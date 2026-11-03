#!/usr/bin/env bash
# Windows desktop build (issue #22): downloadable fallback for friends
# blocked on browsers. Exports the "Windows" preset exe, stamps
# Config.VERSION into VERSION.txt, and zips both to the private
# distributable dist/together-windows.zip.
# Usage: tools/build_desktop.sh (run from anywhere; honors $GODOT).
# Requires the Windows export templates locally; CI never runs this
# (it only runs the parse-level -- --selftest desktop_preset probe).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-godot}"

EXE="build/windows/Together.exe"
STAMP="build/windows/VERSION.txt"
ZIP="dist/together-windows.zip"

cd "$ROOT"
mkdir -p "$(dirname "$EXE")" dist

"$GODOT" --headless --path "$ROOT" --export-release "Windows" "$EXE"

VERSION="$(sed -n 's/^const VERSION: String = "\(.*\)"/\1/p' autoload/Config.gd | head -n 1)"
VERSION="${VERSION:-0.0.0}"
printf '%s\n' "$VERSION" > "$STAMP"

rm -f "$ZIP"
zip -r "$ZIP" "$EXE" "$STAMP"
echo "desktop zip ok: $ZIP (version $VERSION)"
