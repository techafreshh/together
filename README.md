# Together

Co-op party platformer on Godot 4.7. Browser build is the zero-friction
default; a private Windows zip covers friends whose browsers block the
web build.

## Run the server

```sh
godot --headless --path . -- --serve --port 8080
```

`GET /` returns health JSON, `/ws` is the game socket.

## Web build

```sh
godot --headless --path . -- --export-check web
```

## Desktop (Windows) build

One command, run from the repo root:

```sh
tools/build_desktop.sh
```

This exports the `Windows` preset to `build/windows/Together.exe`,
stamps `Config.VERSION` into `build/windows/VERSION.txt`, and zips both
to the private friend-group distributable `dist/together-windows.zip`.

Requires the Godot Windows export templates installed locally; CI only
runs the template-free parse check
(`godot --headless --path . -- --selftest desktop_preset`).
