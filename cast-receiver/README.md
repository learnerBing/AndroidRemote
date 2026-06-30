# AndroidRemote Cast Web Receiver

Primary TV receiver for V1 screen mirroring — **no Android TV app or Play Developer account required**.

Runs as a [Google Cast custom web receiver](https://developers.google.com/cast/docs/web_receiver) on Chromecast and Google TV.

## Direct LAN test (no Chromecast)

Use the **Mac relay** when Cast device registration is not ready. iPhone cannot reliably accept inbound LAN TCP, so signaling runs on your Mac — not on the iPhone.

### 1. Start relay on Mac (same Wi‑Fi)

```bash
python3 tools/lan-test-server.py
```

The script prints your Mac IP, e.g. `192.168.18.5`.

### 2. Open receiver in browser

Use the **Mac IP** from step 1 (not `0.0.0.0`, not the iPhone IP):

```
http://192.168.18.5:8080/test-receiver.html
```

### 3. Link from iPhone

1. iPhone app → **Test** tab
2. **Relay host** = Mac IP, **Port** = `8080`
3. Enter the 6-digit code shown in the browser → **Link Receiver**
4. **Then** start screen broadcast (Link must succeed first)

WebRTC video is peer-to-peer; the Mac only relays SDP/ICE.

### macOS Firewall (required for LAN IP)

`http://127.0.0.1:8080/...` works on the Mac, but `http://192.168.x.x:8080/...` shows **ERR_EMPTY_RESPONSE** until Python is allowed through the firewall.

**One-time fix** — run in Terminal (replace path if your script prints a different one):

```bash
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add "/opt/homebrew/Cellar/python@3.14/3.14.4/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python"
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp "/opt/homebrew/Cellar/python@3.14/3.14.4/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python"
```

Or use the helper script (prints the exact path on your Mac):

```bash
./tools/start-lan-test-server.sh
```

**GUI:** System Settings → Network → Firewall → Options… → **Python** → Allow incoming connections.

Verify from another device (or after fix):

```bash
curl http://YOUR_MAC_IP:8080/health
# → {"ok": true}
```

| Where you open the browser | URL to use |
|----------------------------|------------|
| On the Mac itself | `http://127.0.0.1:8080/test-receiver.html` |
| On TV / another device | `http://MAC_LAN_IP:8080/test-receiver.html` (needs firewall fix) |

Use the plain URL — **no `?iphone=`** query param.

> **Note:** GitHub Pages hosts static files only — it cannot run the relay. For test mode, always use `lan-test-server.py` on Mac.

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
