# AndroidRemote Cast Web Receiver

Primary TV receiver for V1 screen mirroring — **no Android TV app or Play Developer account required**.

Runs as a [Google Cast custom web receiver](https://developers.google.com/cast/docs/web_receiver) on Chromecast and Google TV.

## Direct LAN test (no Chromecast)

Use **`test-receiver.html`** when Cast device registration is not ready:

```
https://learnerbing.github.io/AndroidRemote/test-receiver.html?iphone=YOUR_IPHONE_IP
```

1. iPhone app → **Test** tab → copy receiver URL
2. Open URL in TV browser (or laptop on same Wi‑Fi)
3. Enter 6-digit code from web page → **Link Receiver**
4. Start screen broadcast on iPhone

Pairing uses HTTP on iPhone port **8767**; WebRTC signaling on **8766** when broadcast starts.

---

## Host on GitHub Pages (free, recommended)

This repo includes a workflow that publishes **only** `cast-receiver/` to GitHub Pages over HTTPS.

### 1. Push to GitHub

```bash
cd /path/to/AndoridRemote
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO.git
git push -u origin main
```

### 2. Enable GitHub Pages

1. GitHub repo → **Settings** → **Pages**
2. **Build and deployment** → Source: **GitHub Actions**
3. Wait for the **Deploy Cast Receiver** workflow to finish (Actions tab)

Your receiver URL will be:

```
https://YOUR_USERNAME.github.io/YOUR_REPO/index.html
```

Example: repo `AndoridRemote` → `https://jane.github.io/AndoridRemote/index.html`

Re-deploys automatically when you push changes under `cast-receiver/`.

### 3. Register in Cast console

1. [Cast SDK Developer Console](https://cast.google.com/publish) → **Applications** → **Add new application** → **Custom Receiver**
2. **Receiver URL**: `https://YOUR_USERNAME.github.io/YOUR_REPO/index.html`
3. **Register** your Chromecast / Google TV (serial number) for development testing
4. Copy the **App ID**

Allow 5–15 minutes after saving, then reboot the Cast device once.

### 4. Configure iOS app

`ios/Shared/CastConfig.swift`:

```swift
static let receiverAppId = "YOUR_CAST_APP_ID"
```

```bash
open ios/AndroidRemote.xcodeproj
```

---

## Local dev (same Wi‑Fi, before Pages)

HTTP is allowed on LAN during Cast development:

```bash
cd cast-receiver
python3 -m http.server 8080 --bind 0.0.0.0
```

Register `http://YOUR_MAC_LAN_IP:8080/index.html` in the Cast console (not `localhost`).

---

## Other hosts

Firebase Hosting, Cloudflare Pages, and Netlify also work. GitHub Pages is the simplest starter if the code is already on GitHub.

---

## How it works

```
iPhone main app                Chromecast / Google TV
     │                              │
     │  Cast SDK: launch receiver   │
     ├─────────────────────────────►│  index.html loads
     │  custom: pairing_code        │  shows 6-digit code
     │◄─────────────────────────────┤
     │  custom: session_prepare     │
     ├─────────────────────────────►│  { host, port, sessionId }
     │                              │
iPhone Broadcast Extension          │
     │  ARCP HTTP :8766 on LAN      │
     │◄────────────────────────────►│  WebRTC answer + ICE
     │  WebRTC H.264 video          │
     └──────────────────────────────►│  <video> render
```

- **Signaling** runs on the iPhone (Broadcast Extension) at port `8766`
- **WebRTC** is peer-to-peer on the LAN (STUN only; no cloud TURN)
- **Pairing code** is shown on TV and sent to iPhone via Cast custom messages

## ARCP endpoints used by receiver

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/sdp/offer?sessionId=` | Poll iPhone offer |
| POST | `/sdp` | Post WebRTC answer |
| GET | `/ice?sessionId=&side=sender` | Poll iPhone ICE |
| POST | `/ice?side=receiver` | Post receiver ICE |

## Custom Cast channel

`urn:x-cast:com.androidremote.signaling`

Messages: `pairing_code`, `session_prepare`, `status`

## Optional: native Android TV app

The Kotlin app in `android-tv/` remains an optional high-performance path with on-TV signaling.
