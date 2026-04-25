# Sparkle Auto-Updater Setup

The code integration is complete (`SparkleUpdaterService`, Settings UI, AppDelegate wiring), and the Xcode debug app embeds `Sparkle.framework`. The remaining work is the signed, notarized release/appcast install test.

Status on `2026-04-25`: Developer ID signing and notarization work. The existing hosted appcast is live at `https://thevisher.github.io/Cider/appcast.xml`, and the local appcast for `0.1.0-beta.3` build `8` contains a valid Sparkle Ed25519 signature for a signed, notarized, and stapled DMG.

Earlier on `2026-04-25`, notarization was blocked by Apple before archive submission:

```text
Error: HTTP status code: 403. A required agreement is missing or has expired.
```

Accepting the required Apple Developer agreement for team `S9SS3NNGSW` cleared the blocker.

## 1. Verify Sparkle In The Xcode App Target (DONE)

Sparkle is supplied by the local Swift package product that the Xcode app target links.

Verified on `2026-04-24`:

```bash
xcodebuild -project Cider.xcodeproj -scheme CiderApp -configuration Debug -destination 'platform=macOS' build
find ~/Library/Developer/Xcode/DerivedData -path '*/Cider.app/Contents/Frameworks/Sparkle.framework' -print
otool -L ~/Library/Developer/Xcode/DerivedData/*/Build/Products/Debug/Cider.app/Contents/MacOS/Cider.debug.dylib | grep Sparkle
```

Expected result: the app bundle contains `Contents/Frameworks/Sparkle.framework`, and the Cider debug dylib links `@rpath/Sparkle.framework/Versions/B/Sparkle`.

## 2. Generate Ed25519 Signing Keys (DONE)

Sparkle signs updates with Ed25519. Key pair has been generated.

```bash
# The generate_keys tool is inside the downloaded Sparkle framework
.build/xcode/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
```

**Keep the private key safe.** If you lose it, existing users can't verify future updates.

## 3. Configure Info.plist (DONE)

`Sources/Cider/Resources/Info.plist` already contains `SUFeedURL` and `SUPublicEDKey`.

- `SUFeedURL`: `https://thevisher.github.io/Cider/appcast.xml`
- `SUPublicEDKey`: Set to the generated public key.

## 4. Set Up the Appcast

The appcast is an XML file listing available versions. Sparkle provides a tool to generate it:

```bash
# The release script signs the DMG update, merges the previous hosted appcast,
# and writes build/appcast/appcast.xml.
./scripts/release.sh 0.1.0-beta.4 --skip-github
```

The generated appcast should include:

```bash
rg 'sparkle:shortVersionString|sparkle:version|sparkle:edSignature|sparkle:minimumSystemVersion|sparkle:hardwareRequirements' build/appcast/appcast.xml
```

Host this at the URL you set for `SUFeedURL`.

## 5. Signed And Notarized Release

To check credentials without changing versions or building:

```bash
./scripts/release.sh 0.1.0-beta.4 --preflight-only --skip-github
```

For a real release, use the release script without skip flags:

```bash
./scripts/release.sh 0.1.0-beta.4
```

This archives the app, exports it with Developer ID signing, notarizes and staples the app, creates and signs the DMG, notarizes and staples the DMG, generates the Sparkle appcast from the final DMG, creates the GitHub release, and publishes `appcast.xml` to `gh-pages`.

Before publishing, verify the local artifact:

```bash
codesign --verify --deep --strict build/export/Cider.app
codesign --verify build/Cider-0.1.0-beta.4.dmg
spctl --assess --type execute --verbose=4 build/export/Cider.app
spctl --assess --type open --context context:primary-signature --verbose=4 build/Cider-0.1.0-beta.4.dmg
hdiutil verify build/Cider-0.1.0-beta.4.dmg
plutil -p build/export/Cider.app/Contents/Info.plist | rg 'CFBundleShortVersionString|CFBundleVersion|SUFeedURL|SUPublicEDKey|LSMinimumSystemVersion'
sed -n '1,140p' build/appcast/appcast.xml
```

Expected result: code signing passes, `spctl` accepts both the app and DMG as notarized Developer ID artifacts, the DMG checksum is valid, the plist points at `https://thevisher.github.io/Cider/appcast.xml`, and the newest appcast item points at the matching GitHub release DMG.

## 6. GitHub Pages Option

If using GitHub Pages for the appcast:

1. Create a `docs/` folder in the repo root (or use `gh-pages` branch)
2. Put `appcast.xml` there
3. Enable GitHub Pages in repo settings → Source: `docs/` folder
4. Set `SUFeedURL` to `https://thevisher.github.io/Cider/appcast.xml`

## 7. Update-Install Test

Use two consecutive release builds. Example: installed older build `0.1.0-beta.3`, hosted newer build `0.1.0-beta.4`.

1. Install the older notarized build into `/Applications/Cider.app`.
2. Confirm the older app plist has `CFBundleShortVersionString = 0.1.0-beta.3` and `CFBundleVersion` lower than the appcast item.
3. Publish the newer GitHub release and `gh-pages` appcast with `./scripts/release.sh 0.1.0-beta.4`.
4. Confirm `curl -fsSL https://thevisher.github.io/Cider/appcast.xml` shows the newer `sparkle:shortVersionString`, higher `sparkle:version`, correct GitHub release URL, non-empty `sparkle:edSignature`, `sparkle:minimumSystemVersion` `26.0`, and `sparkle:hardwareRequirements` `arm64`.
5. Launch the older installed app.
6. Open Settings > General > Updates > Check for Updates Now, or About > Check for Updates.
7. Verify Sparkle offers the newer version, downloads the DMG, validates the Ed25519 signature, installs the update, and relaunches Cider.
8. After relaunch, verify `/Applications/Cider.app/Contents/Info.plist` reports the newer short version/build and `spctl --assess --type execute --verbose=4 /Applications/Cider.app` still passes.

If Sparkle does not offer the update, check these first:

- The installed app's `CFBundleVersion` must be lower than the appcast item's `sparkle:version`.
- The appcast URL in the installed app must match the hosted appcast.
- The GitHub release DMG URL in the appcast must be reachable without authentication.
- The appcast signature must be generated with the private key matching `SUPublicEDKey`.

## Reference

- [Sparkle Documentation](https://sparkle-project.org/documentation/)
- [Sparkle GitHub](https://github.com/sparkle-project/Sparkle)
