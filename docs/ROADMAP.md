# AndroidRemote — Product Roadmap

## Version Scope

| Version | Focus | Ship criteria |
|---------|--------|---------------|
| **V1** | Screen mirroring only | iPhone → TV live screen via WebRTC, pairing, stable 720p |
| **V2** | Media cast + TV remote | Photos, videos, IPTV, YouTube URL cast, in-app + system remote |

V1 and V2 share the same **discovery, pairing, and session layer**. V2 adds new **cast modes** on top of the existing ARCP signaling bus — no second app or protocol.

---

## V1 — Screen Mirroring (current)

### Features
- mDNS discovery (`_androidremote._tcp`)
- 6-digit LAN pairing
- ReplayKit Broadcast Extension → WebRTC H.264 → Android TV
- TV: pairing screen, fullscreen mirror, foreground service

### Out of scope for V1
- Photo/video library cast
- IPTV playlists
- YouTube
- Remote control
- QR pairing (deferred to V2)

### Known gaps / near-term TODOs (not started — noted 2026-08-21)
- **Screen rotation** — mirrored video is currently fixed-orientation (portrait); rotating the
  iPhone doesn't rotate the cast picture. Needs handling on both the extension's capture/encode
  side (`ios/Shared/WebRtcBroadcastEngine.swift`) and the receiver's video layout
  (`cast-receiver/index.html`, `test-receiver.html` already has `watchVideoLayout()` reacting to
  `videoWidth`/`videoHeight` as a reference).
- **Audio support** — V1 is video-only by design so far (see the `muted`/video-only comments
  throughout `cast-receiver/index.html` and `ios/Shared/ReplayKitAudioDevice.swift`). Wiring up
  the audio track end-to-end (already partially scaffolded in `ReplayKitAudioDevice`/
  `ReplayKitAudioRingBuffer` and in `test-receiver.html`'s separate `<audio>` element) is tracked
  here as a deliberate near-term addition, not yet started.

### V1 delivery phases
1. Foundation — scaffolds, signaling, Clean Architecture ✅
2. WebRTC pipeline — extension encode + TV decode
3. Polish — audio, reconnect, quality profiles
4. Optional Cast HTML receiver

---

## V2 — Media Cast & TV Remote

### Feature matrix

| Feature | User flow | Transport | TV playback |
|---------|-----------|-----------|-------------|
| **Photos** | Pick album/photos on iPhone → Cast | HTTP multipart or chunked POST to TV | `ImageViewer` + slideshow |
| **Videos** | Pick video from library → Cast | iPhone local HTTP server → TV pulls URL | ExoPlayer (LAN URL) |
| **IPTV** | Add M3U/M3U8 playlist on iPhone → sync channels | Signaling JSON + stream URLs | ExoPlayer (HLS/MPEG-TS) |
| **YouTube** | Paste/share YouTube link on iPhone | Signaling: `{ videoId, url }` | YouTube TV intent or embed WebView |
| **TV Remote** | Virtual D-pad + media keys on iPhone | WebRTC data channel or `/remote` WS | Key dispatch on TV |

### V2 module map (Clean Architecture)

```
domain/
  cast/
    CastMode.swift / CastMode.kt      — screen | photo | video | iptv | youtube
    MediaItem.swift / MediaItem.kt    — id, title, url, mimeType, thumbnail
  remote/
    RemoteCommand.swift / .kt         — key, action, payload
  iptv/
    IptvChannel.swift / .kt           — name, group, streamUrl, logoUrl
    IptvPlaylist.swift / .kt          — channels[], epgUrl?

usecases/
  CastPhotosUseCase
  CastVideoUseCase
  SyncIptvPlaylistUseCase
  CastYoutubeUrlUseCase
  SendRemoteCommandUseCase
  ObserveRemoteConnectionUseCase
```

Presentation gains a **tabbed iOS home**: Mirror | Photos | Videos | IPTV | YouTube | Remote.

TV gains **mode router**: switches between mirror surface, media player, photo viewer, IPTV channel grid, YouTube player, and remote listener.

---

## V2 technical design

### Shared principle: one session, many modes

After pairing, iPhone sends a **mode switch** message:

```json
POST /session/mode
{ "sessionId": "uuid", "mode": "screen" | "photo" | "video" | "iptv" | "youtube" | "remote" }
```

TV tears down or pauses the previous mode handler and activates the new one. Screen mirroring and media playback are **mutually exclusive** on the TV decoder.

---

### Photos cast

**Sender (iOS)**
- `PHPickerViewController` → selected `PHAsset`s
- Resize to max 4K long edge, JPEG 85% (configurable)
- Upload: `POST /media/photo` (multipart) or batch with `POST /media/photos/session`

**Receiver (Android TV)**
- Store in session cache or stream directly to `Coil`/`Glide` display
- Slideshow: `RemoteCommand` `next` / `prev` from iPhone remote tab
- Ken Burns optional in V2.1

**Why not WebRTC for photos:** still images don't need real-time transport; HTTP is simpler and reliable.

---

### Videos cast

**Sender (iOS)**
- Pick file via `PHPicker` or Files
- Start lightweight **local HTTP server** (e.g. GCDWebServer) on iPhone LAN IP
- Send TV: `POST /media/load` `{ "url": "http://192.168.x.x:port/video.mp4", "title": "..." }`

**Receiver (Android TV)**
- ExoPlayer plays LAN URL directly (same Wi‑Fi, no internet required for local files)
- Standard transport controls via remote commands

**Why not WebRTC for files:** file playback needs seek/buffer; ExoPlayer + HTTP URL is the right tool.

---

### IPTV

**Sender (iOS)**
- Parse M3U/M3U8 (UTF-8, `#EXTINF` tags)
- User edits/favorites playlists locally
- Sync: `POST /iptv/playlist` `{ "channels": [{ "name", "group", "streamUrl", "logoUrl?" }] }`

**Receiver (Android TV)**
- Channel grid (Leanback `BrowseSupportFragment` pattern)
- ExoPlayer for HLS (`.m3u8`), MPEG-TS (`.ts`), RTSP where supported
- Last-watched channel persisted on TV

**V2.1:** XMLTV EPG, catch-up URLs

**Note:** IPTV legality varies by region and source; app should only play user-provided playlist URLs.

---

### YouTube web cast

**Sender (iOS)**
- Share extension or in-app URL field
- Extract `videoId` from `youtube.com` / `youtu.be` links
- Send: `POST /media/youtube` `{ "videoId": "abc123", "url": "https://..." }`

**Receiver (Android TV)** — tiered fallback:
1. **Preferred:** Fire `Intent` to YouTube for Android TV (`com.google.android.youtube.tv`) with video ID
2. **Fallback:** In-app WebView with YouTube IFrame embed (no login, limited controls)
3. **Not in scope:** Stream extraction / ad-free playback (ToS violation)

User must have YouTube installed on TV for best experience.

---

### Android TV remote

Two tiers:

#### V2a — In-app remote (ship first)
Works while AndroidRemote TV app is in foreground:
- D-pad: up, down, left, right, select (center)
- Media: play, pause, stop, seek ±10s
- App: back (within app)

Transport: WebRTC **data channel** on existing peer connection (low latency) or `POST /remote` on signaling port.

```json
{ "sessionId": "uuid", "key": "DPAD_UP" | "DPAD_DOWN" | "DPAD_LEFT" | "DPAD_RIGHT" | "ENTER" | "BACK" | "PLAY" | "PAUSE" | "HOME" }
```

TV maps to `KeyEvent` via `dispatchKeyEvent` — controls our player UI and Leanback focus.

#### V2b — System remote (user opt-in)
Navigate Android TV home, other apps, volume:
- **Accessibility Service** on TV (user enables in Settings) — performs global back/home and gesture injection
- Alternative: research **Android TV Remote Service v2** pairing (heavier, Google protocol)

Ship V2a with media + IPTV; add V2b as optional "Full TV control" with clear permission onboarding.

**iPhone UI:** touchpad area + button row mimicking physical remote; haptic on press.

---

## ARCP protocol extensions (V2)

Base URL unchanged: `http://{tv-host}:8765`

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/session/mode` | Switch cast mode |
| POST | `/media/photo` | Upload photo (multipart) |
| POST | `/media/load` | Play video/audio from LAN URL |
| POST | `/media/youtube` | Open YouTube video |
| POST | `/iptv/playlist` | Replace/sync channel list |
| GET | `/iptv/channels` | TV-side channel list |
| POST | `/remote` | Send remote key command |
| WS | `/remote/ws` | Optional low-latency remote stream |

V1 endpoints (`/pair`, `/sdp`, `/ice`, `/status`) unchanged.

---

## V2 delivery phases

### Phase 5 — Media foundation
- [ ] `CastMode` entity + mode router on TV
- [ ] ExoPlayer integration on Android TV
- [ ] iOS local HTTP server for video URLs
- [ ] Photo upload + TV viewer

### Phase 6 — IPTV & YouTube
- [ ] M3U parser on iOS
- [ ] IPTV channel grid on TV
- [ ] YouTube URL cast + TV intent fallback

### Phase 7 — Remote
- [ ] WebRTC data channel for commands
- [ ] iPhone remote UI (touchpad + buttons)
- [ ] In-app key dispatch on TV
- [ ] Accessibility service for system remote (opt-in)

### Phase 8 — V2 polish
- [ ] QR pairing (replace 6-digit entry)
- [ ] Watch history, favorites
- [ ] Stitch UI for all V2 screens

---

## Stitch screens to add (V2)

See [STITCH_DESIGNS.md](STITCH_DESIGNS.md) — sections V2-iOS and V2-TV.

---

## What stays the same across versions

- Clean Architecture (domain / data / presentation)
- mDNS discovery + 6-digit pairing
- WebRTC for **screen mirror only**
- No cloud relay; LAN-first privacy model
- Native Android TV app as primary receiver
