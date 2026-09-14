Cachet Log File

Generated: $(date)

## Session 2 (Sep 13, 2026) - Project Repair + Clean Unsigned IPA ✅

**Objective:** Make Cachet open/compile cleanly in Xcode and ship a working unsigned IPA.

**Problems fixed:**
- `PRODUCT_BUNDLE_IDENTIFIER` was unset → empty `CFBundleIdentifier` in the built app
- Resources build phase referenced undefined PBXBuildFile IDs → no `Assets.car`, no icon, no launch screen
- No deployment target → `MinimumOSVersion = 26.2`
- `LD_NO_PIE=YES`, wrong file types, duplicate group membership, scene manifest vs `@main` conflict
- Stale `TheWorkshop` scheme; broken `Cachet.xcscheme` pointing at a nonexistent target
- `LaunchScreen.storyboard` `<document>` lacked `type="..."` → `ibtool` error "can't determine the type"
- Old IPA was a Debug build with `Cachet.debug.dylib` / `__preview.dylib`

**Fixes applied:**
1. Rewrote `Cachet.xcodeproj/project.pbxproj` from scratch (clean UUIDs, real resources, `com.cachet.downloader`, iOS 16.0, signing off)
2. Rewrote `Cachet.xcscheme`; deleted `TheWorkshop.xcscheme` and `xcuserdata`
3. Rewrote `Info.plist` (ATS permissive for video CDNs, `cachet://` URL scheme, File Sharing on)
4. Deleted `SceneDelegate.swift`, `Info-debug.plist`
5. Rewrote `Models.swift` — real status enum (queued/extracting/downloading/done/failed), `MediaKind`, typed progress fields
6. Rewrote `FastDownloader.swift` (actor) — HEAD probe, chunked byte-range streaming, single-stream fallback, streaming writes; fixed `combineChunks` deleting the finished file
7. Rewrote `MediaExtractor.swift` — continuation-based `WKWebView` sniffing, 30s timeout, JS stream detection
8. Rewrote `DownloadManager.swift` — removed fake demo data; per-id updates; direct + HLS (`AVAssetExportSession`) paths; saves to `Documents/Downloads`
9. Updated `ContentView.swift` — empty state, tap-to-share via `UIActivityViewController`, long-press delete
10. Replaced `LaunchScreen.storyboard` with a valid Xcode launch screen
11. Built Release, verified bundle, packaged unsigned `Cachet.ipa` (13 MB)

**Result:**
- Build: `** BUILD SUCCEEDED **` (Release, arm64, iOS 16.0)
- Bundle verified: `Assets.car`, `LaunchScreen.storyboardc`, icon PNGs, `CFBundleIdentifier = com.cachet.downloader`, `MinimumOSVersion = 16.0`, binary unsigned
- `Cachet.ipa` at project root now the clean unsigned Release build

## Session 1 (Sep 13, 2026) - Original Build Attempt ✅

**Objective:** Build Cachet iOS app and produce working unsigned IPA

**Problem Diagnosed:**
- `xcodebuild` produced empty app shells (no compiled binary)
- Root cause: Target had empty `buildPhases = ( )` - no Sources, Frameworks, or Resources phases
- Also: `PRODUCT_NAME` not set explicitly, `SceneDelegate.swift` referenced `CachetApp()` instead of `ContentView()`

**Fixes Applied:**
1. Regenerated `Cachet.xcodeproj/project.pbxproj` with proper build phases
2. Added explicit `PRODUCT_NAME = Cachet;` and `EXECUTABLE_NAME = Cachet;` settings
3. Fixed `SceneDelegate.swift:12` - changed `CachetApp()` to `ContentView()`
4. Created Cachet scheme

**Result:**
- Build succeeds: `xcodebuild -project Cachet.xcodeproj -scheme Cachet -destination 'generic/platform=iOS' build`
- Binary: `Cachet` (Mach-O 64-bit executable arm64, 72KB)
- IPA: `Cachet.ipa` (262KB, Payload/Cachet.app/ structure) — superseded in Session 2

### File Changes
- Updated DownloadManager.swift - Replaced with cleaned implementation
- Updated FastDownloader.swift - Replaced with cleaned implementation
- Added SceneDelegate.swift - App lifecycle management
- Added Info.plist - App configuration
- Added Cachet.xcodeproj/project.pbxproj - Xcode project
- Added Documentation.md - Comprehensive documentation
- Added Build.md - Build instructions
- Added Cachet.entitlements - App permissions

## Current Project Structure

```
Cachet-iOS/
├── CachetApp.swift                    # App entry point (@main, owns DownloadManager)
├── ContentView.swift                  # Main UI: tabs, empty state, share sheet
├── DownloadManager.swift              # Download orchestration (MainActor)
├── FastDownloader.swift               # Chunked concurrent downloader (actor)
├── MediaExtractor.swift               # Headless WKWebView media sniffing
├── Models.swift                       # DownloadItem / DownloadStatus / MediaKind
├── Theme.swift                        # Dark aqua theme + Color(hex:)
├── AddLinkView.swift                  # Paste-a-link sheet
├── SettingsView.swift                 # Settings sheet
├── Info.plist                         # App config (ATS, URL scheme, File Sharing)
├── LaunchScreen.storyboard            # Valid Xcode launch screen
├── Assets.xcassets/                   # AppIcon (3x 1024x1024)
├── Cachet.xcodeproj/                  # Sane project + Cachet scheme
├── Cachet.entitlements                # Unused (signing disabled); kept on disk
├── Cachet.ipa                         # Current unsigned Release build
├── Build.md                           # Build + IPA guide
├── Documentation.md                   # Architecture doc
└── Cachet-LOG.md                      # This log
```

## Current Component Status (Session 2)

- **Models.swift** — `DownloadItem` (id, title, urlString, kind, progress, receivedBytes, totalBytes, speedString, sizeString, status, errorMessage, fileURL), `DownloadStatus` (queued/extracting/downloading/done/failed), `MediaKind` (unknown/direct/hls)
- **DownloadManager.swift** — MainActor orchestrator: URL normalization, kind detection, MediaExtractor fallback, `FastDownloader` for direct media, `AVAssetExportSession` for HLS, saves to Documents/Downloads, speed + progress per id, delete removes file
- **FastDownloader.swift** — actor: HEAD probe for Accept-Ranges, up to 4 concurrent byte-range chunk streams, streaming writes with throttled progress, single-stream fallback, combines partN files
- **MediaExtractor.swift** — MainActor continuation-based: 30s sniff timeout, injected JS (fetch override, play listener, MutationObserver), returns first media URL or nil
- **ContentView.swift** — header stats, Active/Completed/All tabs, empty state, tap-to-share (UIActivityViewController), long-press context menu (share/delete), toolbar (Browser Tool / + / Settings)
- **AddLinkView.swift** — URL input sheet with clipboard paste
- **SettingsView.swift** — settings sheet (toggles are largely aspirational)
- **Info.plist** — ATS arbitrary loads (+ web content), `cachet://` URL scheme, UIFileSharingEnabled, LSSupportsOpeningDocumentsInPlace, arm64, 1.0.0/1

## Verified State

- Release build: **BUILD SUCCEEDED** (arm64, iOS 16.0, unsigned)
- Bundle: Assets.car, LaunchScreen.storyboardc, icon PNGs, Info.plist, PkgInfo, Cachet binary — no debug dylibs
- IPA: `Cachet.ipa` (~13 MB) repackaged from the clean Release build

## Version Information

- Version: 1.0.0
- Build: 1
- Target: iOS 16.0+
- Swift: 5 (Swift 6 toolchain)
- Xcode: 26.3
