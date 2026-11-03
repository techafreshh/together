# Ops: deploy the headless server (issue #23)

One command ships the headless server, a systemd unit keeps it alive
across reboots, and flags/env select port, data dir, room cap, and TLS
mode. The normal update is a five-minute, laptop-free
`./deploy.sh server` — build, upload, restart — with no mid-session
dependence.

## What this covers

- `deploy.sh`: builds a source tarball (`godot --headless --import` +
  `git archive`), uploads it with scp, and restarts the service over ssh.
- `deploy/systemd/together.service`: the systemd unit (auto-start on
  boot, `Restart=always`).
- Server flags/env for `--port`, `--data-dir`, `--max-rooms`,
  `--tls-mode`.

## Operator prerequisites (out of scope here)

VPS hands-on install, DNS records, and TLS certificate issuance are
operator work; this doc only ships the script, the unit, and the flags.

- A VPS you can ssh into, with Godot installed at
  `/usr/local/bin/godot` (or point `TOGETHER_GODOT` elsewhere).
- A `together` user on the VPS owning `/srv/together/source` and
  `/srv/together/data`.
- DNS pointing at the VPS and a TLS certificate if you terminate TLS
  yourself — the server's `tls-mode` is recorded/passed through only
  (`off` | `behind-proxy`); real termination stays with Caddy or
  Cloudflare.

## The `./deploy server` name

Older runbooks call the update `./deploy server`; that is this same
script. The checked-in name is `deploy.sh` because the `deploy/`
directory already holds the systemd unit, so run `./deploy.sh server`.

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

# Same tuning via env (this is what the systemd unit uses):
TOGETHER_PORT=9001 TOGETHER_DATA_DIR=/srv/together/data \
  godot --headless --path . -- --serve

# Prove the parsing without binding a port:
godot --headless --path . -- --selftest config --port 9001 --data-dir /tmp/cfg --max-rooms 7
# CONFIG_OK port=1 data_dir=1 max_rooms=1
```

## Update flow

```bash
# Ship everything (build + upload + restart):
TOGETHER_HOST=vps.example.com ./deploy.sh server

# Or step by step:
TOGETHER_HOST=vps.example.com ./deploy.sh build    # prints BUILD_OK
TOGETHER_HOST=vps.example.com ./deploy.sh upload   # prints UPLOAD_OK
TOGETHER_HOST=vps.example.com ./deploy.sh restart  # prints RESTART_OK
```

`server` runs the same boot the CI smoke test uses —
`godot --headless --path /srv/together/source -- --serve` — so what you
ship is what CI proved. Without `TOGETHER_HOST` a real run exits 2 and
changes nothing.

```bash
# Dry run: markers only, no network, no godot, no disk writes outside /tmp:
./deploy.sh --dry-run
# DRY_RUN_OK, BUILD_OK, UPLOAD_OK, RESTART_OK (exit 0)
```

Rollback is the previous tarball: re-run `./deploy.sh upload` from the
older commit (or re-extract your backup of `/srv/together/source` on
the VPS) and restart.

## systemd install

```bash
# On the VPS, one time:
sudo install -m 644 deploy/systemd/together.service /etc/systemd/system/together.service
sudo systemctl daemon-reload
sudo systemctl enable --now together

# Local overrides without editing the unit (wins over Environment= lines):
sudo systemctl edit together
#   [Service]
#   Environment=TOGETHER_PORT=9001
sudo systemctl restart together
```

The unit runs `User=together` from `/srv/together/source`,
`ExecStart=/usr/local/bin/godot --headless --path
/srv/together/source -- --serve` with the port/data-dir/room-cap/TLS
tuning supplied via `Environment=` lines, and `Restart=always` with
`RestartSec=5` so a crash or a reboot comes back on its own.

## Verify

```bash
# Health on the (possibly custom) port:
curl -s http://127.0.0.1:8080/   # {"ok":true,"version":"..."}

# Service state and recent logs:
systemctl is-active together
journalctl -u together -n 50
```
