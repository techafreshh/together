# Together palette (single source of truth)

Goal: one consistent palette across every stage, prop, and player cosmetic.
All Kenney CC0 art is recolored to these hues before it ships.

## Core swatches

| Name       | Hex       | Use                          |
|------------|-----------|------------------------------|
| Sky Wash   | `#77C7D9` | Sky / background wash        |
| Grass      | `#5FB75A` | Ground cover, safe surfaces  |
| Sandstone  | `#E3B76B` | Platforms, neutral structure |
| Terracotta | `#D95D39` | Hazards, accents, warm props |
| Deep Slate | `#22333B` | Outlines, text, dark detail  |
| Cream      | `#F2EDE3` | UI background, light detail  |
| Goal Gold  | `#FFB703` | Goals, coins, celebration    |

## Player colors (P1–P4)

| Player | Name  | Hex       |
|--------|-------|-----------|
| P1     | Coral | `#EF476F` |
| P2     | Blue  | `#118AB2` |
| P3     | Leaf  | `#06D6A0` |
| P4     | Grape | `#8338EC` |

## Wardrobe skins

| Skin     | Hex       |
|----------|-----------|
| Charcoal | `#2B2D42` |
| Mint     | `#B8F2E6` |
| Sunset   | `#FF9F1C` |
| Bubblegum| `#FF70A6` |

## Usage rules

- All values are sRGB hex, `Color(html)`-compatible in GDScript
  (e.g. `Color.html("#5FB75A")`).
- Hand-built geometry uses exact hex values from this doc — no eyeballed
  near-matches.
- Recoloring Kenney albedo textures: multiply toward the palette hue so
  shading detail survives while the hue matches.
- Player colors identify P1–P4 at a glance; never reuse them for stage
  geometry that must read as neutral.
