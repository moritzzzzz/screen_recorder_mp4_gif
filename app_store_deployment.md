# Mac App Store Deployment Guide

Step-by-step guide to publishing **Screen Recorder** on the Mac App Store so anyone can download it directly from `apps.apple.com`.

> **Decision point: App Store vs. direct download.** The Mac App Store gives you discoverability and frictionless install at the cost of (a) Apple's review (1–3 days typically, longer for screen capture apps), (b) mandatory sandboxing, and (c) a meaningful one-time project rework into Xcode.
>
> If you only need *frictionless install* without the App Store, see [§13 — Alternative: Developer ID + Notarization](#13-alternative-developer-id--notarization). That path keeps the current Swift Package Manager build and skips sandboxing + review entirely. Most independent macOS apps go this route.
>
> The rest of this document covers the **App Store** path.

---

## Table of contents

1. [Prerequisites](#1-prerequisites)
2. [Decide your Bundle ID and version](#2-decide-your-bundle-id-and-version)
3. [One-time Apple Developer Portal setup](#3-one-time-apple-developer-portal-setup)
4. [Create the App Store Connect record](#4-create-the-app-store-connect-record)
5. [Convert the Swift Package to an Xcode project](#5-convert-the-swift-package-to-an-xcode-project)
6. [Configure entitlements (sandbox + capabilities)](#6-configure-entitlements-sandbox--capabilities)
7. [Configure Info.plist for the store](#7-configure-infoplist-for-the-store)
8. [Add an app icon](#8-add-an-app-icon)
9. [Sanity-check sandboxed behavior](#9-sanity-check-sandboxed-behavior)
10. [Archive and upload to App Store Connect](#10-archive-and-upload-to-app-store-connect)
11. [Fill in App Store metadata](#11-fill-in-app-store-metadata)
12. [Submit for review (and what to expect)](#12-submit-for-review-and-what-to-expect)
13. [Alternative: Developer ID + Notarization](#13-alternative-developer-id--notarization)
14. [Appendix: common rejection reasons for screen recorders](#14-appendix-common-rejection-reasons-for-screen-recorders)

---

## 1. Prerequisites

- **Apple Developer Program membership** ($99/year). The free Developer ID doesn't allow App Store submission.
- **Xcode 15+** (the full app from the App Store, not just `xcode-select --install`).
  - After installing, run once: `sudo xcodebuild -license accept` and `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
- **An Apple ID** that's added as **Account Holder** or **Admin** for your team in [App Store Connect](https://appstoreconnect.apple.com).
- **A privacy policy URL.** Apple requires one for any app that accesses microphone, camera, or screen-recording — i.e. ours. A simple page on GitHub Pages or your own site is fine.

---

## 2. Decide your Bundle ID and version

The current placeholder is `com.custom.screenrecorder`. App Store apps need a Bundle ID that belongs to your team.

Pick something stable like `com.moritzforster.screenrecorder` (use your real reverse-DNS prefix). You'll register this exact string in three places: the developer portal (§3), App Store Connect (§4), and the Xcode project (§5). It can't be changed once the app is live.

Decide a version string:
- `CFBundleShortVersionString` — the user-visible version, e.g. `1.0.0`. Must increase across releases.
- `CFBundleVersion` — the internal build number, e.g. `1`, `2`, … Must increase across every upload to App Store Connect, even within the same `ShortVersionString`.

---

## 3. One-time Apple Developer Portal setup

Sign in at <https://developer.apple.com/account>.

### 3.1 Register an App ID

1. **Certificates, Identifiers & Profiles → Identifiers → +**.
2. Type **App IDs → App**.
3. **Bundle ID:** *Explicit*, paste the bundle ID from §2.
4. **Description:** "Screen Recorder".
5. **Capabilities:** check
   - **App Sandbox** (required for App Store).
   - **Hardened Runtime** (required).
   - You don't need to tick a screen-recording capability here — screen recording is handled via TCC at runtime, not via an entitlement.
6. Save.

### 3.2 Certificates

Xcode 15+ manages these automatically once you're signed into your Apple ID in **Xcode → Settings → Accounts → Manage Certificates → +** and add both:

- **Apple Development** (for local builds).
- **Apple Distribution** (for App Store submission).

If Xcode can't create them for you (rare), do it manually in the portal under **Certificates → +** and download/install the resulting `.cer` files.

---

## 4. Create the App Store Connect record

Sign in at <https://appstoreconnect.apple.com>.

1. **My Apps → + → New App**.
2. Fill:
   - **Platforms:** macOS.
   - **Name:** "Screen Recorder" (must be unique across the store; tweak if taken, e.g. "Screen Recorder by Moritz").
   - **Primary language.**
   - **Bundle ID:** pick the one you registered in §3.
   - **SKU:** any string you like, e.g. `screen-recorder-1`. Internal use only.
   - **User Access:** Full Access (default).
3. Create. You now have an empty app record. Metadata gets filled in §11; you only need the record to exist before you can upload a build.

---

## 5. Convert the Swift Package to an Xcode project

The current build (`Scripts/build.sh` + `swift build`) produces an ad-hoc-signed `.app` that **cannot** be uploaded to App Store Connect — Apple's submission tooling requires a proper Xcode archive. Easiest path: create a new Xcode project that wraps the existing source.

### 5.1 Create the project

1. **Xcode → File → New → Project → macOS → App → Next**.
2. **Product Name:** `ScreenRecorder`.
3. **Team:** your developer team.
4. **Organization Identifier:** your reverse-DNS prefix (e.g. `com.moritzforster`). Combined with the product name this gives Xcode-generated Bundle ID `com.moritzforster.ScreenRecorder` — adjust the product name or override the bundle ID in the target settings to match what you registered in §3.
5. **Interface:** SwiftUI.
6. **Language:** Swift.
7. Save the new project **outside** the existing repo (e.g. `~/dev/ScreenRecorder-Xcode/`), so you don't pollute the current Swift Package layout.

### 5.2 Add the sources

1. In Finder, copy the entire contents of `Sources/ScreenRecorder/` from the existing repo into the new Xcode project's source folder (alongside the auto-generated `App.swift` Xcode created).
2. Delete the auto-generated `App.swift` / `ContentView.swift` Xcode made — we already have our own.
3. Right-click the project navigator → **Add Files to "ScreenRecorder"…** → select the copied folders. Make sure **Copy items if needed** is **off** (they're already in place) and **Create groups** is on.
4. The `main.swift` we ship sets up `NSApplication` manually, so go to the target's **Build Settings** and remove the `@main` attribute Xcode added if there is one (the new-project template has `@main App` in `App.swift` — delete that file entirely).

### 5.3 Link frameworks

In **Target → General → Frameworks, Libraries, and Embedded Content**, add (all are part of the macOS SDK; no embedded copies needed):

- ScreenCaptureKit.framework
- AVFoundation.framework
- AVKit.framework
- CoreMedia.framework
- CoreGraphics.framework
- ImageIO.framework
- AppKit.framework (linked by default for AppKit-based apps)
- UniformTypeIdentifiers.framework

### 5.4 Set deployment target

**Target → General → Minimum Deployments → macOS:** `13.0`.

### 5.5 Build once to confirm everything compiles

`⌘B`. Fix any source-path mistakes (Xcode will surface "file not found" errors if anything was missed). The codebase compiles unchanged in this Xcode setup.

---

## 6. Configure entitlements (sandbox + capabilities)

App Store apps **must** be sandboxed. Without the entitlements below the app will crash or be denied permissions when running.

In Xcode, open the **Target → Signing & Capabilities** tab, then:

1. Click **+ Capability** → **App Sandbox**. Xcode creates `ScreenRecorder.entitlements` for you.
2. Inside **App Sandbox**, tick:
   - **Hardware → Audio Input** — required for `AVCaptureDevice.default(for: .audio)` (the microphone capture path).
3. Click **+ Capability** again → **Hardened Runtime**. (App Store requires both.)
4. Open the generated `ScreenRecorder.entitlements` file directly and confirm it contains at minimum:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
```

### Notes about specific features

- **Screen recording.** There is **no entitlement** to request — screen recording is gated by TCC and the OS prompts the user the first time. As long as `NSScreenCaptureUsageDescription` is set in Info.plist (we already have this) and the app uses ScreenCaptureKit (we do), it works inside the sandbox.
- **System audio capture.** Same TCC permission as screen recording. No extra entitlement.
- **Reading user-chosen video files** (`Open Video to Edit…`). Works in the sandbox via Powerbox — the file the user picks via `NSOpenPanel` is automatically granted access. No `com.apple.security.files.user-selected.read-only` entitlement needed unless you want to *open by path* (which we don't).
- **Saving exported files** (`Save As MP4 …`). Same — `NSSavePanel` grants write access to the user's chosen location. No extra entitlement.
- **Procedural music cache** at `~/Library/Caches/com.custom.screenrecorder/audio/…`. Inside the sandbox this becomes `~/Library/Containers/<bundle-id>/Data/Library/Caches/<bundle-id>/audio/…` automatically. The `FileManager.default.urls(for: .cachesDirectory, …)` call we use already returns the correct sandboxed path.

---

## 7. Configure Info.plist for the store

Open the target's **Info** tab (or the `Info.plist` file directly) and verify / add:

| Key | Value | Why |
| --- | --- | --- |
| `CFBundleIdentifier` | `com.moritzforster.screenrecorder` (yours) | Must match §3.1 |
| `CFBundleShortVersionString` | `1.0.0` | User-visible version |
| `CFBundleVersion` | `1` | Internal build number; bump on every upload |
| `LSMinimumSystemVersion` | `13.0` | Matches deployment target |
| `LSApplicationCategoryType` | `public.app-category.video` | Required for the store; pick from [Apple's list](https://developer.apple.com/documentation/bundleresources/information_property_list/lsapplicationcategorytype) |
| `NSScreenCaptureUsageDescription` | "Screen Recorder needs screen capture access to record your selected screen region." | Already present; required for the TCC prompt |
| `NSMicrophoneUsageDescription` | "Screen Recorder needs microphone access to record your voice alongside the screen capture." | Already present; required for mic TCC prompt |
| `ITSAppUsesNonExemptEncryption` | `false` (boolean) | Tells Apple we don't ship custom crypto — skips export-compliance paperwork. We only use AAC/H.264, which qualify as exempt. |
| `NSHighResolutionCapable` | `true` (boolean) | Already present |

---

## 8. Add an app icon

The store rejects apps without a proper icon set.

1. Design a **1024 × 1024** PNG (square, no transparency, no rounded corners — macOS adds those at render time).
2. In Xcode's asset catalog (`Assets.xcassets`), open **AppIcon** and drag the PNG into the **1024 × 1024 macOS** slot.
3. If you want pixel-perfect icons at small sizes, also provide 16, 32, 64, 128, 256, 512 px renders (Apple's [Icon Composer](https://developer.apple.com/design/resources/) tool generates these from a source SVG/PNG).

A quick way to generate the icon set from a single 1024 px PNG via the command line:

```sh
mkdir -p AppIcon.iconset
sips -z 16 16     icon-1024.png --out AppIcon.iconset/icon_16x16.png
sips -z 32 32     icon-1024.png --out AppIcon.iconset/icon_16x16@2x.png
sips -z 32 32     icon-1024.png --out AppIcon.iconset/icon_32x32.png
sips -z 64 64     icon-1024.png --out AppIcon.iconset/icon_32x32@2x.png
sips -z 128 128   icon-1024.png --out AppIcon.iconset/icon_128x128.png
sips -z 256 256   icon-1024.png --out AppIcon.iconset/icon_128x128@2x.png
sips -z 256 256   icon-1024.png --out AppIcon.iconset/icon_256x256.png
sips -z 512 512   icon-1024.png --out AppIcon.iconset/icon_256x256@2x.png
sips -z 512 512   icon-1024.png --out AppIcon.iconset/icon_512x512.png
cp icon-1024.png  AppIcon.iconset/icon_512x512@2x.png
iconutil -c icns AppIcon.iconset
```

The resulting `AppIcon.icns` can be embedded by setting `CFBundleIconFile = AppIcon` in Info.plist, but the asset catalog approach above is the recommended modern path.

---

## 9. Sanity-check sandboxed behavior

Before archiving, run the sandboxed build locally and verify nothing's broken by the new restrictions:

1. ⌘R in Xcode (this builds the **Debug** scheme with sandbox **on** by virtue of the entitlements file).
2. Walk through every flow:
   - Region selection + recording (with **System Audio** off, **Mic** off).
   - Recording with **System Audio** on.
   - Recording with **Mic** on (you should see the macOS Microphone prompt the *first time*).
   - **Open Video to Edit…** — pick an MP4, then a GIF.
   - Editor: add a second track via **+ Add Video**, do a cut, do a **Cut at Cursor**, disable a track.
   - **Background music**: pick Calm, hit Preview. (This writes to the sandboxed Caches dir — confirm it works.)
   - Export each format (MP4, MPEG-4, GIF) via **Save As…**.
3. If any flow breaks with a sandbox-related crash (`com.apple.security.exception.*` in Console.app), you're missing an entitlement. The most common culprit on this app would be Audio Input.

---

## 10. Archive and upload to App Store Connect

1. In Xcode, set the **scheme's destination** to **Any Mac (Apple Silicon, Intel)** at the top of the window (not "My Mac" — that's the run target).
2. **Product → Archive**. This builds a **Release** configuration with the **Apple Distribution** certificate and produces an archive in the Organizer.
3. When the Organizer opens, select the new archive and click **Validate App**:
   - Choose **App Store Connect → Next**.
   - **Automatically manage signing** (let Xcode pick the distribution profile).
   - Validation runs server-side and flags issues like missing icons, malformed Info.plist keys, missing privacy descriptions. Fix anything it complains about and re-archive.
4. Once validation passes, click **Distribute App** in the Organizer:
   - **App Store Connect → Next**.
   - **Upload**.
   - Confirm signing settings. Xcode signs with **Apple Distribution**, applies the **Hardened Runtime**, and uploads the `.pkg`.
5. After ~5–15 minutes, App Store Connect emails you that the build has been processed (or that it failed processing — usually a re-validate is enough).

---

## 11. Fill in App Store metadata

In App Store Connect, open your app and go to **macOS App → 1.0.0 Prepare for Submission**.

### App information
- **Subtitle** (30 chars): e.g. "Record, edit, export"
- **Promotional text** (170 chars, can be updated without re-submission)
- **Description** (4000 chars): describe the multi-track editor, audio capture, three export formats, royalty-free music
- **Keywords** (100 chars, comma-separated): `screen,recorder,video,editor,gif,mp4,trim,timeline,microphone`
- **Support URL**: link to your GitHub repo issues page works fine
- **Marketing URL** (optional)
- **Privacy Policy URL**: **required** — see prerequisites

### Build
- Click **+** next to "Build" and pick the build you just uploaded.

### App Store screenshots (mandatory)
Provide at least one screenshot per macOS form factor Apple accepts:
- **2880 × 1800** (16:10) is the modern standard
- **2560 × 1600** is also accepted
- 1 screenshot minimum, 10 maximum

You can take screenshots of the app at any size and resize/letterbox to one of the accepted dimensions. The previous screenshots used in the README work as a starting point.

### App preview (optional but boosts conversion)
A 15–30 second video at 1920 × 1080 or 2880 × 1800. Show region selection → recording → editing → exporting. Use the app itself to record this. Upload as `.m4v` or `.mp4`.

### App Privacy
The **App Privacy** section is mandatory and stricter than it looks.
- Click **Get Started** → describe what data you collect.
- For this app, the honest answer is **none** — recordings stay on the user's machine; nothing is sent anywhere. Tick **No, we do not collect data from this app**.
- If you ever add analytics or crash reporting, update this section.

### Pricing
Free or paid. If free, no further setup. If paid, set the tier here and complete the **Agreements, Tax, and Banking** section for your account.

### Age rating
Run the questionnaire — for a screen recorder it'll come out 4+.

### Review information
- **Sign-in required**: no.
- **Demo account**: not applicable.
- **Notes for reviewer**: write a short blurb that helps the reviewer understand what to test. Example:

> Screen Recorder is a region-based screen capture tool with a multi-track video editor. To test:
>
> 1. Launch the app, click "Select Region", drag to choose a 600×400 area on screen, click "Start Recording".
> 2. The 3-second countdown plays, then the app captures the chosen area for as long as the user wishes.
> 3. After clicking "Stop Recording", the user can optionally open the multi-track editor (Edit Video button), trim sections, add a procedurally-synthesized music track, then export as MP4 / MPEG-4 / GIF via "Save As".
>
> The app requests **Screen Recording** permission on first capture and **Microphone** permission only if the user enables the Microphone toggle. All audio is procedurally generated or supplied by the user — no copyrighted content is bundled.

---

## 12. Submit for review (and what to expect)

1. From the build page in App Store Connect, click **Add for Review** (top right).
2. Confirm export-compliance question (we set `ITSAppUsesNonExemptEncryption = false`, so this should auto-resolve).
3. Click **Submit for Review**.

**Timelines** (as of 2026, based on App Store transparency reports):
- Median review time: ~24 hours.
- Screen capture / recording apps tend to land at the higher end (~48–72 h) because reviewers test the TCC prompts and check that the app handles the permission-denied case.

**While in review:**
- You can withdraw any time (**App Information → Pricing and Availability → Remove**).
- You can answer reviewer messages via the **Resolution Center** if anything comes up.

**Once approved:**
- The app appears on the store within a few hours.
- Future updates: bump `CFBundleVersion`, archive, upload, fill in **What's New in This Version**, submit. Update reviews are typically faster than the initial submission.

---

## 13. Alternative: Developer ID + Notarization

If you'd rather skip the App Store, you can ship the existing SPM-built `.app` from your website / GitHub Releases with **zero Apple review** and no sandboxing. Users still get a frictionless install because the app is notarized.

What changes versus the current ad-hoc-signed build:

1. **Replace the ad-hoc signature with a Developer ID Application certificate.**
   - In Xcode → Settings → Accounts → Manage Certificates → + → **Developer ID Application**.
2. **Update `Scripts/build.sh`** to sign with that identity instead of `-`:

   ```sh
   codesign --force \
            --options runtime \
            --sign "Developer ID Application: Moritz Forster (TEAMID12345)" \
            --deep \
            "$APP_BUNDLE"
   ```

   `--options runtime` enables the Hardened Runtime, which notarization requires. Your Team ID is in the developer portal membership page.
3. **Notarize** the signed bundle:

   ```sh
   # Bundle the .app into a zip for upload
   ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "ScreenRecorder.zip"

   # Submit to Apple's notary service (one-time: store credentials in keychain)
   xcrun notarytool store-credentials "AC_PASSWORD" \
       --apple-id "you@example.com" \
       --team-id "TEAMID12345" \
       --password "app-specific-password-from-appleid.apple.com"

   xcrun notarytool submit "ScreenRecorder.zip" \
       --keychain-profile "AC_PASSWORD" \
       --wait

   # Staple the notarization ticket so Gatekeeper sees it offline
   xcrun stapler staple "$APP_BUNDLE"
   ```

4. **Package as a DMG** (per our earlier discussion) and host it on GitHub Releases or your site.

Notarization usually takes 1–5 minutes per submission and is a pure-tooling step — no human review.

Trade-offs versus App Store:
- ✅ No sandbox conversion needed (keeps the current SPM build).
- ✅ No app review queue.
- ✅ You can ship 1.x.y betas without waiting for Apple.
- ❌ No discoverability through the store; users have to know about your site.
- ❌ No auto-updates unless you implement them (Sparkle is the standard library).

---

## 14. Appendix: common rejection reasons for screen recorders

Screen recording apps get scrutinized harder than average. Pre-empt these:

| Reason | How to avoid |
| --- | --- |
| **Missing privacy policy link.** | Have a public URL set in App Store Connect *before* submitting. |
| **Permission denied = crash.** | Confirm the app shows a clear in-app error (not a crash) when the user denies Screen Recording or Microphone. Our current code shows an error state — keep that behavior. |
| **System audio capture without explanation.** | The reviewer notes already explain that audio is optional and toggle-gated. Keep it that way. |
| **Insufficient app description.** | Don't just list features; explain *what users would do with it*. Mention "tutorial recording", "bug reports", "shareable demos". |
| **Screenshots that look like the simulator.** | Take screenshots on a real Mac at a high DPI; show the editor in use rather than just the idle screen. |
| **Built-in music sounds copyrighted.** | Already covered — the three built-in tracks are mathematically synthesized in Swift, with no derived audio from any source. If a reviewer questions licensing, point them to `AudioTrackGenerator.swift`. |
| **Promises features in the description that aren't in the build.** | Keep description honest. If you remove a feature in a future version, update the description in that submission. |

If you do get a rejection, Apple's message in the Resolution Center is usually specific (cites a guideline number like "2.1" or "5.1.1"). Respond, fix, re-submit — second-round reviews are faster.

---

## Quick checklist before you hit "Submit for Review"

- [ ] Bundle ID matches across §3 (portal), §4 (App Store Connect), §5 (Xcode target).
- [ ] App Sandbox + Hardened Runtime + Audio Input entitlement on.
- [ ] `NSScreenCaptureUsageDescription` and `NSMicrophoneUsageDescription` set.
- [ ] `LSApplicationCategoryType = public.app-category.video`.
- [ ] `ITSAppUsesNonExemptEncryption = false`.
- [ ] 1024 × 1024 icon in the asset catalog.
- [ ] At least one 2880 × 1800 screenshot uploaded.
- [ ] Privacy policy URL filled in.
- [ ] Build uploaded and selected on the version page.
- [ ] App Privacy questionnaire completed ("we collect no data").
- [ ] Reviewer notes describing how to test the screen-recording + permission flow.
