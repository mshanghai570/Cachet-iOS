# Cachet Build Guide

Build commands for the Cachet iOS app. All commands run from this directory.

## Prerequisites
- Xcode 26.x (built successfully with Xcode 26.3) — check `xcodebuild -version`
- macOS 14+

## Build (Release for device)
```bash
/usr/bin/xcodebuild \
  -project Cachet.xcodeproj \
  -scheme Cachet \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/cachet-dd \
  build
```

The unsigned `.app` lands at:
`/tmp/cachet-dd/Build/Products/Release-iphoneos/Cachet.app`

## Produce the unsigned IPA (sideloading)
After a successful Release build:
```bash
rm -rf /tmp/ipa-stage && mkdir -p /tmp/ipa-stage/Payload
cp -R /tmp/cachet-dd/Build/Products/Release-iphoneos/Cachet.app /tmp/ipa-stage/Payload/
cd /tmp/ipa-stage && zip -qr Cachet.ipa Payload
```
Copy `/tmp/ipa-stage/Cachet.ipa` to replace `./Cachet.ipa` in this folder.

## Build for Simulator
```bash
xcodebuild -project Cachet.xcodeproj -scheme Cachet -configuration Debug \
  -derivedDataPath /tmp/cachet-dd -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## Clean build
```bash
rm -rf /tmp/cachet-dd
```

## Verify the bundle is correct
```bash
APP=/tmp/cachet-dd/Build/Products/Release-iphoneos/Cachet.app
ls -la "$APP"
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist"   # com.cachet.downloader
/usr/libexec/PlistBuddy -c "Print :MinimumOSVersion"  "$APP/Info.plist"   # 16.0
file "$APP/Cachet"                                                         # Mach-O arm64, unsigned
```
A healthy Release bundle contains: `Assets.car`, `LaunchScreen.storyboardc`,
app-icon PNGs, `Info.plist`, `PkgInfo`, and the `Cachet` binary — and NO
`*.app/PlugIns` debug dylibs or `_CodeSignature`.

## Troubleshooting

- **`Interface Builder can’t determine the type of LaunchScreen.storyboard`**
  The `<document>` element must include `type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB"`
  and `launchScreen="YES"`. Replacing the file with a standard Xcode launch
  screen XML fixes it.
- **Empty `CFBundleIdentifier` on device** — set `PRODUCT_BUNDLE_IDENTIFIER`
  (`com.cachet.downloader`) in the Release build settings.
- **No app icon / black icon** — the Resources build phase must reference
  `Assets.xcassets` and `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` must be set.
- **Signing** is intentionally disabled (`CODE_SIGNING_ALLOWED = NO`) so the IPA
  can be sideloaded unsigned.

## Development workflow
1. Edit Swift files in this directory.
2. Build with the Release command above.
3. Repackage the IPA and sideload.