import Foundation

/// Downloads a file with real progress reporting via URLSession delegate.
actor FastDownloader {
    private let request: DownloadRequest
    private let destination: URL
    private let fileManager = FileManager.default

    init(url: URL, destination: URL) {
        self.request = DownloadRequest(streamURL: url, pageURL: url, cookies: [], userAgent: UserAgents.app)
        self.destination = destination
    }

    init(request: DownloadRequest, destination: URL) {
        self.request = request
        self.destination = destination
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
}
