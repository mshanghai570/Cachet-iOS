import AVFoundation
import Foundation
import SwiftUI

@MainActor
final class DownloadManager: ObservableObject {
    @Published var downloads: [DownloadItem] = []

    private var downloadsDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private struct SpeedSample {
        var received: Int64
        var date: Date
        var bytesPerSecond: Double
    }
    private var speedSamples: [UUID: SpeedSample] = [:]

    // MARK: - Public API

    func addDownload(url rawString: String) {
        guard let url = Self.normalizedURL(rawString) else { return }

        let item = DownloadItem(
            title: Self.displayTitle(for: url),
            urlString: url.absoluteString
        )
        downloads.insert(item, at: 0)

        Task { await process(url, itemID: item.id) }
    }

    func enqueue(_ request: DownloadRequest) {
        let item = DownloadItem(
            title: Self.displayTitle(for: request.streamURL),
            urlString: request.streamURL.absoluteString,
            kind: MediaURLClassifier.kind(for: request.streamURL) ?? .unknown
        )
        downloads.insert(item, at: 0)
        Task { await process(request, itemID: item.id) }
    }

    func delete(_ item: DownloadItem) {
        if let fileURL = item.fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        speedSamples[item.id] = nil
        downloads.removeAll { $0.id == item.id }
    }

    func clearFinished() {
        for item in downloads where item.status == .done {
            delete(item)
        }
    }

    // MARK: - Detection + dispatch

    private func process(_ sourceURL: URL, itemID: UUID) async {
        var mediaURL = sourceURL
        var kind = MediaExtractor.kind(for: sourceURL)

        if kind == .unknown {
            update(itemID) {
                $0.status = .extracting
                $0.sizeString = "Scanning link…"
            }

            let extractor = MediaExtractor()
            guard let found = await extractor.extract(from: sourceURL) else {
                fail(itemID, "Couldn't find a video on that page.")
                return
            }

            mediaURL = found
            update(itemID) {
                $0.urlString = mediaURL.absoluteString
                $0.title = Self.displayTitle(for: mediaURL)
            }
            kind = MediaExtractor.kind(for: mediaURL)
            guard kind != .unknown else {
                fail(itemID, "Couldn't find a downloadable video stream.")
                return
            }
        }

        update(itemID) { $0.kind = kind }

        switch kind {
        case .hls:
            await downloadHLS(id: itemID, url: mediaURL)
        default:
            await downloadDirect(id: itemID, url: mediaURL)
        }
    }

    private func process(_ request: DownloadRequest, itemID: UUID) async {
        update(itemID) { $0.kind = MediaURLClassifier.kind(for: request.streamURL) ?? .unknown }
        switch DownloadRoute(request: request) {
        case .direct:
            await downloadDirect(id: itemID, request: request)
        case .hls:
            await downloadHLS(id: itemID, request: request)
        case .unsupported:
            fail(itemID, "This stream format is not supported.")
        }
    }

    // MARK: - Direct download

    private func downloadDirect(id: UUID, url: URL) async {
        await downloadDirect(id: id, request: DownloadRequest(streamURL: url, pageURL: url, cookies: [], userAgent: "Cachet"))
    }

    private func downloadDirect(id: UUID, request: DownloadRequest) async {
        let url = request.streamURL
        let ext = url.pathExtension.lowercased().isEmpty ? "mp4" : url.pathExtension.lowercased()
        let fileURL = uniqueFileURL(for: url, extension: ext)
        let downloader = FastDownloader(request: request, destination: fileURL)

        update(id) {
            $0.status = .downloading
            $0.sizeString = "Connecting…"
        }

        do {
            _ = try await downloader.startDownload(progress: { [weak self] received, total in
                self?.trackProgress(id: id, received: received, total: total)
            })
        } catch {
            fail(id, error.localizedDescription)
            return
        }

        finishSuccess(id: id, fileURL: fileURL)
    }

    private func trackProgress(id: UUID, received: Int64, total: Int64?) {
        Task { @MainActor [weak self] in
            self?.applyProgress(id: id, received: received, total: total)
        }
    }

    private func applyProgress(id: UUID, received: Int64, total: Int64?) {
        guard let index = downloads.firstIndex(where: { $0.id == id }),
              downloads[index].status == .downloading else { return }

        let now = Date()
        var item = downloads[index]
        item.receivedBytes = received
        if let total = total {
            item.totalBytes = total
            if total > 0 {
                item.progress = min(1.0, Double(received) / Double(total))
                if received == 0 {
                    item.sizeString = "Connected · " + Self.byteString(Double(total))
                }
            }
        }

        if let previous = speedSamples[id] {
            let deltaTime = now.timeIntervalSince(previous.date)
            let deltaBytes = received - previous.received
            if deltaTime >= 0.1, deltaBytes > 0 {
                let instantSpeed = Double(deltaBytes) / deltaTime
                // Exponential moving average for smooth display
                let alpha = 0.3
                let smoothedSpeed = previous.bytesPerSecond > 0
                    ? alpha * instantSpeed + (1 - alpha) * previous.bytesPerSecond
                    : instantSpeed
                item.speedString = Self.speedString(smoothedSpeed)
                item.sizeString = Self.byteString(Double(received)) + " of " + Self.byteString(Double(total ?? received))
                speedSamples[id] = SpeedSample(received: received, date: now, bytesPerSecond: smoothedSpeed)
            }
        } else {
            speedSamples[id] = SpeedSample(received: received, date: now, bytesPerSecond: 0)
        }

        downloads[index] = item
    }

    // MARK: - HLS export

    private func downloadHLS(id: UUID, url: URL) async {
        await downloadHLS(id: id, request: DownloadRequest(streamURL: url, pageURL: url, cookies: [], userAgent: "Cachet"))
    }

    private func downloadHLS(id: UUID, request: DownloadRequest) async {
        let url = request.streamURL
        update(id) {
            $0.status = .downloading
            $0.sizeString = "Preparing HLS stream…"
        }

        let outputURL = uniqueFileURL(for: url, extension: "mp4")
        let asset = AVURLAsset(url: url)

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            fail(id, "This HLS stream can't be exported.")
            return
        }

        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        let poller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000)
                await MainActor.run {
                    guard let self = self,
                          let index = self.downloads.firstIndex(where: { $0.id == id }),
                          self.downloads[index].status == .downloading else { return }
                    self.downloads[index].progress = Double(session.progress)
                    self.downloads[index].sizeString = "Exporting \(Int(session.progress * 100))%"
                }
            }
        }

        await withCheckedContinuation { continuation in
            session.exportAsynchronously { continuation.resume() }
        }
        poller.cancel()

        guard session.status == .completed else {
            fail(id, session.error?.localizedDescription ?? "HLS export failed.")
            return
        }

        finishSuccess(id: id, fileURL: outputURL)
    }

    // MARK: - Completion / failure

    private func finishSuccess(id: UUID, fileURL: URL) {
        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        speedSamples[id] = nil

        update(id) {
            $0.status = .done
            $0.progress = 1.0
            $0.receivedBytes = Int64(size)
            $0.totalBytes = Int64(size)
            $0.speedString = ""
            $0.sizeString = Self.byteString(Double(size))
            $0.errorMessage = nil
            $0.fileURL = fileURL
        }
    }

    private func fail(_ id: UUID, _ message: String) {
        speedSamples[id] = nil
        update(id) {
            $0.status = .failed
            $0.errorMessage = message
            $0.sizeString = message
        }
    }

    private func update(_ id: UUID, _ mutate: (inout DownloadItem) -> Void) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        mutate(&downloads[index])
    }

    // MARK: - Helpers

    private func uniqueFileURL(for url: URL, extension ext: String) -> URL {
        var base = url.deletingPathExtension().lastPathComponent
        let cleaned = base.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        base = cleaned.isEmpty ? "Video" : String(cleaned.prefix(60))

        guard !FileManager.default.fileExists(atPath: downloadsDirectory.appendingPathComponent("\(base).\(ext)").path) else {
            var counter = 1
            while FileManager.default.fileExists(atPath: downloadsDirectory.appendingPathComponent("\(base) \(counter).\(ext)").path) {
                counter += 1
            }
            return downloadsDirectory.appendingPathComponent("\(base) \(counter).\(ext)")
        }
        return downloadsDirectory.appendingPathComponent("\(base).\(ext)")
    }

    static func normalizedURL(_ raw: String) -> URL? {
        var candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }
        let lower = candidate.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            candidate = "https://" + candidate
        }
        return URL(string: candidate)
    }

    static func displayTitle(for url: URL) -> String {
        let last = url.deletingPathExtension().lastPathComponent
        if !last.isEmpty, last != "/" { return last }
        return url.host ?? "Video"
    }

    static func speedString(_ bytesPerSecond: Double) -> String {
        let value = max(0, bytesPerSecond)
        let units = ["B", "KB", "MB", "GB"]
        var scaled = value
        var unit = 0
        while scaled >= 1024, unit < units.count - 1 {
            scaled /= 1024
            unit += 1
        }
        return String(format: "%.1f %@/s", scaled, units[unit])
    }

    static func byteString(_ bytes: Double) -> String {
        if bytes < 0 { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var scaled = bytes
        var unit = 0
        while scaled >= 900 && unit < units.count - 1 {
            scaled /= 1024
            unit += 1
        }
        if unit == 0 { return "\(Int(scaled)) \(units[unit])" }
        return String(format: "%.1f %@", scaled, units[unit])
    }
}
