#!/usr/bin/env bash
# One-command headless deploy (issue #23): build the source tarball,
# upload it to the VPS, and restart the systemd service — a five-minute,
# laptop-free update with no mid-session dependence.
# Usage: ./deploy.sh server | build | upload | restart [--dry-run] [--help]
# Stdlib only (bash + git + scp/ssh). `./deploy.sh --dry-run` prints markers
# only and never touches network, godot, or disk outside /tmp.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT="${TOGETHER_GODOT:-/usr/local/bin/godot}"
HOST="${TOGETHER_HOST:-}"
USER="${TOGETHER_USER:-together}"
DIR="${TOGETHER_DIR:-/srv/together/source}"
SERVICE="${TOGETHER_SERVICE:-together}"
PORT="${TOGETHER_PORT:-8080}"
DATA_DIR="${TOGETHER_DATA_DIR:-/srv/together/data}"
MAX_ROOMS="${TOGETHER_MAX_ROOMS:-64}"
TLS_MODE="${TOGETHER_TLS_MODE:-off}"
TARBALL="/tmp/together-deploy.tar.gz"

usage() {
	cat <<'EOF'
Usage: ./deploy.sh server | build | upload | restart [--dry-run] [--help]

  server    build + upload + restart (the normal update path)
  build     godot --headless --import, then git archive a source tarball
  upload    scp the tarball to the VPS and extract it over the source dir
  restart   ssh to the VPS and systemctl restart the service
  --dry-run print DRY_RUN_OK/BUILD_OK/UPLOAD_OK/RESTART_OK, change nothing
  --help    print this usage

Config (env only; flags live on the server itself, see docs/ops.md):
  TOGETHER_HOST       scp/ssh target (required for real runs, never for --dry-run)
  TOGETHER_USER       ssh user (default: together)
  TOGETHER_DIR        remote source dir (default: /srv/together/source)
  TOGETHER_SERVICE    systemd unit name (default: together)
  TOGETHER_GODOT      local godot binary (default: /usr/local/bin/godot)
  TOGETHER_PORT TOGETHER_DATA_DIR TOGETHER_MAX_ROOMS TOGETHER_TLS_MODE
                  server tuning recorded in deploy/systemd/together.service
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
		echo "deploy: TOGETHER_HOST is not set (scp/ssh target, e.g. TOGETHER_HOST=vps.example.com ./deploy.sh server)" >&2
		exit 2
	fi
}

do_build() {
	"$GODOT" --headless --path "$ROOT" --import
	git -C "$ROOT" archive --format=tar.gz -o "$TARBALL" HEAD
	echo "BUILD_OK"
}

do_upload() {
	require_host
	scp "$TARBALL" "$USER@$HOST:/tmp/together-deploy.tar.gz"
	ssh "$USER@$HOST" "mkdir -p '$DIR' && tar -xzf /tmp/together-deploy.tar.gz -C '$DIR' && rm -f /tmp/together-deploy.tar.gz"
	echo "UPLOAD_OK"
}

do_restart() {
	require_host
	ssh "$USER@$HOST" "sudo systemctl restart '$SERVICE'"
	echo "RESTART_OK"
}

case "$ACTION" in
	build) do_build ;;
	upload) do_upload ;;
	restart) do_restart ;;
	server)
		do_build
		do_upload
		do_restart
		;;
esac
