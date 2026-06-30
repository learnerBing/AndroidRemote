# AndroidRemote

Cast from **iPhone** to **Google TV / Chromecast** over local Wi‑Fi — no cloud, no TV app install.

## Versions

| Version | Features |
|---------|----------|
| **V1** | Screen mirroring (WebRTC) |
| **V2** | Photos cast, videos cast, IPTV, YouTube URL cast, TV remote |

See [docs/ROADMAP.md](docs/ROADMAP.md) for the full V2 plan.

## Stack

| Component | Technology |
|-----------|------------|
| Transport | **WebRTC** (H.264, LAN P2P) |
| TV receiver | **Cast custom web receiver** (`cast-receiver/`) |
| Discovery | Google Cast SDK (+ optional mDNS for native TV app) |
| Signaling | ARCP HTTP on iPhone (`:8766`) when casting; Cast custom messages for pairing |
| iOS capture | ReplayKit Broadcast Upload Extension |
| Optional | Native Kotlin Android TV app (`android-tv/`) |

## Why Cast-first

- **No Play Developer account** for TV — register a free Cast App ID and host the HTML receiver over HTTPS.
- **No TV install** — works on Chromecast and Google TV out of the box.
- **WebRTC** still gives sub-second LAN latency; extension hosts signaling so mirroring works when the main app is backgrounded.

## Project Layout

```
docs/ARCHITECTURE.md     — system design & protocol
docs/ROADMAP.md          — V1/V2 product roadmap
cast-receiver/           — primary TV receiver (host over HTTPS)
ios/                     — iPhone sender (Swift, Clean Architecture)
android-tv/              — optional native TV receiver
```

## Quick Start

### 1. Cast receiver (TV side — one-time)

See [cast-receiver/README.md](cast-receiver/README.md). **GitHub Pages** (free HTTPS) is set up via `.github/workflows/deploy-cast-receiver.yml`:

1. Push repo to GitHub → **Settings → Pages → GitHub Actions**
2. Receiver URL: `https://YOUR_USERNAME.github.io/YOUR_REPO/index.html`
3. Register that URL in [Cast SDK Developer Console](https://cast.google.com/publish)
4. Set App ID in `ios/Shared/CastConfig.swift`

### 2. iOS sender

```bash
cd ios
open AndroidRemote.xcodeproj
```

Set signing Team on both targets. See [ios/README.md](ios/README.md).

### 3. Optional native Android TV

```bash
cd android-tv
# Open in Android Studio
```

## Pairing Flow (Cast)

1. Open **AndroidRemote** on iPhone → select Chromecast / Google TV
2. Tap **Connect to TV** → receiver shows 6-digit code on TV
3. Tap **broadcast picker** → start screen share
4. TV displays mirrored iPhone screen

## Status

### V1 (in progress)
- **Phase 1:** Architecture, scaffolds, UI ✅
- **Phase 2:** Cast-first WebRTC pipeline wired (needs Cast App ID + device test)
- **Phase 3:** Audio, reconnect, quality profiles

### V2 (planned)
- Photos, videos, IPTV, YouTube, TV remote (native TV app recommended)

Details: [docs/ROADMAP.md](docs/ROADMAP.md)

## License

TBD
