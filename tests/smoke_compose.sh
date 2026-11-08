#!/usr/bin/env bash
# Compose smoke (issue #51): mirrors tests/smoke_serve.sh against the
# container stack. Builds the image, starts `game` on a free $PORT,
# asserts GET / -> 200 JSON with "ok":true + "version": (and that only
# `game` runs by default), then tears the stack down.
# Stdlib only (bash + python3 + curl + docker compose). Prints COMPOSE_SMOKE_OK.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="together-smoke-$$"

PORT="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
export PORT

cleanup() {
	(cd "$ROOT" && PORT="$PORT" docker compose -p "$PROJECT" down -v >/dev/null 2>&1) || true
}
trap cleanup EXIT

fail() {
	echo "COMPOSE SMOKE FAIL: $1" >&2
	exit 1
}

(cd "$ROOT" && docker compose -p "$PROJECT" up --build -d) || fail "compose up failed"

RUNNING="$(cd "$ROOT" && docker compose -p "$PROJECT" ps --services --filter status=running)"
[ "$RUNNING" = "game" ] || fail "expected only 'game' running by default, got: $RUNNING"

for _i in $(seq 1 150); do
	CODE="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/" || true)"
	if [ "$CODE" = "200" ]; then break; fi
	sleep 0.2
done

BODY="$(curl -sS -m 5 "http://127.0.0.1:${PORT}/")" || fail "GET / failed"
echo "$BODY" | grep -q '"ok":true' || fail "body missing ok:true: $BODY"
echo "$BODY" | grep -q '"version":' || fail "body missing version: $BODY"

echo "COMPOSE_SMOKE_OK port=$PORT body=$BODY"
