# Cachet

A sleek iOS video downloader built with SwiftUI. Paste a link or use the built-in browser — Cachet sniffs out the stream and saves it straight to your device.

## Features

- **Paste & Download** — Drop any video URL and Cachet automatically detects the stream (direct MP4, M4V, WebM, or HLS)
- **Built-in Browser** — Navigate to any site with the integrated WebKit browser, detect video streams on the fly, and download with one tap
- **Ad Blocking** — Content blockers built in to keep pages clean while you browse for videos
- **HLS Support** — Downloads and exports HLS (`.m3u8`) streams as MP4 via `AVAssetExportSession`
- **Chunked Downloads** — When the server supports byte ranges, files are split into concurrent chunks for faster transfers
- **Real-time Progress** — Live speed, percentage, and file size tracking for every download
- **Stream Detection** — JavaScript injection monitors `fetch`, `XMLHttpRequest`, and `<video>` elements to catch streams that don't appear in the page source
- **Share Sheet** — Tap a completed download to share it via the iOS share sheet
- **Dark Mode Only** — Custom teal-on-black theme

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+

## Getting Started

1. Clone the repo:
   ```bash
   git clone https://github.com/mshanghai570/Cachet-iOS.git
   ```
2. Open `Cachet.xcodeproj` in Xcode
3. Select a simulator or device and hit Build & Run

## How It Works

1. **Paste a URL** or open the **Browser Tool** and navigate to a page with a video
2. Cachet's `MediaExtractor` loads the page in a hidden `WKWebView` and injects JavaScript to intercept media streams
3. If multiple streams are found, you pick the best one from the stream picker
4. `FastDownloader` handles the transfer — single-stream for basic servers, chunked concurrent downloads for servers that support byte ranges
5. Completed downloads are saved to the app's Documents directory and can be shared via the system share sheet

## Project Structure

| File | Purpose |
|------|---------|
| `CachetApp.swift` | App entry point |
| `ContentView.swift` | Main download list UI |
| `AddLinkView.swift` | Paste-a-link sheet |
| `BrowserView.swift` | Integrated WebKit browser |
| `BrowserCoordinator.swift` | Browser state, ad blocking, stream detection |
| `MediaExtractor.swift` | Hidden WKWebView sniffing for media URLs |
| `DownloadManager.swift` | Download orchestration and state management |
| `FastDownloader.swift` | Single-stream and chunked concurrent downloading |
| `ChunkedDataDownload.swift` | URLSession delegate-based streaming to disk |
| `Models.swift` | Data models (`DownloadItem`, `MediaCandidate`, transfer policies) |
| `SettingsView.swift` | Settings UI |
| `Theme.swift` | Color palette and theme constants |

## License

MIT
