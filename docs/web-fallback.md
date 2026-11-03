# Web fallback: serve the Godot web build from the VPS (issue #21)

The primary path is Cloudflare Pages: the `Web` export preset writes to
`web/index.html` and `web/_headers` carries the cross-origin isolation
headers next to it. Use this fallback when Pages cannot take the build —
notably its per-file size limit, which the ~80 MB first-load bundle can
exceed even though repeat (cached) loads target under 5 s.

Page/account/project creation on either host is operator work; this doc
covers only the server side.

## When to use the VPS

- The exported `.pck`/`.wasm` exceeds the Pages per-file size limit.
- You need response headers Pages cannot express.
- Otherwise stay on Pages — no maintenance, no TLS to manage.

## Layout

Copy the export output (`index.html`, `index.js`, `index.wasm`,
`index.pck`, plus the `.br`/`.gz` precompressed sidecars the export
produces and `loading.html`) to `/srv/together/web` on the VPS so the
directory contains an `index.html` at its root.

## Caddyfile

```caddy
together.example.com {
	root * /srv/together/web

	# Cross-origin isolation (needed if thread support is ever enabled)
	# plus hardening; caching is split per path below.
	header {
		Cross-Origin-Opener-Policy same-origin
		Cross-Origin-Embedder-Policy require-corp
		X-Content-Type-Options nosniff
	}

	# Hashed bundle assets are immutable; the entry page revalidates.
	@immutable {
		path *.js *.wasm *.pck
	}
	header @immutable Cache-Control "public, max-age=31536000, immutable"
	header /*index.html* Cache-Control "no-cache"

	encode zstd gzip
	file_server {
		precompressed br zstd gzip
	}
}
```

Notes:

- `encode zstd gzip` compresses on the fly when no sidecar exists;
  `file_server { precompressed br zstd gzip }` serves the export's
  precompressed `.br`/`.zst`/`.gz` sidecars first (checked in that
  order) with the right `Content-Encoding`.
- The single-threaded preset (`variant/thread_support=false`) runs fine
  without COOP/COEP, but the headers above keep the host ready for a
  threaded build later with no hosting change.

## Deploy / reload

```bash
# Validate then reload after editing the Caddyfile.
caddy fmt --overwrite /etc/caddy/Caddyfile
caddy reload --config /etc/caddy/Caddyfile
systemctl reload caddy
```

`caddy reload` applies the new config with zero downtime; `systemctl
reload caddy` is the equivalent when running under systemd.
