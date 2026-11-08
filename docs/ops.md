# Ops: deploy the headless server (issue #51)

One command ships the headless server as a Docker Compose stack, an
optional Cloudflare tunnel exposes it, and flags/env select port, data
dir, room cap, and TLS mode. The normal update is a five-minute,
laptop-free `./deploy.sh server` — ensure Docker, sync source, compose
build, compose up — with no mid-session dependence. The VPS needs
nothing but Docker.

## What this covers

- `Dockerfile`: multi-stage server image (Godot fetch + `--import` in
  the builder, godot binary + project on Debian slim in the runtime).
- `docker-compose.yml`: the `game` service plus the profile-gated
  `cloudflared` tunnel service.
- `deploy.sh`: ensures Docker on the VPS, syncs the source, and runs
  the compose stack over ssh.
- Server flags/env for `--port`, `--data-dir`, `--max-rooms`,
  `--tls-mode`.
- `deploy/systemd/together.service`: legacy reference only (see
  "systemd (legacy)" below). It is kept for reference and is no longer
  part of the deploy path.

## The `./deploy server` name

Older runbooks call the update `./deploy server`; that is this same
script. The checked-in name is `deploy.sh` because the `deploy/`
directory already holds the legacy systemd unit, so run
`./deploy.sh server`.

## Operator prerequisites

Docker on the VPS is installed for you: `./deploy.sh server` installs
it via the official `get.docker.com` script when `docker` is missing.
A missing compose plugin is a hard error — install the Docker Compose
plugin on the VPS before deploying.

- A VPS you can ssh into, with nothing preinstalled but (eventually)
  Docker and its compose plugin.
- A checkout of this repo on the VPS at `TOGETHER_DIR`
  (default `/srv/together/source`), or an empty dir `deploy.sh` can
  rsync into.
- DNS pointing at the VPS if you expose it directly; or a Cloudflare
  tunnel (below) so no inbound port is needed.

Locally you need Docker (for `build`) plus `git`, `rsync`, and `ssh`.

## Configure

```bash
cp .env.example .env
```

`.env` is never committed (it may hold `TUNNEL_TOKEN`). Tune it:

| Var                 | Default | Notes                              |
|---------------------|---------|------------------------------------|
| `PORT`              | `8080`  | host port mapped to container 8080 |
| `TOGETHER_DATA_DIR` | `/data` | JSON persistence dir (named volume)|
| `TOGETHER_MAX_ROOMS`| `64`    | clamped 1..256                     |
| `TOGETHER_TLS_MODE` | `off`   | `off` \| `behind-proxy`            |
| `TUNNEL_TOKEN`      | (empty) | Cloudflare tunnel token (below)    |

The same `TOGETHER_*` names the native server reads (flags beat env
beat compiled defaults) are passed through to the `game` service; see
"Flags and env" below. With the tunnel in front, use
`TOGETHER_TLS_MODE=behind-proxy` — the tunnel terminates TLS, the game
server never does.

## Run locally

```bash
docker compose up --build -d
curl -s http://127.0.0.1:8080/
# {"ok":true,"version":"..."}
```

`PORT=9001 docker compose up --build -d` maps the host port instead;
the container always serves 8080 internally.

## Tunnel (optional)

1. Create the tunnel in the Cloudflare dashboard (Zero Trust ->
   Tunnels) pointing at `http://game:8080`.
2. Store its token in `.env` (never committed):
   `TUNNEL_TOKEN=<token-from-the-dashboard>`.
3. Start the tunnel service explicitly:

```bash
docker compose --profile tunnel up -d
```

`cloudflared` only starts when explicitly requested with
`--profile tunnel`; a plain `docker compose up -d` starts just `game`.

## Update flow

```bash
# Ship everything (ensure docker + sync + build + up):
TOGETHER_HOST=vps.example.com ./deploy.sh server

# Or step by step:
TOGETHER_HOST=vps.example.com ./deploy.sh build    # prints BUILD_OK
TOGETHER_HOST=vps.example.com ./deploy.sh upload   # prints UPLOAD_OK
TOGETHER_HOST=vps.example.com ./deploy.sh restart  # prints RESTART_OK
```

`upload` runs a remote `git pull --ff-only` when the remote dir is a
checkout, else rsyncs the source (excluding `.git`/`.godot`/`.env`).
`restart` runs a remote `docker compose build` + `docker compose up -d`,
and adds `--profile tunnel up -d` (with `TUNNEL_TOKEN` forwarded in the
remote environment only) when `TUNNEL_TOKEN` is set locally. Without
`TOGETHER_HOST` a real run exits 2 and changes nothing.

```bash
# Dry run: markers only, no network, no docker, no disk writes outside /tmp:
./deploy.sh --dry-run
# DRY_RUN_OK, BUILD_OK, UPLOAD_OK, RESTART_OK (exit 0)
```

Rollback is the previous image/source: re-run `./deploy.sh upload`
from the older commit (or `docker compose up -d` against the previous
local build) and restart.

## Flags and env

The server reads `--port`, `--data-dir`, `--max-rooms`, `--tls-mode`
flags, else the matching env var, else the compiled default. Precedence
is always flag > env > default; invalid values fall back silently and
never fail boot.

| Flag          | Env                 | Default            | Notes                              |
|---------------|---------------------|--------------------|------------------------------------|
| `--port`      | `TOGETHER_PORT`     | `8080`             | 1..65535; health + `/ws` port      |
| `--net-port`  | `TOGETHER_NET_PORT` | `port + 1`         | game socket; health-only if busy   |
| `--data-dir`  | `TOGETHER_DATA_DIR` | `user://players`   | JSON persistence directory         |
| `--max-rooms` | `TOGETHER_MAX_ROOMS`| `64`               | clamped 1..256                     |
| `--tls-mode`  | `TOGETHER_TLS_MODE` | `off`              | `off` \| `behind-proxy`; unknown values pass through verbatim |

```bash
# Custom port and data dir for one boot:
godot --headless --path . -- --serve --port 9001 --data-dir /srv/together/data --max-rooms 32 --tls-mode behind-proxy

# Same tuning via env (this is what the compose file passes through):
TOGETHER_PORT=9001 TOGETHER_DATA_DIR=/srv/together/data \
  godot --headless --path . -- --serve

# Prove the parsing without binding a port:
godot --headless --path . -- --selftest config --port 9001 --data-dir /tmp/cfg --max-rooms 7
# CONFIG_OK port=1 data_dir=1 max_rooms=1
```

## Verify

```bash
# Health on the (possibly custom) port:
curl -s http://127.0.0.1:8080/   # {"ok":true,"version":"..."}

# Stack state and recent logs:
docker compose ps
docker compose logs -n 50 game
```

## systemd (legacy)

The systemd unit left the active path: deploys no longer install
Godot or a service on the VPS. `deploy/systemd/together.service` is
kept for reference only — it auto-starts on boot with
`Restart=always` and carries the same `TOGETHER_*` tuning now found in
`.env`/compose. Prefer the compose path above for every new install.
