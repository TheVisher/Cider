# Sparkle Auto-Updater Setup

The code integration is complete (`SparkleUpdaterService`, Settings UI, AppDelegate wiring). These manual steps remain to activate update checking.

## 1. Add Sparkle to the Xcode Project

The SPM `Package.swift` already has the dependency, but Xcode needs to know about it too:

1. Open `Cider.xcodeproj` in Xcode
2. Select the **Cider** project in the navigator (not the target)
3. Go to **Package Dependencies** tab
4. Click **+** → paste `https://github.com/sparkle-project/Sparkle` → Add Package
5. When prompted, add the **Sparkle** library to the **Cider** app target
6. Build to verify it links correctly

## 2. Generate Ed25519 Signing Keys

Sparkle signs updates with Ed25519. You need a key pair:

```bash
# The generate_keys tool is inside the downloaded Sparkle framework
.build/artifacts/sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Resources/bin/generate_keys
```

This prints:
- A **private key** — save it in your Keychain or a secure location. You'll need it to sign `.dmg` files before publishing updates.
- A **public key** — goes into Info.plist (next step).

**Keep the private key safe.** If you lose it, existing users can't verify future updates.

## 3. Configure Info.plist

Add these two keys to `Sources/Cider/Resources/Info.plist`:

```xml
<key>SUFeedURL</key>
<string>https://thevisher.github.io/Cider/appcast.xml</string>

<key>SUPublicEDKey</key>
<string>YOUR_PUBLIC_ED25519_KEY_HERE</string>
```

- `SUFeedURL`: Where Sparkle checks for updates. Can be GitHub Pages, a raw GitHub URL, or any HTTPS endpoint.
- `SUPublicEDKey`: The public key from step 2.

## 4. Set Up the Appcast

The appcast is an XML file listing available versions. Sparkle provides a tool to generate it:

```bash
# Sign a .dmg and generate/update the appcast
.build/artifacts/sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Resources/bin/generate_appcast /path/to/dmg/directory
```

Or manually create `appcast.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Cider Updates</title>
    <item>
      <title>Version 1.0.1</title>
      <sparkle:version>6</sparkle:version>
      <sparkle:shortVersionString>1.0.1</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <pubDate>Sat, 01 Mar 2026 12:00:00 +0000</pubDate>
      <enclosure
        url="https://github.com/TheVisher/Cider/releases/download/v1.0.1/Cider-1.0.1.dmg"
        length="12345678"
        type="application/octet-stream"
        sparkle:edSignature="BASE64_SIGNATURE_HERE"
      />
    </item>
  </channel>
</rss>
```

Host this at the URL you set for `SUFeedURL`.

## 5. Signing a Release

When publishing a new version:

```bash
# Sign the .dmg with your private key
.build/artifacts/sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Resources/bin/sign_update Cider-1.0.1.dmg
```

This outputs an `edSignature` and `length` — put them in the appcast `<enclosure>` tag.

## 6. GitHub Pages Option

If using GitHub Pages for the appcast:

1. Create a `docs/` folder in the repo root (or use `gh-pages` branch)
2. Put `appcast.xml` there
3. Enable GitHub Pages in repo settings → Source: `docs/` folder
4. Set `SUFeedURL` to `https://thevisher.github.io/Cider/appcast.xml`

## 7. Test

1. Build and run Cider
2. Go to Settings > General > Startup > "Check for Updates Now"
3. If the appcast is set up correctly, Sparkle will show an update dialog when a newer version is listed

## Reference

- [Sparkle Documentation](https://sparkle-project.org/documentation/)
- [Sparkle GitHub](https://github.com/sparkle-project/Sparkle)
