#!/usr/bin/env bash
# Black-box smoke for the walking skeleton (mirrors issue #1 acceptance).
# Boots `godot --headless --path . -- --serve --port $PORT` and asserts:
#   GET /          -> 200, application/json, body has "ok":true + "version":
#   GET /ws        -> 101 upgrade with a valid Sec-WebSocket-Accept
#   GET /nope      -> 404 (never 500)
#   process        -> still foreground at 10s, every response within 2s
# Stdlib only (bash + python3). Exits non-zero on any mismatch.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-godot}"
LOG="$ROOT/.smoke_server.log"

PORT="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
export SMOKE_PORT="$PORT"
BOOT_EPOCH="$(date +%s)"

"$GODOT" --headless --path "$ROOT" -- --serve --port "$PORT" >"$LOG" 2>&1 &
SERVER_PID=$!

cleanup() {
	kill "$SERVER_PID" 2>/dev/null || true
	wait "$SERVER_PID" 2>/dev/null || true
	rm -f "$LOG"
}
trap cleanup EXIT

fail() {
	echo "SMOKE FAIL: $1" >&2
	exit 1
}

# Wait for the port (up to 15s); fail fast if the server dies first.
for _i in $(seq 1 150); do
	if python3 -c 'import os, socket; s = socket.socket(); s.settimeout(0.2); s.connect(("127.0.0.1", int(os.environ["SMOKE_PORT"]))); s.close()' 2>/dev/null; then
		break
	fi
	if ! kill -0 "$SERVER_PID" 2>/dev/null; then
		echo "--- server log ---" >&2
		cat "$LOG" >&2 || true
		fail "server exited during boot"
	fi
	sleep 0.1
done
python3 -c 'import os, socket; s = socket.socket(); s.settimeout(2); s.connect(("127.0.0.1", int(os.environ["SMOKE_PORT"]))); s.close()' \
	|| fail "port $PORT never opened"

python3 - <<'EOF' || exit 1
import os, time, urllib.request
port = int(os.environ["SMOKE_PORT"])
t0 = time.monotonic()
with urllib.request.urlopen(f"http://127.0.0.1:{port}/", timeout=5) as r:
    status, ctype, body = r.status, r.headers.get("Content-Type", ""), r.read().decode()
dt = time.monotonic() - t0
assert status == 200, f"GET / status {status}"
assert "application/json" in ctype, f"Content-Type {ctype!r}"
assert '"ok":true' in body, f"body {body!r}"
assert '"version":' in body, f"body {body!r}"
assert dt < 2.0, f"GET / took {dt:.2f}s"
print(f"health ok ({dt * 1000:.0f}ms): {body.strip()}")
EOF

python3 - <<'EOF' || exit 1
import base64, hashlib, os, socket, time
port = int(os.environ["SMOKE_PORT"])
key = base64.b64encode(os.urandom(16)).decode()
req = (
    f"GET /ws HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n"
    f"Upgrade: websocket\r\nConnection: Upgrade\r\n"
    f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
)
t0 = time.monotonic()
s = socket.create_connection(("127.0.0.1", port), timeout=5)
s.sendall(req.encode())
resp = b""
while b"\r\n\r\n" not in resp:
    chunk = s.recv(4096)
    if not chunk:
        break
    resp += chunk
dt = time.monotonic() - t0
s.close()
head = resp.split(b"\r\n\r\n")[0].decode("latin1")
lines = head.split("\r\n")
assert "101" in lines[0], f"expected 101, got {lines[0]!r}"
accept = ""
for ln in lines[1:]:
    if ln.lower().startswith("sec-websocket-accept:"):
        accept = ln.split(":", 1)[1].strip()
expected = base64.b64encode(
    hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()
).decode()
assert accept == expected, f"accept mismatch {accept!r} != {expected!r}"
assert dt < 2.0, f"/ws took {dt:.2f}s"
print(f"ws 101 ok ({dt * 1000:.0f}ms)")
EOF

python3 - <<'EOF' || exit 1
import os, time, urllib.request, urllib.error
port = int(os.environ["SMOKE_PORT"])
t0 = time.monotonic()
try:
    urllib.request.urlopen(f"http://127.0.0.1:{port}/does-not-exist", timeout=5)
    raise SystemExit("expected an HTTP error for /does-not-exist")
except urllib.error.HTTPError as e:
    dt = time.monotonic() - t0
    assert e.code == 404, f"status {e.code}"
    assert e.code != 500, "status must never be 500"
    assert dt < 2.0, f"404 took {dt:.2f}s"
    print(f"404 ok ({dt * 1000:.0f}ms)")
EOF

# Foreground check: the boot command must still be alive at 10s and serving.
NOW="$(date +%s)"
SLEEP_FOR=$((BOOT_EPOCH + 10 - NOW))
if [ "$SLEEP_FOR" -gt 0 ]; then
	sleep "$SLEEP_FOR"
fi
kill -0 "$SERVER_PID" 2>/dev/null || fail "server did not stay foreground for 10s"
curl -sS -m 5 "http://127.0.0.1:${PORT}/" -o /dev/null || fail "server stopped responding at 10s"

echo "SMOKE PASS: health 200, ws 101, 404, foreground 10s on port $PORT"
