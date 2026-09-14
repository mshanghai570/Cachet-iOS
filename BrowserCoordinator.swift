import Combine
import Foundation
import WebKit

@MainActor
final class BrowserCoordinator: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
    @Published private(set) var address = "https://duckduckgo.com/"
    @Published private(set) var pageTitle = "Browser"
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var candidates: [MediaCandidate] = []
    @Published private(set) var adBlockingEnabled = true

    let webView: WKWebView
    private var catalog = MediaCandidateCatalog()
    private let contentController: WKUserContentController
    private let contentRuleIdentifier = "CachetAdBlock"

    override init() {
        contentController = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        contentController.add(self, name: "mediaCandidate")
        contentController.addUserScript(WKUserScript(source: Self.detectorScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        webView.navigationDelegate = self
        webView.customUserAgent = UserAgents.browser
        setAdBlocking(enabled: true)
    }

    func start() {
        load(address)
    }

    func load(_ rawAddress: String) {
        let trimmed = rawAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let url: URL?
        if trimmed.contains(" ") || (!trimmed.contains(".") && !trimmed.hasPrefix("http")) {
            var components = URLComponents(string: "https://duckduckgo.com/")!
            components.queryItems = [URLQueryItem(name: "q", value: trimmed)]
            url = components.url
        } else {
            url = DownloadManager.normalizedURL(trimmed)
        }
        guard let url else { return }
        catalog = MediaCandidateCatalog()
        candidates = []
        webView.load(URLRequest(url: url))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reloadOrStop() {
        if isLoading {
            webView.stopLoading()
        } else {
            webView.reload()
        }
    }

    func setAdBlocking(enabled: Bool) {
        adBlockingEnabled = enabled
        contentController.removeAllContentRuleLists()
        guard enabled else { return }
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: contentRuleIdentifier, encodedContentRuleList: Self.contentRules) { [weak self] list, _ in
            guard let self, let list else { return }
            Task { @MainActor in
                guard self.adBlockingEnabled else { return }
                self.contentController.add(list)
            }
        }
    }

    func downloadRequest(for candidate: MediaCandidate) async -> DownloadRequest {
        let cookies = await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        return DownloadRequest(
            streamURL: candidate.streamURL,
            pageURL: candidate.pageURL,
            cookies: cookies,
            userAgent: webView.customUserAgent ?? "Cachet",
            referer: candidate.pageURL.absoluteString
        )
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        refreshNavigationState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        address = webView.url?.absoluteString ?? address
        pageTitle = webView.title?.isEmpty == false ? webView.title! : (webView.url?.host ?? "Browser")
        refreshNavigationState()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        refreshNavigationState()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        refreshNavigationState()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "mediaCandidate",
              let rawURL = message.body as? String,
              let streamURL = URL(string: rawURL),
              let kind = MediaURLClassifier.kind(for: streamURL),
              let pageURL = webView.url else { return }
        catalog.insert(MediaCandidate(streamURL: streamURL, kind: kind, pageURL: pageURL))
        candidates = catalog.candidates
    }

    private func refreshNavigationState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    private static let contentRules = """
    [
      {"trigger":{"url-filter":".*(doubleclick|googlesyndication|google-analytics|adservice|adnxs|taboola|outbrain).*"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*","resource-type":["popup"]},"action":{"type":"block"}}
    ]
    """

    private static let detectorScript = """
    (function() {
      function send(value) {
        if (value && window.webkit && window.webkit.messageHandlers.mediaCandidate) {
          window.webkit.messageHandlers.mediaCandidate.postMessage(value);
        }
      }
      function scan() {
        document.querySelectorAll('video, audio, source').forEach(function(element) {
          send(element.currentSrc || element.src);
        });
      }
      var fetchOriginal = window.fetch;
      window.fetch = function() {
        return fetchOriginal.apply(this, arguments).then(function(response) { send(response.url); return response; });
      };
      var openOriginal = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url) { send(url); return openOriginal.apply(this, arguments); };
      document.addEventListener('play', scan, true);
      new MutationObserver(scan).observe(document.documentElement, { childList: true, subtree: true });
      scan();
    })();
    """
}
