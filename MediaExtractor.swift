import Foundation
import WebKit

/// Navigates a hidden WKWebView to a page, sniffs out the underlying video
/// stream (direct MP4 or HLS manifest) and returns it. One instance per
/// extraction, so multiple downloads can sniff simultaneously.
@MainActor
final class MediaExtractor: NSObject, WKNavigationDelegate, WKScriptMessageHandler {

    private var webView: WKWebView!
    private var continuation: CheckedContinuation<URL?, Never>?
    private let sniffTimeout: TimeInterval = 30

    private static let directExtensions = ["mp4", "m4v", "mov", "webm", "mkv", "3gp", "avi", "m4a", "mp3", "aac"]

    /// Load `targetURL`, wait up to `sniffTimeout` seconds, and return the
    /// media stream URL (or nil if none was found).
    func extract(from targetURL: URL) async -> URL? {
        let scriptSource = """
            (function() {
                function report(type, url) {
                    if (!url) return;
                    window.webkit.messageHandlers.mediaHandler.postMessage({ type: type, url: url });
                }

                function mediaFromElement(video) {
                    if (!video) return null;
                    if (video.currentSrc && video.currentSrc.length) return video.currentSrc;
                    if (video.src && video.src.length) return video.src;
                    var source = video.querySelector('source[src]');
                    return source ? source.src : null;
                }

                function scan() {
                    document.querySelectorAll('video').forEach(function(v) {
                        var m = mediaFromElement(v);
                        if (m) report('video_tag', m);
                    });
                }

                var origFetch = window.fetch;
                window.fetch = async function() {
                    var response = await origFetch.apply(this, arguments);
                    var lower = (response.url || '').toLowerCase();
                    if (lower.indexOf('.m3u8') !== -1 || lower.indexOf('.mp4') !== -1 || lower.indexOf('.m4v') !== -1) {
                        report('fetch', response.url);
                    }
                    return response;
                };

                document.addEventListener('play', function(e) {
                    if (e.target && e.target.tagName === 'VIDEO') {
                        var m = mediaFromElement(e.target);
                        if (m) report('video_tag', m);
                    }
                }, true);

                var observer = new MutationObserver(function() { scan(); });
                observer.observe(document.documentElement, { childList: true, subtree: true });
                scan();
            })();
            """

        let config = WKWebViewConfiguration()
        let script = WKUserScript(source: scriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        config.userContentController.addUserScript(script)
        config.userContentController.add(self, name: "mediaHandler")

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

        return await withCheckedContinuation { continuation in
            self.continuation = continuation

            var request = URLRequest(url: targetURL)
            request.timeoutInterval = self.sniffTimeout
            webView.load(request)

            let timeout = self.sniffTimeout
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.finish()
            }
        }
    }

    // MARK: - Completion

    private func finish(with url: URL? = nil) {
        guard let continuation = continuation else { return }
        self.continuation = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mediaHandler")
        webView = nil
        continuation.resume(returning: url)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if Self.isMediaURL(url) {
            finish(with: url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "mediaHandler",
              let dict = message.body as? [String: String],
              let urlString = dict["url"],
              let url = URL(string: urlString) else { return }
        if Self.isMediaURL(url) {
            finish(with: url)
        }
    }

    // MARK: - Helpers

    static func isMediaURL(_ url: URL) -> Bool {
        let absolute = url.absoluteString.lowercased()
        if absolute.contains(".m3u8") { return true }
        let ext = url.pathExtension.lowercased()
        return !ext.isEmpty && directExtensions.contains(ext)
    }

    /// Maps a discovered URL to the kind of download it needs.
    static func kind(for url: URL) -> MediaKind {
        let absolute = url.absoluteString.lowercased()
        if absolute.contains(".m3u8") { return .hls }
        return isMediaURL(url) ? .direct : .unknown
    }
}