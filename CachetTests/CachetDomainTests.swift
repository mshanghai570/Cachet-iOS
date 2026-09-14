import Foundation

@main
struct CachetDomainTests {
    static func main() {
        testCatalogDeduplicatesStreamURLs()
        testSessionRequestIncludesReferer()
        testUnvalidatedRangeUsesSingleStream()
        testMediaURLClassifierRecognizesSupportedMedia()
        testTransferStartupStartsWithSingleStream()
        testUnverifiedRangeAdvertisementStaysSingleStream()
        testChunkProgressTracksReceivedData()
        print("Cachet domain tests passed")
    }

    private static func testCatalogDeduplicatesStreamURLs() {
        var catalog = MediaCandidateCatalog()
        let stream = URL(string: "https://cdn.example/video.m3u8?token=1")!
        let page = URL(string: "https://example.com/watch")!
        catalog.insert(MediaCandidate(streamURL: stream, kind: .hls, pageURL: page))
        catalog.insert(MediaCandidate(streamURL: stream, kind: .hls, pageURL: page))
        precondition(catalog.candidates.count == 1, "Equivalent media URLs must be deduplicated")
    }

    private static func testSessionRequestIncludesReferer() {
        let request = DownloadRequest(
            streamURL: URL(string: "https://cdn.example/video.mp4")!,
            pageURL: URL(string: "https://example.com/watch")!,
            cookies: [],
            userAgent: "Cachet Test",
            referer: "https://example.com/watch"
        )
        let urlRequest = request.makeURLRequest()
        precondition(urlRequest.value(forHTTPHeaderField: "Referer") == "https://example.com/watch")
        precondition(urlRequest.value(forHTTPHeaderField: "User-Agent") == "Cachet Test")
    }

    private static func testUnvalidatedRangeUsesSingleStream() {
        let policy = TransferPolicy(responseStatus: 200, acceptsRanges: false, contentLength: 20_000_000)
        precondition(policy.mode == .singleStream, "A server that ignores ranges must use one stream")
    }

    private static func testMediaURLClassifierRecognizesSupportedMedia() {
        precondition(MediaURLClassifier.kind(for: URL(string: "https://cdn.example/video.mp4")!) == .direct)
        precondition(MediaURLClassifier.kind(for: URL(string: "https://cdn.example/master.m3u8")!) == .hls)
        precondition(MediaURLClassifier.kind(for: URL(string: "https://example.com/watch")!) == nil)
    }

    private static func testTransferStartupStartsWithSingleStream() {
        precondition(TransferStartupPolicy().startsWithSingleStream, "Downloads must start the authenticated GET without a HEAD or range probe")
    }

    private static func testUnverifiedRangeAdvertisementStaysSingleStream() {
        let policy = TransferBootstrapPolicy(responseStatus: 200, acceptsRanges: true, contentLength: 20_000_000)
        precondition(policy.mode == .singleStream, "An advertised range capability must not interrupt a working stream")
    }

    private static func testChunkProgressTracksReceivedData() {
        var progress = TransferProgressTracker(totalBytes: 1_000)
        precondition(progress.record(chunkByteCount: 256) == 256)
        precondition(progress.record(chunkByteCount: 744) == 1_000)
        precondition(progress.fractionCompleted == 1)
    }
}
