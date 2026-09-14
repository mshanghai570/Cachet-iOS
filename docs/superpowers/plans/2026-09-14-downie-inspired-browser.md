# Downie-Inspired Browser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver an unsigned Cachet IPA with a fast, session-aware browser that detects and downloads authorized playable video streams.

**Architecture:** A visible `WKWebView` feeds a deduplicated `MediaCandidate` catalog through a coordinator. The download manager receives a `DownloadRequest` carrying browser cookies and headers, then dispatches direct files to a GET-first, range-safe downloader or compatible HLS streams to AVFoundation.

**Tech Stack:** Swift 6, SwiftUI, WebKit, AVFoundation, URLSession, XCTest, Xcode 26.

**Spec:** `docs/superpowers/specs/2026-09-14-downie-inspired-browser-design.md`

## Global Constraints

- Minimum iOS version is 16.0.
- Browser starts at `https://duckduckgo.com/`.
- Ad blocking is default-on and optional in the browser UI.
- Direct transfers retain cookies, user-agent, and `Referer`.
- Do not bypass DRM, encryption, authentication, or access controls.
- Use at most four parallel ranges only after the server validates range support.
- Build using `CODE_SIGNING_ALLOWED=NO` and deliver `Cachet.ipa`.

---

## File Structure

- `Models.swift`: media candidates, browser-aware requests, catalog ranking, transfer policy.
- `BrowserCoordinator.swift`: WebKit bridge, candidate capture, session snapshot, content rules.
- `BrowserView.swift`: browser controls and stream sheet.
- `DownloadManager.swift` and `FastDownloader.swift`: transfers and user-visible errors.
- `CachetTests/CachetTests.swift`: behavior tests.
- `ContentView.swift`, `SettingsView.swift`, project file, documentation, build guide.

### Task 1: Add tested media and transfer models

**Files:** Create `CachetTests/CachetTests.swift`; modify `Models.swift` and `Cachet.xcodeproj/project.pbxproj`.

**Produces:** `MediaCandidate`, `DownloadRequest`, `MediaCandidateCatalog`, `TransferPolicy`, `DownloadRoute`.

- [ ] **Step 1: Write the failing tests**

```swift
func testCatalogDeduplicatesStreamURLs() {
    var catalog = MediaCandidateCatalog()
    let stream = URL(string: "https://cdn.example/video.m3u8?token=1")!
    catalog.insert(.init(streamURL: stream, kind: .hls, pageURL: URL(string: "https://example.com/watch")!))
    catalog.insert(.init(streamURL: stream, kind: .hls, pageURL: URL(string: "https://example.com/watch")!))
    XCTAssertEqual(catalog.candidates.count, 1)
}

func testSessionRequestIncludesReferer() {
    let request = DownloadRequest(streamURL: URL(string: "https://cdn.example/video.mp4")!, pageURL: URL(string: "https://example.com")!, cookies: [], userAgent: "Cachet", referer: "https://example.com")
    XCTAssertEqual(request.makeURLRequest().value(forHTTPHeaderField: "Referer"), "https://example.com")
}

func testUnvalidatedRangeUsesSingleStream() {
    XCTAssertEqual(TransferPolicy(responseStatus: 200, acceptsRanges: false, contentLength: 20_000_000).mode, .singleStream)
}
```

- [ ] **Step 2: Verify red**

Run: `xcodebuild -project Cachet.xcodeproj -scheme Cachet -destination 'platform=iOS Simulator,name=iPhone 16' test`

Expected: FAIL because the test target and types do not exist.

- [ ] **Step 3: Implement minimal models**

```swift
struct MediaCandidate: Identifiable, Hashable {
    let streamURL: URL
    let kind: MediaKind
    let pageURL: URL
    var id: String { streamURL.absoluteString }
}
```

Implement a URL-keyed catalog, best-candidate ranking, request headers, and route/range policy.

- [ ] **Step 4: Verify green**

Run the Task 1 test command. Expected: PASS.

### Task 2: Add browser detection and session capture

**Files:** Create `BrowserCoordinator.swift`; modify `MediaExtractor.swift`, project file, and tests.

**Consumes:** Task 1 models. **Produces:** `@MainActor BrowserCoordinator` exposing web view, state, candidates, `load(_:) `, and `downloadRequest(for:)`.

- [ ] **Step 1: Write failing URL classifier tests**

```swift
func testMediaURLClassifierRecognizesMedia() {
    XCTAssertEqual(MediaURLClassifier.kind(for: URL(string: "https://cdn.example/video.mp4")!), .direct)
    XCTAssertEqual(MediaURLClassifier.kind(for: URL(string: "https://cdn.example/master.m3u8")!), .hls)
}

func testMediaURLClassifierRejectsPage() {
    XCTAssertNil(MediaURLClassifier.kind(for: URL(string: "https://example.com/watch")!))
}
```

- [ ] **Step 2: Verify red**

Run the Task 1 test command. Expected: FAIL because `MediaURLClassifier` is missing.

- [ ] **Step 3: Implement coordinator**

At document start, inject a script that observes `video`/`source` elements plus fetch/XHR URLs and posts direct/HLS candidates to a script handler. Compile a small default-enabled `WKContentRuleList` for advertising, trackers, and popups. Capture cookies via `WKHTTPCookieStore`, user-agent, and page URL for selected downloads. Reuse the classifier from `MediaExtractor`.

- [ ] **Step 4: Verify green**

Run the Task 1 test command. Expected: PASS.

### Task 3: Replace Browser Tool with real browser

**Files:** Create `BrowserView.swift`; modify `ContentView.swift`, `SettingsView.swift`, and project file.

**Consumes:** Task 2 coordinator and Task 4 queue entry point. **Produces:** browser with stream-selection sheet.

- [ ] **Step 1: Write failing ranking test**

```swift
func testCatalogHasBestCandidate() {
    let direct = MediaCandidate(streamURL: URL(string: "https://cdn.example/video.mp4")!, kind: .direct, pageURL: URL(string: "https://example.com")!)
    XCTAssertEqual(MediaCandidateCatalog(candidates: [direct]).bestCandidate, direct)
}
```

- [ ] **Step 2: Verify red**

Run the Task 1 test command. Expected: FAIL until the catalog exposes `bestCandidate`.

- [ ] **Step 3: Implement browser UI**

Wrap the coordinator web view with `UIViewRepresentable`; open DuckDuckGo; add address/search, back, forward, reload/stop, title/progress, close, ad-block toggle, and a detected-count download button. Present “Best available” and each candidate in a native sheet. Persist blocking with `@AppStorage`. Use native controls, 44-point icon controls, labels for icon-only controls, and Dynamic Type styles.

- [ ] **Step 4: Build and verify**

Run: `xcodebuild -project Cachet.xcodeproj -scheme Cachet -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /tmp/cachet-dd build`

Expected: BUILD SUCCEEDED. On device, verify DuckDuckGo, navigation, playback, candidate sheet, and content-block toggle.

### Task 4: Make downloads session-aware and resilient

**Files:** Modify `FastDownloader.swift`, `DownloadManager.swift`, and tests.

**Consumes:** Task 1 `DownloadRequest`. **Produces:** `FastDownloader(request:destination:)` and `DownloadManager.enqueue(_:) `.

- [ ] **Step 1: Write failing routing test**

```swift
func testHLSRequestRoutesToHLSDownload() {
    let request = DownloadRequest(streamURL: URL(string: "https://cdn.example/master.m3u8")!, pageURL: URL(string: "https://example.com")!, cookies: [], userAgent: "Cachet", referer: "https://example.com")
    XCTAssertEqual(DownloadRoute(request: request), .hls)
}
```

- [ ] **Step 2: Verify red**

Run the Task 1 test command. Expected: FAIL until routing exists.

- [ ] **Step 3: Implement transfer behavior**

Start direct transfers with GET and browser request context. Stream immediately if ranges cannot be validated; otherwise require a valid `206` and `Content-Range` before at most four chunks. Aggregate progress, assemble temporary chunks atomically, and always clean them up. Route compatible HLS through AVFoundation and report protected/incompatible playlists. Surface specific authorization, protection, storage, unsupported-format, and network errors.

- [ ] **Step 4: Verify green**

Run the Task 1 test command. Expected: PASS.

### Task 5: Document and package the unsigned IPA

**Files:** Modify `Documentation.md`, `Build.md`; replace workspace `Cachet.ipa`.

- [ ] **Step 1: Document final behavior**

Document browser-guided extraction, optional blocking, session-aware transfers, compatible direct/HLS media, and the explicit DRM/access limits.

- [ ] **Step 2: Run a Release device build**

Run: `/usr/bin/xcodebuild -project Cachet.xcodeproj -scheme Cachet -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /tmp/cachet-dd CODE_SIGNING_ALLOWED=NO build`

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Package and inspect IPA**

Run: `mkdir -p /tmp/cachet-ipa/Payload && cp -R /tmp/cachet-dd/Build/Products/Release-iphoneos/Cachet.app /tmp/cachet-ipa/Payload/ && cd /tmp/cachet-ipa && zip -qr Cachet.ipa Payload && cp Cachet.ipa /Users/michaelshingara/Documents/Cachet-iOS-main/Cachet-iOS/Cachet.ipa && unzip -l /Users/michaelshingara/Documents/Cachet-iOS-main/Cachet-iOS/Cachet.ipa | rg 'Payload/Cachet.app/'`

Expected: `Payload/Cachet.app/` exists and no `_CodeSignature` directory appears.

## Plan Self-Review

- Tasks cover browser UI, DuckDuckGo, default content blocking, catalog/chooser, session-aware transfers, safe speed optimization, HLS, errors, accessibility, docs, and IPA.
- Every behavior implementation follows a named failing test and green verification.
- No unresolved implementation placeholder remains.
