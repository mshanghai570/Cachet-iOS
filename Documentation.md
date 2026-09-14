# Cachet App Structure

Cachet is a free, local-only iOS video downloader. No backend, no accounts,
no cloud — everything runs on-device. Built with SwiftUI over Swift concurrency.

## Source Files

| File | Role |
| --- | --- |
| `CachetApp.swift` | `@main` entry point; owns the `DownloadManager` (`.environmentObject`) |
| `ContentView.swift` | Main UI: header, Active/Completed/All tabs, empty state, toolbar, share sheet, `ActivityView` |
| `BrowserView.swift` | Visible browser, navigation controls, stream picker, and ad-block switch |
| `BrowserCoordinator.swift` | WebKit media detection, browser session capture, and content-rule management |
| `DownloadManager.swift` | Orchestrates every download: URL normalization, stream detection, direct + HLS paths, speed/progress, shares items via `ObservableObject` |
| `FastDownloader.swift` | `actor` that downloads a single file: HEAD probe → concurrent chunked byte-range streaming → single-stream fallback |
| `MediaExtractor.swift` | `@MainActor` headless `WKWebView` that sniffs a page for its media URL (`.m3u8` / video ext) with a 30s timeout |
| `Models.swift` | `DownloadItem` (id/title/URL/kind/progress/speed/status/fileURL…), `DownloadStatus`, `MediaKind` |
| `Theme.swift` | Dark aqua palette + `Color(hex:)` |
| `AddLinkView.swift` | Paste-a-link sheet |
| `SettingsView.swift` | Settings sheet (mildly aspirational toggles) |

Not part of the app anymore (removed during repair): `SceneDelegate.swift`,
`Info-debug.plist`, `Cachet.entitlements` (left on disk but unused), and a
matching `Info.plist` that no longer declares a scene manifest.

## How a download flows

1. **Browser Tool** opens a visible WebKit browser at DuckDuckGo. Play a video,
   then choose from the detected direct/HLS streams; the ad blocker is on by default.
2. The selected stream is passed to `DownloadManager.enqueue(_:)` with the
   page’s cookies, user-agent, and referrer.
3. `DownloadManager.addDownload(url:)` normalizes a pasted link (auto-prepends
   `https://`) and inserts a `.queued` `DownloadItem`.
4. Kind detection by URL: `.m3u8` → `.hls`; video file extension → `.direct`;
   otherwise `.unknown`.
5. Unknown pasted pages go through `MediaExtractor.extract(from:)`, which loads the
   page in a hidden `WKWebView`, injects JS (fetch override, `play` listener,
   MutationObserver scan) and returns the first media URL found.
6. **Direct** → `FastDownloader.startDownload(progress:)`: it sends the
   browser-aware request and uses up to 4 chunks only after a valid `206`
   range probe. Servers without range support use one stream instead of failing.
7. **HLS** → `AVAssetExportSession` (`.mp4`, highest quality) with a poller
   updating progress.
6. Everything is saved to `Documents/Downloads/` (visible in the **Files** app
   because Info.plist sets `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`).
7. Tap a finished row → share sheet. Long-press → delete (removes the file too).

## Technical notes

- **Concurrency**: `DownloadManager` is `@MainActor`; `FastDownloader` is an
  `actor` that serializes its state. Downloads run concurrently via Swift
  concurrency.
- **Info.plist**: ATS allows arbitrary loads (and web content) because video
  CDNs and embedded players often serve over plain HTTP / non-HTTPS schemes.
- **URL scheme**: `cachet://` is registered (`CFBundleURLTypes`).
- **Signing**: disabled, so the shipped `Cachet.ipa` is unsigned and sideloadable.
- Minimum OS: iOS 16.0. App version 1.0.0 (build 1), deployment arm64.

## Build

See `Build.md` for the exact Release build + unsigned-IPA packaging commands.

## Known limitations

- HLS export can be slow/large for very long streams (remux rather than re-encode).
- DRM-protected, encrypted, login-restricted, or otherwise access-controlled
  streams cannot be made downloadable by the app and are reported as unsupported.
- No resume across app restarts; an interrupted download must be started again.

## License

Free for educational and personal use.
