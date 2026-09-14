import Foundation

/// Streams a remote file to disk with real progress reporting via URLSession
/// delegate callbacks. Starts with a plain GET and writes bytes straight to
/// disk, so small files and range-unfriendly servers never wait on extra
/// requests. When the server advertises byte ranges and the file is large
/// enough, a `bytes=0-0` probe validates range support, then the download
/// upgrades to up to 8 concurrent ranged streams — which defeats the
/// per-connection throttling that slows a single stream to a crawl — and the
/// finished parts are concatenated into the destination file.
final class ChunkedDataDownload: NSObject, URLSessionDataDelegate {
    typealias Progress = (Int64, Int64?) -> Void

    enum DownloadError: LocalizedError {
        case invalidResponse
        case partWriteFailed

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "The server returned an invalid response while downloading."
            case .partWriteFailed:
                return "Couldn't write a chunk of the download."
            }
        }
    }

    private enum Mode {
        case singleStream
        case chunked
    }

    private let request: URLRequest
    private let destination: URL
    private let progress: Progress

    private var session: URLSession?
    private var continuation: CheckedContinuation<URL, Error>?
    private var fileHandle: FileHandle?
    private var finished = false

    private var mode: Mode = .singleStream
    private var declaredTotal: Int64?
    private var receivedBytes: Int64 = 0

    private var initialTask: URLSessionDataTask?
    private var initialTaskID = -1
    private var probeTaskID: Int?
    private var probeFailed = false

    private var chunkCount = 0
    private var chunkRanges: [Int: ClosedRange<Int64>] = [:]
    private var partFiles: [Int: URL] = [:]
    private var partHandles: [Int: FileHandle] = [:]
    private var chunkTasks: [Int: URLSessionDataTask] = [:]
    private var taskIndex: [Int: Int] = [:]
    private var chunkAttempts: [Int: Int] = [:]
    private var completedParts: Set<Int> = []

    init(request: URLRequest, destination: URL, progress: @escaping Progress) {
        self.request = request
        self.destination = destination
        self.progress = progress
    }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 0
            configuration.waitsForConnectivity = true
            configuration.httpMaximumConnectionsPerHost = Self.maximumChunks
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            let task = session.dataTask(with: request)
            initialTask = task
            initialTaskID = task.taskIdentifier
            task.resume()
        }
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard !finished else {
            completionHandler(.cancel)
            return
        }
        let identifier = dataTask.taskIdentifier
        if identifier == probeTaskID {
            handleProbeResponse(response, completionHandler: completionHandler)
        } else if identifier == initialTaskID, mode == .singleStream {
            handleInitialResponse(response, completionHandler: completionHandler)
        } else if let index = taskIndex[identifier] {
            handleChunkResponse(index, response, completionHandler: completionHandler)
        } else {
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !finished else { return }
        let identifier = dataTask.taskIdentifier
        if identifier == initialTaskID, mode == .singleStream {
            guard let fileHandle else { return }
            do {
                try fileHandle.write(contentsOf: data)
                receivedBytes += Int64(data.count)
                progress(receivedBytes, declaredTotal)
            } catch {
                dataTask.cancel()
                finish(throwing: error)
            }
        } else if let index = taskIndex[identifier] {
            writeChunkData(index, data: data)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished else { return }
        let identifier = task.taskIdentifier

        if identifier == initialTaskID {
            if mode == .singleStream {
                if let error {
                    finish(throwing: error)
                } else {
                    finish(returning: destination)
                }
            }
            return
        }

        if identifier == probeTaskID {
            probeTaskID = nil
            return
        }

        if let index = taskIndex[identifier] {
            taskIndex[identifier] = nil
            chunkTasks[identifier] = nil
            if let error {
                failChunk(index, error: error)
            } else {
                completeChunk(index)
            }
        }
    }

    // MARK: - Single-stream setup

    private func handleInitialResponse(_ response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            completionHandler(.cancel)
            finish(throwing: DownloadError.invalidResponse)
            return
        }

        let length = response.expectedContentLength > 0 ? response.expectedContentLength : nil
        declaredTotal = length
        receivedBytes = 0

        do {
            try openDestinationFile()
        } catch {
            completionHandler(.cancel)
            finish(throwing: error)
            return
        }

        progress(0, declaredTotal)

        let acceptsRanges = http.value(forHTTPHeaderField: "Accept-Ranges")?
            .lowercased().contains("bytes") ?? false
        if acceptsRanges, let length, length >= Self.minimumChunkedSize, !probeFailed {
            startProbe()
        }

        completionHandler(.allow)
    }

    private func openDestinationFile() throws {
        try? FileManager.default.removeItem(at: destination)
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: destination)
    }

    // MARK: - Range probe

    private func startProbe() {
        var probeRequest = request
        probeRequest.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        probeRequest.cachePolicy = .reloadIgnoringLocalCacheData
        let task = session!.dataTask(with: probeRequest)
        probeTaskID = task.taskIdentifier
        task.resume()
    }

    private func handleProbeResponse(_ response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        completionHandler(.cancel)
        probeTaskID = nil

        let isSupported: Bool
        if let http = response as? HTTPURLResponse,
           http.statusCode == 206,
           let range = http.value(forHTTPHeaderField: "Content-Range") {
            isSupported = Self.total(fromContentRange: range) == declaredTotal
        } else {
            isSupported = false
        }

        if isSupported {
            beginChunked()
        } else {
            probeFailed = true
        }
    }

    // MARK: - Chunked download

    private func beginChunked() {
        guard let total = declaredTotal, total > 0 else {
            probeFailed = true
            return
        }

        mode = .chunked
        receivedBytes = 0
        initialTask?.cancel()
        initialTask = nil
        try? fileHandle?.close()
        fileHandle = nil
        try? FileManager.default.removeItem(at: destination)

        chunkCount = Self.chunkCount(for: total)
        var start: Int64 = 0
        for index in 0..<chunkCount {
            let end = min(total - 1, start + Self.chunkSize - 1)
            chunkRanges[index] = start...end
            partFiles[index] = destination.appendingPathExtension("part\(index)")
            start = end + 1
        }

        progress(0, total)
        for index in 0..<chunkCount {
            spawnChunk(index)
        }
    }

    private func spawnChunk(_ index: Int) {
        guard let range = chunkRanges[index], let partURL = partFiles[index] else { return }
        chunkAttempts[index, default: 0] += 1

        try? FileManager.default.removeItem(at: partURL)
        FileManager.default.createFile(atPath: partURL.path, contents: nil)

        var chunkRequest = request
        chunkRequest.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range")
        let task = session!.dataTask(with: chunkRequest)
        taskIndex[task.taskIdentifier] = index
        chunkTasks[task.taskIdentifier] = task
        task.resume()
    }

    private func handleChunkResponse(_ index: Int, _ response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.statusCode == 206 else {
            completionHandler(.cancel)
            abortChunkedToSingleStream()
            return
        }

        guard let partURL = partFiles[index],
              let handle = try? FileHandle(forWritingTo: partURL) else {
            completionHandler(.cancel)
            failChunk(index, error: DownloadError.partWriteFailed)
            return
        }
        try? handle.truncate(atOffset: 0)
        partHandles[index] = handle
        completionHandler(.allow)
    }

    private func writeChunkData(_ index: Int, data: Data) {
        guard let handle = partHandles[index] else { return }
        do {
            try handle.write(contentsOf: data)
            receivedBytes += Int64(data.count)
            progress(receivedBytes, declaredTotal)
        } catch {
            failChunk(index, error: error)
        }
    }

    private func completeChunk(_ index: Int) {
        try? partHandles[index]?.close()
        partHandles[index] = nil
        completedParts.insert(index)
        if completedParts.count == chunkCount {
            assembleAndFinish()
        }
    }

    private func failChunk(_ index: Int, error: Error) {
        try? partHandles[index]?.close()
        partHandles[index] = nil
        if chunkAttempts[index, default: 0] < Self.maximumAttemptsPerChunk {
            spawnChunk(index)
        } else {
            abortChunkedToSingleStream()
        }
    }

    private func abortChunkedToSingleStream() {
        mode = .singleStream
        probeFailed = true

        for task in chunkTasks.values {
            task.cancel()
        }
        chunkTasks.removeAll()
        taskIndex.removeAll()
        completedParts.removeAll()

        for (_, handle) in partHandles {
            try? handle.close()
        }
        partHandles.removeAll()

        for part in partFiles.values {
            try? FileManager.default.removeItem(at: part)
        }
        partFiles.removeAll()
        chunkRanges.removeAll()
        chunkAttempts.removeAll()
        chunkCount = 0

        receivedBytes = 0
        declaredTotal = nil

        do {
            try openDestinationFile()
            progress(0, declaredTotal)
        } catch {
            finish(throwing: error)
            return
        }

        let task = session!.dataTask(with: request)
        initialTask = task
        initialTaskID = task.taskIdentifier
        task.resume()
    }

    // MARK: - Assembly

    private func assembleAndFinish() {
        do {
            try? FileManager.default.removeItem(at: destination)
            FileManager.default.createFile(atPath: destination.path, contents: nil)
            let output = try FileHandle(forWritingTo: destination)

            for index in 0..<chunkCount {
                guard let part = partFiles[index] else { continue }
                let input = try FileHandle(forReadingFrom: part)
                while true {
                    let chunk = try input.read(upToCount: Self.assemblyBufferSize)
                    guard let chunk, !chunk.isEmpty else { break }
                    try output.write(contentsOf: chunk)
                }
                try input.close()
            }
            try output.close()

            for part in partFiles.values {
                try? FileManager.default.removeItem(at: part)
            }
            partFiles.removeAll()

            finish(returning: destination)
        } catch {
            finish(throwing: error)
        }
    }

    // MARK: - Teardown

    private func finish(returning url: URL) {
        guard !finished else { return }
        finished = true
        cleanup()
        session?.finishTasksAndInvalidate()
        continuation?.resume(returning: url)
        continuation = nil
    }

    private func finish(throwing error: Error) {
        guard !finished else { return }
        finished = true
        cleanup()
        try? FileManager.default.removeItem(at: destination)
        session?.invalidateAndCancel()
        continuation?.resume(throwing: error)
        continuation = nil
    }

    private func cleanup() {
        try? fileHandle?.close()
        fileHandle = nil
        for (_, handle) in partHandles {
            try? handle.close()
        }
        partHandles.removeAll()
        for part in partFiles.values {
            try? FileManager.default.removeItem(at: part)
        }
        partFiles.removeAll()
        mode = .singleStream
    }

    // MARK: - Constants & helpers

    private static let chunkSize: Int64 = 4 * 1_048_576
    private static let minimumChunkedSize: Int64 = 8 * 1_048_576
    private static let maximumChunks = 8
    private static let maximumAttemptsPerChunk = 3
    private static let assemblyBufferSize = 1_048_576

    private static func chunkCount(for total: Int64) -> Int {
        let bySize = Int((total + Self.chunkSize - 1) / Self.chunkSize)
        return max(2, min(Self.maximumChunks, bySize))
    }

    private static func total(fromContentRange value: String) -> Int64? {
        guard let slash = value.lastIndex(of: "/") else { return nil }
        return Int64(value[value.index(after: slash)...])
    }
}