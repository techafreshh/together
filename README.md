# Together

Co-op party platformer on Godot 4.7: small squads clear eight World 1 co-op stages together from a headless server, in the browser or a Windows build.

> [!NOTE]
> The server is the product. The browser and Windows builds are thin clients over the headless server described below.

## Features

- 2–4 player co-op platformer: menu → lobby → stage → results flow.
- Eight World 1 stages (`w1s1`–`w1s8`) with 2/3/4-player scaling per `stages/world1/manifest.cfg`.
- Rooms lobby: host creates a room, guests join with a 4-letter code, host picks the stage and starts it.
- All-players-in-goal clear gate; first clear pays 100 coins, replays pay 10.
- Coins buy wardrobe: 8 hats and 4 palette skins, persisted per display name as one JSON file.
- Headless server: one port serves health `GET /` plus the `/ws` socket; the game socket defaults to `port + 1` (one above the serve port).
- Web build (single-threaded, static-host friendly) and a Windows desktop zip for friends blocked on browsers.

## Prerequisites

- Godot 4.7.x with `godot` on `PATH` (CI pins 4.7.2).
- Nothing else for the quickstart below.

## Quickstart

Docker path (nothing but Docker needed):

```sh
git clone https://github.com/techafreshh/together.git && cd together
docker compose up --build
```

Then connect to `ws://localhost:${PORT:-8080}/ws` (host port defaults
to `8080`; override with `PORT=9001 docker compose up --build`).

Native Godot path (needs `godot` on `PATH`):

```sh
git clone https://github.com/techafreshh/together.git && cd together
godot --headless --path . --import
godot --headless --path . -- --serve --port 8080
```

In a second terminal, verify the server:

```sh
curl -s http://127.0.0.1:8080/
# {"ok":true,"version":"0.1.0"}
```

> [!TIP]
> The game socket listens on `port + 1` (one above the serve port). If it is busy, the server logs a warning and keeps serving health only.

## Usage

Play a round (see `docs/join.md` for the 2-minute version):

1. Open the build and enter a display name — coins and wardrobe follow the name.
2. The host creates a room and reads out the 4-letter lobby code; guests join with that code.
3. The host picks a World 1 stage (start with `w1s1`) and presses Start.
4. Run to the glowing goal — the stage clears only when everybody is inside.

Controls (from `project.godot`): `WASD` or arrow keys to move, `Space` to jump.

Server behavior worth knowing:

- `GET /` returns health JSON (`{"ok": true, "version": "…"}`).
- The `/ws` upgrade answers `101` with a valid `Sec-WebSocket-Accept`, then a close frame; unknown routes return `404`, malformed requests return `400`. The server never returns `5xx`.
- Coins persist per display name in the data dir and survive restarts; rejoin with the same name to keep them.

## Configuration

Flags and env vars select the port, data dir, room cap, and TLS mode. Precedence is always flag > env > default; invalid values fall back silently and never fail boot.

| Flag | Env | Default | Notes |
|------|-----|---------|-------|
| `--port` | `TOGETHER_PORT` | `8080` | 1..65535; health + `/ws` port |
| `--net-port` | `TOGETHER_NET_PORT` | `port + 1` | game socket; health-only if busy |
| `--data-dir` | `TOGETHER_DATA_DIR` | `user://players` | JSON persistence directory |
| `--max-rooms` | `TOGETHER_MAX_ROOMS` | `64` | clamped 1..256 |
| `--tls-mode` | `TOGETHER_TLS_MODE` | `off` | `off` \| `behind-proxy`; unknown values pass through verbatim |

```sh
# Custom port and data dir for one boot:
godot --headless --path . -- --serve --port 9001 --data-dir /srv/together/data --max-rooms 32 --tls-mode behind-proxy

# Same tuning via env:
TOGETHER_PORT=9001 TOGETHER_DATA_DIR=/srv/together/data \
  godot --headless --path . -- --serve

# Prove the parsing without binding a port:
godot --headless --path . -- --selftest config --port 9001 --data-dir /tmp/cfg --max-rooms 7
# CONFIG_OK port=1 data_dir=1 max_rooms=1
```

> [!NOTE]
> `tls-mode` is recorded and passed through only. Real TLS termination stays operator work (Caddy or Cloudflare); see `docs/ops.md`.

## Builds and deploy

Web build (parse-level check, no export templates needed):

```sh
godot --headless --path . -- --export-check web
# EXPORT_WEB_OK preset=1 headers=1
```

The `Web` preset (`export_presets.cfg`) writes to `web/index.html`, single-threaded (`variant/thread_support=false`) so it runs on any static host. `web/_headers` ships COOP/COEP and immutable caching for hashed assets; `web/loading.html` shows the boot indicator (~80 MB first load, under 5 s cached). VPS fallback when Pages cannot take the bundle: `docs/web-fallback.md`.

Windows desktop build (needs the Windows export templates installed locally):

```sh
tools/build_desktop.sh
```

Exports the `Windows` preset to `build/windows/Together.exe`, stamps `Config.VERSION` into `build/windows/VERSION.txt`, and zips both to `dist/together-windows.zip`. Honors `$GODOT`. CI only runs the template-free parse check (`--selftest desktop_preset`).

Deploy the headless server as a compose stack (full operator guide:
`docs/ops.md` — the VPS needs nothing but Docker):

```sh
TOGETHER_HOST=vps.example.com ./deploy.sh server
docker compose up --build   # same stack locally
./deploy.sh --dry-run   # markers only, no network
```

The systemd unit (`deploy/systemd/together.service`) is legacy
reference only; compose is the supported deploy path.

## Project structure

- `server/` — headless multiplexer (`serve.gd`), game socket (`net_server.gd`), rooms, stage flow, persistence, wardrobe.
- `autoload/` — `Config.gd` (version, ports, CLI/env parsing), `Net.gd`, `Sfx.gd` (8 effects + loop music).
- `scenes/` — menu, lobby, wardrobe, HUD, results client screens.
- `stages/world1/` — the eight stage scenes plus `manifest.cfg`.
- `actors/` — player controller, ragdoll, grabber, props, cosmetics.
- `assets/` — hats, skins, music, sound effects.
- `web/` — Pages headers and loading indicator for the web build.
- `tools/` — desktop build script. `Dockerfile` + `docker-compose.yml` + `deploy.sh` — compose VPS deploy (`deploy/systemd/` is legacy reference).
- `docs/` — join guide, ops runbook, web fallback, palette. `tests/` — logic runners plus `smoke_serve.sh`.

## Limitations

- The web build's ~80 MB first download needs patience or a warm cache; repeat loads target under 5 s.
- TLS is pass-through (`off` | `behind-proxy`): terminate it in front of the server, not in it.
- Windows export templates must be installed locally; CI never runs the real export.
- Persistence is keyed by display name with no auth — names are not ownership.
- The `/ws` handshake completes with a close frame; live game frames arrive over the game socket on `port + 1`.
