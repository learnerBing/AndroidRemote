# AndroidRemote — iPhone → Google TV / Chromecast

Local-network screen mirroring: iOS sender + **Cast custom web receiver** (no TV app install).

| Version | Scope |
|---------|--------|
| **V1** | Screen mirroring only (WebRTC) |
| **V2** | Photos, videos, IPTV, YouTube URL cast, TV remote |

Full product roadmap: [ROADMAP.md](ROADMAP.md)

## Research Summary

### Options Evaluated

| Approach | Pros | Cons | Verdict |
|----------|------|------|---------|
| **WebRTC (P2P)** | Sub-second latency, no cloud, works on LAN | iOS needs Broadcast Extension | **Recommended transport** |
| **Cast custom web receiver** | No TV app, no Play Developer account, works on Google TV | 1080p+ harder than native; signaling bridged via iPhone | **Primary V1 receiver** |
| **Native Android TV app** | Best decode performance, on-TV signaling | Requires APK + Play/sideload | **Optional secondary** |
| **AirPlay receiver on TV** | Native Control Center UX | Apple proprietary stack | Alternative product |
| **Google Cast SDK (media URLs)** | Familiar Cast UX | Not designed for live screen mirror | Wrong tool alone |
| **RTMP push** | Simple server model | 3–5s latency | Too slow |

### Why Cast-first + WebRTC (not native TV app)

1. **No TV install**: Chromecast / Google TV already run Cast; host `cast-receiver/index.html` and register a free Cast App ID.
2. **iOS constraint**: System-wide screen capture requires a **Broadcast Upload Extension** (50 MB cap). Extension owns WebRTC — main app only launches Cast + pairing.
3. **Signaling on iPhone**: Extension runs ARCP HTTP on `:8766`; web receiver connects over LAN. Main app is not needed as relay after broadcast starts.
4. **STUN-only ICE** on home Wi‑Fi — no cloud TURN.

### iOS Critical Constraints

- Use **H.264 hardware encoding only** (VideoToolbox). VP8 software encoding OOMs in the extension.
- Cap at **720p @ 30 fps** initially (memory + thermal).
- **Pattern 2 architecture**: Extension owns WebRTC peer connection; main app handles Cast discovery, pairing, session config via App Group.
- Trigger broadcast via `RPSystemBroadcastPickerView`.

---

## System Architecture (V1 — Cast-first)

```
┌─────────────────────┐   Cast SDK (discover + launch)   ┌──────────────────────────┐
│   iPhone Main App   │ ────────────────────────────────► │  Chromecast / Google TV  │
│  - Discover Cast    │   custom messages (pair, prep)  │  cast-receiver/index.html│
│  - Launch receiver  │ ◄──────────────────────────────► │  - pairing code UI       │
│  - session_prepare  │                                 │  - WebRTC RTCPeerConnection│
└─────────┬───────────┘                                 └────────────┬─────────────┘
          │ App Group session                                         │
          ▼                                                           │ ARCP HTTP
┌─────────────────────┐         WebRTC (H.264, UDP)                  │ ws://iphone:8766
│  Broadcast Ext.     │ ◄═══════════════════════════════════════════►│
│  - ReplayKit        │                                              │
│  - ExtensionSignalingServer :8766                                   │
│  - WebRTC send      │                                              │
└─────────────────────┘                                              ▼
                                                            <video> fullscreen
```

### Optional: Native Android TV app

`android-tv/` uses mDNS (`_androidremote._tcp`) + HTTP signaling on the TV (`:8765`). Same WebRTC transport; useful for V2 media/remote and higher mirror quality.

---

## Clean Architecture (Both Platforms)

```
┌─────────────────────────────────────────────────────────┐
│                    Presentation                         │
│  SwiftUI / Compose TV  ·  ViewModels  ·  UI State       │
├─────────────────────────────────────────────────────────┤
│                      Domain                             │
│  Entities  ·  Use Cases  ·  Repository Protocols        │
├─────────────────────────────────────────────────────────┤
│                       Data                              │
│  Repository Impls  ·  WebRTC  ·  mDNS  ·  Signaling     │
└─────────────────────────────────────────────────────────┘
```

### Domain Entities

**V1 (implemented / in progress)**

- `CastDevice` — id, name, host, port, lastSeen
- `PairingSession` — sessionId, pairingCode, expiresAt
- `StreamConfig` — resolution, fps, bitrate, codec (h264)
- `ConnectionState` — idle | discovering | pairing | connecting | streaming | error

**V2 (domain stubs — see ROADMAP.md)**

- `CastMode` — screen | photo | video | iptv | youtube | remote
- `MediaItem` — id, title, sourceUrl, mimeType, thumbnailUrl
- `IptvChannel` / `IptvPlaylist` — name, group, streamUrl, channels[]
- `RemoteCommand` — key (dpad, media, system), action, sessionId

### Use Cases

**V1 — Screen mirror**

| Use Case | Sender (iOS) | Receiver (Android TV) |
|----------|--------------|------------------------|
| DiscoverDevices | Browse mDNS | Advertise mDNS |
| PairWithDevice | POST /pair with code | Validate code, create session |
| StartScreenCast | Launch broadcast ext. with session | Accept WebRTC offer |
| StopScreenCast | Stop broadcast | Tear down peer connection |
| ObserveConnection | Poll /status + ICE state | Expose /status |

**V2 — Media & remote** (planned)

| Use Case | Sender (iOS) | Receiver (Android TV) |
|----------|--------------|------------------------|
| CastPhotos | PHPicker → upload JPEG | Image viewer + slideshow |
| CastVideo | Local HTTP server → send URL | ExoPlayer LAN playback |
| SyncIptvPlaylist | Parse M3U → POST channels | Channel grid + ExoPlayer |
| CastYoutubeUrl | Parse videoId → POST | YouTube TV intent / embed |
| SendRemoteCommand | Touchpad UI → data channel | dispatchKeyEvent / a11y |
| SwitchCastMode | POST /session/mode | Mode router on TV |

---

## Signaling Protocol (ARCP v1)

Base URL: `http://{tv-host}:8765`

| Method | Path | Body | Response |
|--------|------|------|----------|
| GET | `/health` | — | `{ "ok": true }` |
| POST | `/pair` | `{ "code": "123456" }` | `{ "sessionId": "uuid" }` |
| POST | `/sdp` | `{ "sessionId", "type": "offer"\|"answer", "sdp" }` | `{ "ok": true }` |
| GET | `/sdp?sessionId=` | — | `{ "type", "sdp" }` or 204 |
| POST | `/ice` | `{ "sessionId", "candidate", "sdpMid", "sdpMLineIndex" }` | `{ "ok": true }` |
| GET | `/ice?sessionId=` | — | `{ "candidates": [...] }` |
| GET | `/status?sessionId=` | — | `{ "state": "waiting"\|"connected"\|"disconnected" }` |

Pairing code is shown on TV; user enters it on iPhone (QR pairing in V2).

### Cast custom messages (Cast-first path)

Namespace: `urn:x-cast:com.androidremote.signaling`

| Direction | type | Payload |
|-----------|------|---------|
| Receiver → iPhone | `pairing_code` | `{ "code": "123456" }` |
| iPhone → Receiver | `session_prepare` | `{ "sessionId", "signalingHost", "signalingPort" }` |
| Receiver → iPhone | `status` | `{ "state": "connected" }` |

After `session_prepare`, the Cast web receiver connects to ARCP HTTP on the **iPhone** (`signalingHost:8766`). Screen mirroring WebRTC runs extension → receiver over LAN.

### ARCP extensions on iPhone (Cast path)

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/sdp/offer?sessionId=` | Receiver polls iPhone offer |
| GET | `/sdp?sessionId=` | Extension polls receiver answer |
| GET | `/ice?sessionId=&side=sender` | Receiver polls extension ICE |
| GET | `/ice?sessionId=` | Extension polls receiver ICE |
| POST | `/ice?side=receiver` | Receiver posts ICE |

Native TV path (`:8765` on device) uses the table above.

### ARCP v2 extensions (media + remote)

Documented in full in [ROADMAP.md](ROADMAP.md). Summary:

- `POST /session/mode` — switch between screen, photo, video, iptv, youtube, remote
- `POST /media/photo`, `/media/load`, `/media/youtube` — media cast
- `POST /iptv/playlist` — IPTV channel sync
- `POST /remote` or WebRTC data channel — TV remote commands

Screen mirroring continues to use WebRTC; all other V2 modes use HTTP signaling + ExoPlayer/image viewer on TV.

---

## V2 mode router (TV)

```
                    ┌─────────────────┐
  /session/mode ──► │   ModeRouter    │
                    └────────┬────────┘
         ┌───────────────────┼───────────────────┐
         ▼                   ▼                   ▼
  ScreenMirrorHandler  MediaPlayerHandler  RemoteInputHandler
  (WebRTC + Surface)   (ExoPlayer/Coil)     (KeyEvent / a11y)
         │                   │                   │
         └───────────────────┴───────────────────┘
                    mutually exclusive decoder use
```

---

## Project Structure

```
AndoridRemote/
├── docs/
│   ├── ARCHITECTURE.md      (this file)
│   ├── ROADMAP.md           (V1/V2 product plan)
│   └── STITCH_DESIGNS.md    (UI briefs for Stitch MCP)
├── ios/                     (Swift, SwiftUI, Clean Architecture)
├── android-tv/              (Kotlin, Leanback, Clean Architecture)
└── cast-receiver/           (Optional HTML Cast custom receiver)
```

---

## Implementation Phases

### V1

### V1

#### Phase 1 — Foundation ✅
- [x] Architecture & protocol spec
- [x] Android TV: mDNS + signaling server + WebRTC receive skeleton
- [x] iOS: discovery UI + pairing flow + broadcast extension skeleton
- [x] iOS tab bar with V2 placeholders
- [x] Stitch UI designs for V1 screens
- [x] iOS V1 UI (Mirror home, connecting, streaming)
- [x] Android TV V1 UI (pairing, streaming overlay, settings)

#### Phase 2 — WebRTC Pipeline (in progress)
- [x] Android: AppContainer, ICE buffering, connection state → UI
- [x] iOS: Shared signaling client, SessionStore, WebRtcBroadcastEngine
- [x] iOS: ExtensionSignalingServer for Cast path (ARCP on iPhone :8766)
- [x] Cast receiver: WebRTC client + ARCP HTTP client in `cast-receiver/index.html`
- [x] iOS: Google Cast SDK integration (discovery, pairing, session_prepare)
- [ ] End-to-end LAN test at 720p (requires Cast App ID + physical devices)

#### Phase 3 — V1 polish
- [ ] Reconnect on ICE disconnect
- [ ] Audio (microphone from extension)
- [ ] Quality profiles (720p/1080p)
- [ ] Receiver diagnostics overlay (FPS, bitrate)

#### Phase 4 — Native TV polish (optional)
- [ ] Keep `android-tv/` as high-performance secondary receiver
- [ ] V2 ExoPlayer / remote on native app

### V2 (after V1 ships)

See [ROADMAP.md](ROADMAP.md): photos, videos, IPTV, YouTube, TV remote (phases 5–8).

---

## Dependencies

| Platform | Library | Purpose |
|----------|---------|---------|
| iOS | GoogleWebRTC (SPM) | Peer connection, H.264 |
| iOS | GoogleCastStatic (SPM: castlabs/google-cast-spm) | Discover Cast devices, custom messages |
| iOS | Network.framework | mDNS browse (native TV path) |
| Android | `org.webrtc:google-webrtc` | Peer connection |
| Android | NanoHTTPD | Local signaling |
| Android | AndroidX Leanback | TV UI |

---

## Security (LAN)

- Pairing code (6 digits, 5 min TTL) prevents drive-by casting on shared Wi‑Fi.
- No cloud relay; media stays on local subnet.
- Future: optional PIN on TV settings.
