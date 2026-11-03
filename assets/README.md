# assets/ — Kenney CC0 placeholder

Art source of truth for recoloring: `docs/palette.md`.

- Candidate source: Kenney CC0 packs (https://kenney.nl). The exact set is
  TBD in the content lap.
- No binaries are committed in this lap (no `.png`, `.blend`, `.fbx`, ...).
- Rule: albedo recolors multiply toward palette hues; hand-built geometry
  uses exact palette hex values.

# assets/sfx/ — synthesized CC0 placeholder effects

- 8 files (`jump/flop/grab/throw/button/checkpoint/goal/coin.wav`), 44.1 kHz
  16-bit mono, generated in-repo by `tools/gen_sfx.py` (stdlib only, no
  downloads): CC0 by construction, no attribution required.
- Central bus: `autoload/Sfx.gd` (autoload `Sfx`), single entry point
  `play(<event>)`; lazy guarded loads keep missing files mute-safe.
- Default volume is low (`DEFAULT_VOLUME_DB = -12.0 dB`); one music track
  is deferred to a later lap.
