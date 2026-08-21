#!/bin/bash
# Start AndroidRemote LAN relay. Handles macOS Firewall blocking Python on LAN IP.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PY="$(python3 -c 'import sys; print(sys.executable)')"
LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "")"
PORT="${1:-8080}"

echo "Python: $PY"
echo ""

if [[ -n "$LAN_IP" ]]; then
  if ! curl -sf --connect-timeout 2 "http://${LAN_IP}:${PORT}/health" >/dev/null 2>&1; then
    echo "============================================================"
    echo "LAN IP not reachable — macOS Firewall is blocking Python"
    echo "============================================================"
    echo ""
    echo "Run this ONCE (enter Mac password when prompted):"
    echo ""
    echo "  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add \"$PY\""
    echo "  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp \"$PY\""
    echo ""
    echo "Or: System Settings → Network → Firewall → Options…"
    echo "    Find Python → Allow incoming connections"
    echo ""
    echo "If you only open the receiver ON THIS MAC, use:"
    echo "  http://127.0.0.1:${PORT}/test-receiver.html"
    echo "  (LAN IP ${LAN_IP} fails from this Mac until firewall is fixed)"
    echo "============================================================"
    echo ""
  fi
fi

exec "$PY" tools/lan-test-server.py --port "$PORT"
