# AndroidRemote iOS Sender

SwiftUI app for casting iPhone screen to **Chromecast / Google TV** via WebRTC (Cast-first). Optional native Android TV path via mDNS.

## Quick start

### 1. Cast receiver setup (required)

1. Host `cast-receiver/index.html` over HTTPS
2. Register in [Cast SDK Developer Console](https://cast.google.com/publish) → copy **App ID**
3. Edit `Shared/CastConfig.swift`:
   ```swift
   static let receiverAppId = "YOUR_CAST_APP_ID"
   ```

### 2. Open in Xcode

```bash
open ios/AndroidRemote.xcodeproj
```

Dependencies resolve via **Swift Package Manager** (no CocoaPods):

| Package | Source | Product |
|---------|--------|---------|
| WebRTC | `stasel/WebRTC` | WebRTC |
| Google Cast | `castlabs/google-cast-spm` | GoogleCastStatic |

First open: **File → Packages → Resolve Package Versions** if Xcode does not fetch automatically.

### 3. Signing & run

1. Set **Team** on **AndroidRemote** and **BroadcastExtension**
2. App Group `group.com.androidremote.shared` on both targets
3. Run on a **physical iPhone** (broadcast does not work in Simulator)

### Regenerate Xcode project (after editing `project.yml`)

```bash
cd ios
../tools/xcodegen-bin/xcodegen/bin/xcodegen generate
```

---

## Cast flow (V1 primary)

1. **Mirror tab** → discover Cast devices → select TV → **Connect to TV**
2. Cast session launches web receiver; pairing code appears on TV
3. Main app sends `session_prepare` with iPhone LAN IP + port `8766`
4. Session saved to App Group (`SessionStore`)
5. **Broadcast picker** → AndroidRemote extension starts
6. Extension runs `ExtensionSignalingServer` + WebRTC offer
7. Cast receiver polls offer, posts answer, video plays on TV

---

## Project layout

| Path | Targets | Purpose |
|------|---------|---------|
| `Shared/` | App + Extension | ARCP, SessionStore, WebRtcBroadcastEngine, ExtensionSignalingServer |
| `AndroidRemote/Data/Cast/` | App only | Google Cast SDK wrapper |
| `BroadcastExtension/` | Extension | ReplayKit SampleHandler |

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| No Cast devices | Set `CastConfig.receiverAppId`; same Wi‑Fi; allow Local Network |
| Package resolve fails | Xcode → File → Packages → Reset Package Caches |
| Broadcast fails | Physical device; WebRTC SPM linked; paired session in App Group |
| TV shows code but no video | Start **screen broadcast** on iPhone after Connect |

## iOS constraints

- Extension **50 MB memory cap** — H.264 only, 720p @ 30fps target
- Extension owns WebRTC (not main app) for system-wide mirroring
