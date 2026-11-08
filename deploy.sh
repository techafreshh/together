#!/usr/bin/env bash
# Compose-based deploy (issue #51): build the game image, sync the source
# to the VPS, and run the compose stack — the VPS needs nothing but Docker.
# Usage: ./deploy.sh server | build | upload | restart [--dry-run] [--help]
# Stdlib only (bash + git + rsync/ssh). `./deploy.sh --dry-run` prints markers
# only and never touches network, docker, or disk outside /tmp.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST="${TOGETHER_HOST:-}"
USER="${TOGETHER_USER:-together}"
DIR="${TOGETHER_DIR:-/srv/together/source}"
SERVICE="${TOGETHER_SERVICE:-together}"
PORT="${TOGETHER_PORT:-8080}"
DATA_DIR="${TOGETHER_DATA_DIR:-/data}"
MAX_ROOMS="${TOGETHER_MAX_ROOMS:-64}"
TLS_MODE="${TOGETHER_TLS_MODE:-off}"
TUNNEL_TOKEN="${TUNNEL_TOKEN:-}"

usage() {
	cat <<'EOF'
Usage: ./deploy.sh server | build | upload | restart [--dry-run] [--help]

  server    ensure docker + sync source + compose build + up (the normal update path)
  build     docker compose build locally
  upload    sync source to the VPS (remote git pull, else rsync)
  restart   ssh to the VPS and docker compose build + up -d (plus --profile tunnel when TUNNEL_TOKEN is set)
  --dry-run print DRY_RUN_OK/BUILD_OK/UPLOAD_OK/RESTART_OK, change nothing
  --help    print this usage

Config (env only; server tuning lives in the remote .env, see docs/ops.md):
  TOGETHER_HOST       ssh target (required for real runs, never for --dry-run)
  TOGETHER_USER       ssh user (default: together)
  TOGETHER_DIR        remote checkout dir holding docker-compose.yml (default: /srv/together/source)
  TOGETHER_SERVICE    legacy systemd unit name (default: together; the unit left the active path, see docs/ops.md)
  TUNNEL_TOKEN        when set, the tunnel profile is started too (forwarded in the remote environment only, never written to a file)
  TOGETHER_PORT TOGETHER_DATA_DIR TOGETHER_MAX_ROOMS TOGETHER_TLS_MODE
                  server tuning recorded in the remote .env (compose reads PORT/TOGETHER_*)
EOF
}

DRY_RUN=0
ACTION=""
for arg in "$@"; do
	case "$arg" in
		--dry-run) DRY_RUN=1 ;;
		--help|-h) usage; exit 0 ;;
		server|build|upload|restart) ACTION="$arg" ;;
		*)
			echo "deploy: unknown argument '$arg'" >&2
			usage >&2
			exit 2
			;;
	esac
done

if [ "$DRY_RUN" = "1" ]; then
	echo "DRY_RUN_OK"
	echo "config: port=$PORT data_dir=$DATA_DIR max_rooms=$MAX_ROOMS tls_mode=$TLS_MODE service=$SERVICE dir=$DIR"
	echo "BUILD_OK"
	echo "UPLOAD_OK"
	echo "RESTART_OK"
	exit 0
fi

if [ -z "$ACTION" ]; then
	echo "deploy: need an action (server | build | upload | restart)" >&2
	usage >&2
	exit 2
fi

require_host() {
	if [ -z "$HOST" ]; then
		echo "deploy: TOGETHER_HOST is not set (ssh target, e.g. TOGETHER_HOST=vps.example.com ./deploy.sh server)" >&2
		exit 2
	fi
}

ensure_remote_docker() {
	require_host
	if ! ssh "$USER@$HOST" "command -v docker >/dev/null 2>&1"; then
		ssh "$USER@$HOST" "curl -fsSL https://get.docker.com | sh"
	fi
	if ! ssh "$USER@$HOST" "docker compose version >/dev/null 2>&1"; then
		echo "deploy: remote host has docker but no compose plugin" >&2
		exit 1
	fi
}

do_build() {
	(cd "$ROOT" && docker compose build)
	echo "BUILD_OK"
}

do_upload() {
	require_host
	if ssh "$USER@$HOST" "git -C '$DIR' rev-parse --is-inside-work-tree >/dev/null 2>&1"; then
		ssh "$USER@$HOST" "git -C '$DIR' pull --ff-only"
	else
		rsync -az --delete --exclude='.git' --exclude='.godot' --exclude='.env' "$ROOT/" "$USER@$HOST:$DIR/"
	fi
	echo "UPLOAD_OK"
}

do_restart() {
	require_host
	ssh "$USER@$HOST" "cd '$DIR' && docker compose build && docker compose up -d"
	if [ -n "$TUNNEL_TOKEN" ]; then
		escaped="${TUNNEL_TOKEN//\'/\'\\\'\'}"
		ssh "$USER@$HOST" "cd '$DIR' && TUNNEL_TOKEN='$escaped' docker compose --profile tunnel up -d"
	fi
	echo "RESTART_OK"
}

case "$ACTION" in
	build) do_build ;;
	upload) do_upload ;;
	restart) do_restart ;;
	server)
		ensure_remote_docker
		do_upload
		do_restart
		;;
esac
