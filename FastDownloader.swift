import Foundation

/// Downloads a file with real progress reporting. When the server advertises
/// byte-range support, the file is split into concurrent chunks and combined
/// afterwards; otherwise it falls back to a single streaming download.
actor FastDownloader {
    enum DownloadError: LocalizedError {
        case invalidResponse
        case serverRejectedRange
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "The server returned an invalid response."
            case .serverRejectedRange: return "The server does not support resumable downloads."
            case .failed(let message): return message
            }
        }
    }

    private let request: DownloadRequest
    private let destination: URL
    private let maxConcurrentTasks: Int
    private let fileManager = FileManager.default

    private let chunkMinBytes: Int64 = 1_048_576 // 1 MB

    init(url: URL, destination: URL, concurrentTasks: Int = 4) {
        self.request = DownloadRequest(streamURL: url, pageURL: url, cookies: [], userAgent: "Cachet")
        self.destination = destination
        self.maxConcurrentTasks = max(1, min(concurrentTasks, 8))
    }

    init(request: DownloadRequest, destination: URL, concurrentTasks: Int = 4) {
        self.request = request
        self.destination = destination
        self.maxConcurrentTasks = max(1, min(concurrentTasks, 8))
    }

    /// Downloads the file, reporting `(receivedBytes, totalBytes)` as progress
    /// is made. Returns the finished local file URL.
    func startDownload(progress: @escaping (Int64, Int64?) -> Void) async throws -> URL {
        let download = ChunkedDataDownload(
            request: request.makeURLRequest(),
            destination: destination,
            progress: progress
        )
        return try await download.start()
    }

    // MARK: - Single stream

    private func downloadSingle(totalBytes: Int64?, progress: @escaping (Int64, Int64?) -> Void) async throws {
        var request = self.request.makeURLRequest()
        request.timeoutInterval = 30
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DownloadError.invalidResponse
        }
        let responseTotal = Int64(http.value(forHTTPHeaderField: "Content-Length") ?? "")
        let expectedTotal = responseTotal ?? totalBytes
        progress(0, expectedTotal)
        try await write(bytes: bytes, expectedTotal: expectedTotal, to: destination, progress: progress)
    }

    // MARK: - Concurrent chunks

    private func downloadChunked(totalBytes: Int64, progress: @escaping (Int64, Int64?) -> Void) async throws {
        let chunkSize = totalBytes / Int64(maxConcurrentTasks)

        var tasks: [Task<Void, Error>] = []
        for index in 0..<maxConcurrentTasks {
            let start = Int64(index) * chunkSize
            let end = (index == maxConcurrentTasks - 1) ? totalBytes - 1 : (start + chunkSize - 1)

            tasks.append(Task {
                try await self.downloadChunk(start: start, end: end, index: index)
            })
        }

        for task in tasks {
            try await task.value
        }

        try combineChunks()
    }

    private func downloadChunk(start: Int64, end: Int64, index: Int) async throws {
        var request = self.request.makeURLRequest()
        request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        request.timeoutInterval = 120

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw DownloadError.invalidResponse }

        // A 200 here means the server ignored our Range header. Fall back to a
        // single-stream download instead of duplicating the whole file.
        guard http.statusCode == 206 else {
            throw DownloadError.serverRejectedRange
        }

        let partURL = destination.appendingPathExtension("part\(index)")
        try await write(bytes: bytes, expectedTotal: end - start + 1, to: partURL, progress: nil)
    }

    private func validatesRangeSupport() async throws -> Bool {
        var request = self.request.makeURLRequest()
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.timeoutInterval = 20
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 206 && http.value(forHTTPHeaderField: "Content-Range") != nil
    }

    // MARK: - Streaming write

    private func write(bytes: URLSession.AsyncBytes,
                       expectedTotal: Int64?,
                       to url: URL,
                       progress: ((Int64, Int64?) -> Void)?) async throws {
        try? fileManager.removeItem(at: url)
        fileManager.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        let bufferSize = 64 * 1024
        var buffer = Data(capacity: bufferSize)
        var received: Int64 = 0

        // Progress is reported only for the primary stream so speed and
        // percentages stay smooth even with many chunks running.
        var lastReport = Date.distantPast
        let reportInterval = 0.3

        for try await byte in bytes {
            buffer.append(byte)
            received += 1
            if buffer.count >= bufferSize {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
                if let progress = progress {
                    let now = Date()
                    if now.timeIntervalSince(lastReport) >= reportInterval {
                        progress(received, expectedTotal)
                        lastReport = now
                    }
                }
            }
        }

        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }

        if let progress = progress {
            progress(received, expectedTotal)
        }
    }

    // MARK: - Combine

    private func combineChunks() throws {
        var chunks = [URL]()

        for index in 0..<maxConcurrentTasks {
            let partURL = destination.appendingPathExtension("part\(index)")
            guard fileManager.fileExists(atPath: partURL.path) else {
                throw DownloadError.failed("Download was interrupted while assembling the file.")
            }
            chunks.append(partURL)
        }

        try? fileManager.removeItem(at: destination)
        fileManager.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        let chunkSize = 1 * 1024 * 1024
        for chunkURL in chunks {
            let handleRead = try FileHandle(forReadingFrom: chunkURL)
            defer { try? handleRead.close() }

            while let data = try handleRead.read(upToCount: chunkSize), !data.isEmpty {
                try handle.write(contentsOf: data)
            }

            try? fileManager.removeItem(at: chunkURL)
        }
    }
}
