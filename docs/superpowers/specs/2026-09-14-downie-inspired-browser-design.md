# Downie-Inspired Browser and Download Engine

## Goal

Turn Cachet's Browser Tool into a real, local-first iOS browser that lets a
person navigate to an authorized video, play it, inspect discovered streams,
and save the selected stream quickly and reliably. The app will package as an
unsigned IPA.

## Scope

The browser opens at DuckDuckGo and provides an address field, back, forward,
reload/stop, a close control, a page title, and a default-enabled ad blocker.
It renders pages in a visible `WKWebView`, retaining the page's session state.

A browser coordinator observes navigation and injects a small document-start
script. The script reports video elements, source elements, and media fetches
to Swift. The coordinator creates a deduplicated media catalog containing the
stream URL, type, label, detected source, referring page, and active cookies.
Only direct, unprotected media URLs and compatible HLS playlists are offered.
It never attempts to bypass DRM, access restrictions, or encryption.

The browser's download affordance displays a sheet when one or more streams
are available. The sheet offers a prominent Best Available selection plus
every discovered variant, starts a chosen download, and remains clear about
unsupported or protected media. It refreshes after playback begins, which is
when many sites create their actual media request.

## Performance and Reliability

Downloads use the browser's cookies, user-agent, and `Referer` header. Direct
file downloads make a normal GET request first and stream immediately to disk.
The downloader measures response headers, then uses a bounded number of
parallel range requests only when the server proves it supports byte ranges.
If a server rejects HEAD or Range requests, the task continues as one stream;
this prevents the present all-or-nothing failure mode. Concurrent chunks are
assembled atomically and cleaned up on cancellation or error.

Compatible HLS streams use Apple's asset-download facilities and preserve the
original stream rather than forcing an unreliable export. The UI reports
download progress, current throughput, resumability when available, completion,
and an actionable failure reason: no media detected, expired/unauthorized URL,
DRM/protected media, unsupported format, insufficient storage, or network
failure.

The media catalog and transfer request are independent data types. This makes
future site-specific extractors additive: they can contribute candidates to
the same catalog without changing the browser or queue UI.

## Content Blocking

An optional `WKContentRuleList` blocks common advertising, tracking, and popup
patterns. It is enabled by default and can be disabled in the browser toolbar.
Changing the setting recompiles/applies the appropriate WebKit configuration
for the next page load. The download button and sheet never depend on blocked
content.

## Files and Components

- `BrowserView.swift`: SwiftUI browser presentation, toolbar, download sheet,
  and accessibility labels.
- `BrowserCoordinator.swift`: `WKNavigationDelegate`, script-message handler,
  cookie/session capture, media-catalog updates, and content-rule setup.
- `MediaCandidate.swift`: stream metadata and a download request that carries
  the browser request context.
- `DownloadManager.swift`: accepts a media candidate/request and presents
  specific transfer failures.
- `FastDownloader.swift`: resilient GET-first direct downloader, safe range
  probing, bounded concurrency, atomic assembly, and cleanup.
- `ContentView.swift` / `SettingsView.swift`: launch the browser and retain
  user preferences.

## Validation

Unit tests will first cover URL normalization, content-disposition filename
selection, media-candidate de-duplication and ranking, range-response
validation, and download-request header construction. The project has no test
target today, so a `CachetTests` target will be added.

Manual device validation will cover DuckDuckGo navigation, page playback,
ad-blocker switching, a direct MP4, an HLS stream, an authenticated stream
whose session is respected, a server without `HEAD`/range support, a protected
stream failure, Files app output, Dynamic Type, and VoiceOver labels. The
release device build will use `CODE_SIGNING_ALLOWED=NO`; the resulting app is
wrapped in `Payload/` as an unsigned IPA.

## Limits

iOS and WebKit cannot make protected, DRM-encrypted, login-restricted, or
otherwise unavailable video downloadable. No claim of universal site support
will appear in the product; the target is the widest reliable support for
streams the user is authorized to save.
