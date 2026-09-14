import Foundation

/// Streams normal network data chunks to disk. Unlike `URLSession.AsyncBytes`,
/// it never resumes an async loop for every individual byte.
final class ChunkedDataDownload: NSObject, URLSessionDataDelegate {
    typealias Progress = (Int64, Int64?) -> Void

    private let request: URLRequest
    private let destination: URL
    private let progress: Progress

    private var session: URLSession?
    private var continuation: CheckedContinuation<URL, Error>?
    private var fileHandle: FileHandle?
    private var progressTracker = TransferProgressTracker(totalBytes: nil)
    private var finished = false

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
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            session.dataTask(with: request).resume()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            completionHandler(.cancel)
            finish(throwing: FastDownloader.DownloadError.invalidResponse)
            return
        }

        let length = response.expectedContentLength > 0 ? response.expectedContentLength : nil
        progressTracker = TransferProgressTracker(totalBytes: length)

        do {
            try? FileManager.default.removeItem(at: destination)
            FileManager.default.createFile(atPath: destination.path, contents: nil)
            fileHandle = try FileHandle(forWritingTo: destination)
            progress(0, length)
            completionHandler(.allow)
        } catch {
            completionHandler(.cancel)
            finish(throwing: error)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !finished, let fileHandle else { return }
        do {
            try fileHandle.write(contentsOf: data)
            progress(progressTracker.record(chunkByteCount: data.count), progressTracker.totalBytes)
        } catch {
            dataTask.cancel()
            finish(throwing: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(throwing: error)
        } else {
            finish(returning: destination)
        }
    }

    private func finish(returning url: URL) {
        guard !finished else { return }
        finished = true
        try? fileHandle?.close()
        fileHandle = nil
        session?.finishTasksAndInvalidate()
        continuation?.resume(returning: url)
        continuation = nil
    }

    private func finish(throwing error: Error) {
        guard !finished else { return }
        finished = true
        try? fileHandle?.close()
        fileHandle = nil
        try? FileManager.default.removeItem(at: destination)
        session?.invalidateAndCancel()
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
