#!/usr/bin/env python3
"""LAN test server on Mac: static cast-receiver files + ARCP signaling relay.

iPhone and browser both connect OUT to this Mac — no inbound TCP to iPhone required.

Usage:
  python3 tools/lan-test-server.py
  python3 tools/lan-test-server.py --port 8080
"""
from __future__ import annotations

import argparse
import json
import os
import socket
import sys
import threading
import time
from datetime import datetime, timezone
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from typing import Any
from urllib.parse import parse_qs, urlparse

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "cast-receiver"))

lock = threading.Lock()
links_by_code: dict[str, dict[str, Any]] = {}
sessions: dict[str, dict[str, Any]] = {}
waiting_codes: dict[str, float] = {}
_offer_poll_counts: dict[str, int] = {}
_status_poll_counts: dict[str, int] = {}


def _ts() -> str:
    return datetime.now(timezone.utc).strftime("%H:%M:%S")


def log_event(event: str, client: str = "", **fields: Any) -> None:
    parts = [f"[{_ts()}]", event]
    if client:
        parts.append(f"from={client}")
    for key, value in fields.items():
        parts.append(f"{key}={value}")
    print(" ".join(parts), flush=True)


def sid_prefix(session_id: str) -> str:
    return session_id[:8] + "…" if len(session_id) >= 8 else session_id


def new_session() -> dict[str, Any]:
    return {
        "state": "waiting",
        "offer": None,
        "answer": None,
        "ice_sender": [],
        "ice_receiver": [],
        "created_at": time.time(),
    }


def session_summary(session_id: str) -> str:
    with lock:
        session = sessions.get(session_id, {})
        offer = session.get("offer")
        answer = session.get("answer")
        return (
            f"state={session.get('state', '?')} "
            f"offer={'yes' if offer else 'no'} "
            f"answer={'yes' if answer else 'no'} "
            f"ice_s={len(session.get('ice_sender', []))} "
            f"ice_r={len(session.get('ice_receiver', []))}"
        )


class LanRelayHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def log_message(self, fmt: str, *args) -> None:
        # Suppress default access log — we emit structured events instead.
        pass

    @property
    def client_ip(self) -> str:
        return self.client_address[0]

    def end_headers(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        super().end_headers()

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self.end_headers()

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path
        query = {k: v[0] for k, v in parse_qs(parsed.query).items()}

        if path in ("/health", "/test/link", "/test/active-code", "/sdp/offer", "/sdp", "/ice", "/status"):
            log_event("GET", client=self.client_ip, path=path, query=query or "-")

        if path == "/health":
            self._json(200, {"ok": True})
            return
        if path == "/test/link":
            self._handle_test_link_get(query)
            return
        if path == "/test/active-code":
            self._handle_test_active_code_get()
            return
        if path == "/sdp/offer":
            self._handle_sdp_offer_get(query)
            return
        if path == "/sdp":
            self._handle_sdp_answer_get(query)
            return
        if path == "/ice":
            self._handle_ice_get(query)
            return
        if path == "/status":
            self._handle_status_get(query)
            return
        super().do_GET()

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path
        query = {k: v[0] for k, v in parse_qs(parsed.query).items()}
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode("utf-8") if length else ""
        data = json.loads(body) if body else {}

        if path in ("/test/link", "/test/register", "/sdp", "/ice", "/status"):
            summary = self._post_summary(path, data, query)
            log_event("POST", client=self.client_ip, path=path, query=query or "-", **summary)

        if path == "/test/link":
            self._handle_test_link_post(data)
            return
        if path == "/test/register":
            self._handle_test_register_post(data)
            return
        if path == "/sdp":
            self._handle_sdp_post(data)
            return
        if path == "/ice":
            self._handle_ice_post(data, query)
            return
        if path == "/status":
            self._handle_status_post(data)
            return
        if path == "/debug/log":
            self._handle_debug_log_post(data)
            return
        self.send_error(404)

    def _post_summary(self, path: str, data: dict[str, Any], query: dict[str, str]) -> dict[str, Any]:
        if path == "/test/link":
            return {"code": data.get("code", ""), "session": sid_prefix(str(data.get("sessionId", "")))}
        if path == "/test/register":
            return {"code": data.get("code", "")}
        if path == "/sdp":
            sdp = str(data.get("sdp", ""))
            return {
                "type": data.get("type", ""),
                "session": sid_prefix(str(data.get("sessionId", ""))),
                "sdp_bytes": len(sdp),
            }
        if path == "/ice":
            cand = str(data.get("candidate", ""))
            preview = cand[:60] + "…" if len(cand) > 60 else cand
            return {
                "side": query.get("side", "sender"),
                "session": sid_prefix(str(data.get("sessionId", ""))),
                "candidate": preview or "(empty)",
            }
        if path == "/status":
            return {"state": data.get("state", ""), "session": sid_prefix(str(data.get("sessionId", "")))}
        return {}

    def _handle_test_link_post(self, data: dict[str, Any]) -> None:
        code = str(data.get("code", ""))
        session_id = str(data.get("sessionId", ""))
        if len(code) != 6 or not session_id:
            log_event("link_rejected", client=self.client_ip, reason="bad code or sessionId")
            self.send_error(400, "code and sessionId required")
            return
        host, port = self.server.server_address  # type: ignore[attr-defined]
        with lock:
            links_by_code[code] = {
                "sessionId": session_id,
                "signalingHost": local_lan_ip(),
                "signalingPort": port,
                "state": "ready",
            }
            sessions.setdefault(session_id, new_session())
            _offer_poll_counts[sid_prefix(session_id)] = 0
        log_event(
            "link_ok",
            client=self.client_ip,
            code=code,
            session=sid_prefix(session_id),
            relay=f"{local_lan_ip()}:{port}",
            hint="iPhone linked — start broadcast (AndroidRemote extension)",
        )
        self._json(200, {"ok": True})

    def _handle_test_link_get(self, query: dict[str, str]) -> None:
        code = query.get("code", "")
        with lock:
            record = links_by_code.get(code)
        if not record:
            log_event("link_poll_miss", client=self.client_ip, code=code or "(none)")
            self.send_response(204)
            self.end_headers()
            return
        log_event(
            "link_poll_ok",
            client=self.client_ip,
            code=code,
            session=sid_prefix(str(record.get("sessionId", ""))),
        )
        self._json(200, record)

    def _handle_test_register_post(self, data: dict[str, Any]) -> None:
        code = str(data.get("code", ""))
        if len(code) != 6:
            log_event("register_rejected", client=self.client_ip, reason="bad code")
            self.send_error(400, "6-digit code required")
            return
        with lock:
            waiting_codes[code] = time.time()
        log_event("browser_registered", client=self.client_ip, code=code, hint="waiting for iPhone link")
        self._json(200, {"ok": True})

    def _handle_test_active_code_get(self) -> None:
        with lock:
            unlinked = [c for c in waiting_codes if c not in links_by_code]
            if not unlinked:
                log_event("active_code_miss", client=self.client_ip, reason="no browser waiting")
                self.send_response(204)
                self.end_headers()
                return
            code = max(unlinked, key=lambda c: waiting_codes[c])
        log_event("active_code_ok", client=self.client_ip, code=code)
        self._json(200, {"code": code})

    def _handle_sdp_post(self, data: dict[str, Any]) -> None:
        session_id = str(data.get("sessionId", ""))
        sdp_type = str(data.get("type", ""))
        sdp = str(data.get("sdp", ""))
        with lock:
            session = sessions.setdefault(session_id, new_session())
            if sdp_type == "offer":
                session["offer"] = sdp
                session["state"] = "connecting"
                _offer_poll_counts[sid_prefix(session_id)] = 0
            elif sdp_type == "answer":
                session["answer"] = sdp
                session["state"] = "connecting"
        log_event(
            "sdp_stored",
            client=self.client_ip,
            type=sdp_type,
            session=sid_prefix(session_id),
            bytes=len(sdp),
            summary=session_summary(session_id),
        )
        self._json(200, {"ok": True})

    def _handle_sdp_offer_get(self, query: dict[str, str]) -> None:
        session_id = query.get("sessionId", "")
        with lock:
            offer = sessions.get(session_id, {}).get("offer")
        if not offer:
            key = sid_prefix(session_id)
            _offer_poll_counts[key] = _offer_poll_counts.get(key, 0) + 1
            n = _offer_poll_counts[key]
            if n == 1 or n % 10 == 0:
                log_event(
                    "offer_missing",
                    client=self.client_ip,
                    session=key,
                    polls=n,
                    hint="no POST /sdp offer yet — start iPhone broadcast (AndroidRemote extension)",
                )
            self.send_response(204)
            self.end_headers()
            return
        log_event(
            "offer_delivered",
            client=self.client_ip,
            session=sid_prefix(session_id),
            bytes=len(offer),
        )
        self._json(200, {"sessionId": session_id, "type": "offer", "sdp": offer})

    def _handle_sdp_answer_get(self, query: dict[str, str]) -> None:
        session_id = query.get("sessionId", "")
        with lock:
            answer = sessions.get(session_id, {}).get("answer")
        if not answer:
            log_event("answer_missing", client=self.client_ip, session=sid_prefix(session_id))
            self.send_response(204)
            self.end_headers()
            return
        log_event(
            "answer_delivered",
            client=self.client_ip,
            session=sid_prefix(session_id),
            bytes=len(answer),
        )
        self._json(200, {"sessionId": session_id, "type": "answer", "sdp": answer})

    def _handle_ice_post(self, data: dict[str, Any], query: dict[str, str]) -> None:
        session_id = str(data.get("sessionId", ""))
        side = query.get("side", "sender")
        candidate = {
            "candidate": data.get("candidate", ""),
            "sdpMid": data.get("sdpMid"),
            "sdpMLineIndex": data.get("sdpMLineIndex", 0),
        }
        added = False
        with lock:
            session = sessions.setdefault(session_id, new_session())
            key = "ice_receiver" if side == "receiver" else "ice_sender"
            cand_str = str(candidate.get("candidate", ""))
            if cand_str:
                existing = session[key]
                if not any(c.get("candidate") == cand_str for c in existing):
                    session[key].append(candidate)
                    added = True
        if added:
            with lock:
                total = len(sessions.get(session_id, {}).get(key, []))
            log_event(
                "ice_added",
                client=self.client_ip,
                side=side,
                session=sid_prefix(session_id),
                total=total,
            )
        self._json(200, {"ok": True})

    def _handle_ice_get(self, query: dict[str, str]) -> None:
        session_id = query.get("sessionId", "")
        side = query.get("side", "receiver")
        drain = query.get("drain", "0") == "1"
        with lock:
            session = sessions.get(session_id, {})
            key = "ice_sender" if side == "sender" else "ice_receiver"
            candidates = list(session.get(key, []))
            if drain:
                session[key] = []
        log_event(
            "ice_get",
            client=self.client_ip,
            side=side,
            session=sid_prefix(session_id),
            count=len(candidates),
            drain=drain,
        )
        self._json(200, {"candidates": candidates})

    def _handle_status_get(self, query: dict[str, str]) -> None:
        session_id = query.get("sessionId", "")
        with lock:
            state = sessions.get(session_id, {}).get("state", "waiting")
        key = sid_prefix(session_id)
        _status_poll_counts[key] = _status_poll_counts.get(key, 0) + 1
        n = _status_poll_counts[key]
        if n == 1 or n % 20 == 0 or state != "waiting":
            log_event("status_get", client=self.client_ip, session=key, state=state, polls=n)
        self._json(200, {"state": state})

    def _handle_status_post(self, data: dict[str, Any]) -> None:
        session_id = str(data.get("sessionId", ""))
        state = str(data.get("state", ""))
        if not session_id or not state:
            log_event("status_rejected", client=self.client_ip, reason="missing fields")
            self.send_error(400, "sessionId and state required")
            return
        with lock:
            session = sessions.setdefault(session_id, new_session())
            session["state"] = state
            if state in ("ended", "disconnected"):
                session["offer"] = None
                session["answer"] = None
                session["ice_sender"] = []
                session["ice_receiver"] = []
                _offer_poll_counts[sid_prefix(session_id)] = 0
                _status_poll_counts[sid_prefix(session_id)] = 0
        log_event(
            "status_set",
            client=self.client_ip,
            session=sid_prefix(session_id),
            state=state,
            summary=session_summary(session_id),
        )
        self._json(200, {"ok": True})

    def _handle_debug_log_post(self, data: dict[str, Any]) -> None:
        component = str(data.get("component", "?"))
        level = str(data.get("level", "info"))
        message = str(data.get("message", ""))
        session_id = str(data.get("sessionId", ""))
        session = sid_prefix(session_id) if session_id else "-"
        log_event(
            "iphone_log",
            client=self.client_ip,
            component=component,
            level=level,
            session=session,
            msg=message,
        )
        self._json(200, {"ok": True})

    def _json(self, status: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def local_lan_ip() -> str:
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.connect(("8.8.8.8", 80))
        ip = sock.getsockname()[0]
        sock.close()
        return ip
    except OSError:
        return "127.0.0.1"


def probe_http(host: str, port: int) -> bool:
    """Return True if GET /health returns JSON with ok=true."""
    try:
        sock = socket.create_connection((host, port), timeout=2)
        request = (
            f"GET /health HTTP/1.1\r\n"
            f"Host: {host}:{port}\r\n"
            f"Connection: close\r\n\r\n"
        )
        sock.sendall(request.encode("utf-8"))
        chunks: list[bytes] = []
        while True:
            part = sock.recv(4096)
            if not part:
                break
            chunks.append(part)
        sock.close()
        body = b"".join(chunks).decode("utf-8", errors="replace")
        return '"ok": true' in body or '"ok":true' in body
    except OSError:
        return False


def print_firewall_help(python_exe: str) -> None:
    print()
    print("=" * 60)
    print("LAN IP NOT REACHABLE — macOS Firewall is blocking Python")
    print("=" * 60)
    print()
    print("Run ONCE in Terminal (Mac password required):")
    print()
    print(f'  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add "{python_exe}"')
    print(f'  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp "{python_exe}"')
    print()
    print("Or: System Settings → Network → Firewall → Options…")
    print("    Find “Python” → Allow incoming connections")
    print()
    print("Then restart this server.")
    print()
    print("Browsing ON THIS MAC only? Use http://127.0.0.1:PORT/test-receiver.html")
    print("iPhone / TV must use the LAN IP — firewall fix required for those.")
    print("Do NOT use ?iphone= in the URL.")
    print("=" * 60)
    print()


def main() -> None:
    parser = argparse.ArgumentParser(description="AndroidRemote LAN test server")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--bind", default="0.0.0.0")
    args = parser.parse_args()

    httpd = ThreadingHTTPServer((args.bind, args.port), LanRelayHandler)
    httpd.daemon_threads = True
    ip = local_lan_ip()
    print(f"Serving {ROOT}")
    print(f"Local:  http://127.0.0.1:{args.port}/test-receiver.html")
    print(f"LAN:    http://{ip}:{args.port}/test-receiver.html")
    print(f"iPhone Test tab → Relay host: {ip}  Port: {args.port}")
    print("No ?iphone= query param — signaling stays on this Mac.")
    print()
    print("Log legend:")
    print("  link_ok          iPhone linked code → session")
    print("  sdp_stored offer iPhone broadcast posted WebRTC offer")
    print("  offer_missing    browser polling, no offer yet (every 10 polls)")
    print("  offer_delivered  browser got offer → should show video soon")
    print("  iphone_log       iPhone/broadcast extension log line (no Xcode attach needed)")
    print()

    server_thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    server_thread.start()

    if ip != "127.0.0.1":
        lan_ok = probe_http(ip, args.port)
        local_ok = probe_http("127.0.0.1", args.port)
        if local_ok and not lan_ok:
            print_firewall_help(sys.executable)
        elif lan_ok:
            print(f"LAN check OK — other devices can use http://{ip}:{args.port}/")

    try:
        server_thread.join()
    except KeyboardInterrupt:
        print("\nStopped.")
        httpd.shutdown()


if __name__ == "__main__":
    main()
