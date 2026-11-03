# assets/ — Kenney CC0 placeholder

Art source of truth for recoloring: `docs/palette.md`.

- Candidate source: Kenney CC0 packs (https://kenney.nl). The exact set is
  TBD in the content lap.
- No binaries are committed in this lap (no `.png`, `.blend`, `.fbx`, ...).
- Rule: albedo recolors multiply toward palette hues; hand-built geometry
  uses exact palette hex values.
- Recolor rule (issue #20): every material listed in `assets/recolor.json`
  carries the exact sRGB float of its palette hex (translucent materials
  keep their alpha). The per-material mapping lives in that JSON file so a
  file scan under `assets/` proves the palette references.

## Palette hex table (mirrors `docs/palette.md`)

| Name       | Hex       |
|------------|-----------|
| Sky Wash   | `#77C7D9` |
| Grass      | `#5FB75A` |
| Sandstone  | `#E3B76B` |
| Terracotta | `#D95D39` |
| Deep Slate | `#22333B` |
| Cream      | `#F2EDE3` |
| Goal Gold  | `#FFB703` |
| P1 Coral   | `#EF476F` |
| P2 Blue    | `#118AB2` |
| P3 Leaf    | `#06D6A0` |
| P4 Grape   | `#8338EC` |
| Charcoal   | `#2B2D42` |
| Mint       | `#B8F2E6` |
| Sunset     | `#FF9F1C` |
| Bubblegum  | `#FF70A6` |

# assets/music/ — CC0 looping track

- 1 file (`loop.ogg`, 40 s, 22050 Hz mono, ~48 kbit/s, < 300 KB web
  budget), synthesized in-repo by `tools/gen_music.py` (stdlib only, no
  downloads): CC0 by construction, no attribution required.
- Player: `autoload/Sfx.gd` (autoload `Sfx`), `play_music()` /
  `stop_music()` on a dedicated looping `AudioStreamPlayer` at
  `MUSIC_VOLUME_DB = -14.0 dB`; `stop_music()` plus `set_muted(true)` keep
  it silent. Music lives in separate `MUSIC_*` consts; the 8-file SFX set
  is untouched.

# assets/sfx/ — synthesized CC0 placeholder effects

- 8 files (`jump/flop/grab/throw/button/checkpoint/goal/coin.wav`, 44.1 kHz
  16-bit mono, generated in-repo by `tools/gen_sfx.py` (stdlib only, no
  downloads): CC0 by construction, no attribution required.
- Central bus: `autoload/Sfx.gd` (autoload `Sfx`), single entry point
  `play(<event>)`; lazy guarded loads keep missing files mute-safe.
- Default volume is low (`DEFAULT_VOLUME_DB = -12.0 dB`); the looping music
  track lives in `assets/music/loop.ogg` (see above).
