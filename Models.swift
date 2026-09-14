import Foundation

enum DownloadStatus: String {
    case queued
    case extracting
    case downloading
    case done
    case failed
}

enum MediaKind: String {
    case unknown
    case direct
    case hls
}

enum MediaURLClassifier {
    private static let directExtensions: Set<String> = [
        "mp4", "m4v", "mov", "webm", "mkv", "3gp", "avi", "m4a", "mp3", "aac"
    ]

    static func kind(for url: URL) -> MediaKind? {
        let address = url.absoluteString.lowercased()
        if address.contains(".m3u8") { return .hls }
        return directExtensions.contains(url.pathExtension.lowercased()) ? .direct : nil
    }
}

struct MediaCandidate: Identifiable, Hashable {
    let streamURL: URL
    let kind: MediaKind
    let pageURL: URL
    let source: String

    init(streamURL: URL, kind: MediaKind, pageURL: URL, source: String = "Detected stream") {
        self.streamURL = streamURL
        self.kind = kind
        self.pageURL = pageURL
        self.source = source
    }

    var id: String { streamURL.absoluteString }

    var label: String {
        switch kind {
        case .direct:
            return streamURL.pathExtension.uppercased().isEmpty ? "Video file" : streamURL.pathExtension.uppercased()
        case .hls:
            return "HLS stream"
        case .unknown:
            return "Video stream"
        }
    }
}

struct MediaCandidateCatalog: Equatable {
    private(set) var candidates: [MediaCandidate]

    init(candidates: [MediaCandidate] = []) {
        self.candidates = []
        for candidate in candidates {
            insert(candidate)
        }
    }

    mutating func insert(_ candidate: MediaCandidate) {
        guard !candidates.contains(where: { $0.streamURL == candidate.streamURL }) else { return }
        candidates.append(candidate)
        candidates.sort { lhs, rhs in
            Self.rank(lhs) > Self.rank(rhs)
        }
    }

    var bestCandidate: MediaCandidate? { candidates.first }

    private static func rank(_ candidate: MediaCandidate) -> Int {
        switch candidate.kind {
        case .direct: return 2
        case .hls: return 1
        case .unknown: return 0
        }
    }
}

struct DownloadRequest {
    let streamURL: URL
    let pageURL: URL
    let cookies: [HTTPCookie]
    let userAgent: String
    let referer: String

    init(streamURL: URL, pageURL: URL, cookies: [HTTPCookie], userAgent: String, referer: String? = nil) {
        self.streamURL = streamURL
        self.pageURL = pageURL
        self.cookies = cookies
        self.userAgent = userAgent
        self.referer = referer ?? pageURL.absoluteString
    }

    func makeURLRequest() -> URLRequest {
        var request = URLRequest(url: streamURL)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        for (field, value) in HTTPCookie.requestHeaderFields(with: cookies) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }
}

enum TransferMode: Equatable {
    case singleStream
    case chunked(taskCount: Int)
}

struct TransferPolicy: Equatable {
    let mode: TransferMode

    init(responseStatus: Int, acceptsRanges: Bool, contentLength: Int64?, maximumTasks: Int = 4) {
        let supportsRanges = responseStatus == 206 && acceptsRanges
        if supportsRanges, let contentLength, contentLength >= 1_048_576, maximumTasks > 1 {
            mode = .chunked(taskCount: min(maximumTasks, 4))
        } else {
            mode = .singleStream
        }
    }
}

struct TransferStartupPolicy: Equatable {
    let startsWithSingleStream = true
}

struct TransferBootstrapPolicy: Equatable {
    let mode: TransferMode

    init(responseStatus: Int, acceptsRanges: Bool, contentLength: Int64?, maximumTasks: Int = 4) {
        // CDN headers are advisory. A real range validation must happen before
        // a future optimization replaces the already-working GET stream.
        mode = .singleStream
    }
}

struct TransferProgressTracker: Equatable {
    let totalBytes: Int64?
    private(set) var receivedBytes: Int64 = 0

    init(totalBytes: Int64?) {
        self.totalBytes = totalBytes
    }

    mutating func record(chunkByteCount: Int) -> Int64 {
        receivedBytes += Int64(chunkByteCount)
        return receivedBytes
    }

    var fractionCompleted: Double {
        guard let totalBytes, totalBytes > 0 else { return 0 }
        return min(1, Double(receivedBytes) / Double(totalBytes))
    }
}

enum DownloadRoute: Equatable {
    case direct
    case hls
    case unsupported

    init(request: DownloadRequest) {
        if request.streamURL.absoluteString.lowercased().contains(".m3u8") {
            self = .hls
        } else if !request.streamURL.pathExtension.isEmpty {
            self = .direct
        } else {
            self = .unsupported
        }
    }
}

struct DownloadItem: Identifiable, Equatable {
    let id: UUID
    var title: String
    var urlString: String
    var kind: MediaKind
    var progress: Double
    var receivedBytes: Int64
    var totalBytes: Int64?
    var speedString: String
    var sizeString: String
    var status: DownloadStatus
    var errorMessage: String?
    var fileURL: URL?

    init(id: UUID = UUID(),
         title: String,
         urlString: String,
         kind: MediaKind = .unknown,
         progress: Double = 0.0,
         receivedBytes: Int64 = 0,
         totalBytes: Int64? = nil,
         speedString: String = "0 B/s",
         sizeString: String = "Preparing",
         status: DownloadStatus = .queued,
         errorMessage: String? = nil,
         fileURL: URL? = nil) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.kind = kind
        self.progress = progress
        self.receivedBytes = receivedBytes
        self.totalBytes = totalBytes
        self.speedString = speedString
        self.sizeString = sizeString
        self.status = status
        self.errorMessage = errorMessage
        self.fileURL = fileURL
    }
}
