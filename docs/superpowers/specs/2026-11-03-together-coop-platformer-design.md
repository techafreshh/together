# Co-op Party Platformer ("Together"-like) — Design

Codename: **together** (working title; real name TBA).
Status: design approved pending — not yet approved by owner.
Date: 2026-11-03.

## Intent & why

A small co-op platformer in the spirit of Roblox's *Together [Party Game]*:
2–4 friends clear short obstacle stages that are impossible alone — they
must cooperate (hold buttons, boost jumps, carry each other) while goofy
ragdoll moments — flops, crashes, friend-catapults — turn every failure
into a shared laugh.

Built as a **fun project to play with a friend group** — not a commercial
push. Lean scope, polish where it counts (feel, comedy, instant access).

The defining product promise: **no install, no account, no setup.** A
friend gets a link, opens it in a desktop browser, plays. Everything else
in this design serves that promise.

## Goals

- G1. Online co-op for **2–4 players** in the same room, family-friendly.
- G2. **Stages that require teamwork** with a **shared moveset** —
  cooperation comes from position and timing (hold a button, see-saws,
  boost jumps, passing players across gaps), never from stronger/weaker
  character classes.
- G3. **Grab/carry other players, ragdoll flop on failure.** Walking uses
  a precise, responsive platformer controller — not perpetually floppy
  physics; ragdoll triggers on failure and big impacts. Failing is
  comedy, never punishment: fail → flop → instant self-respawn at your
  checkpoint while friends keep playing.
- G4. **Playable in the browser with zero install** (web export), plus a
  downloadable desktop build exported from the same project.
- G5. Dedicated game server hosted on the owner's **existing VPS**.
- G6. **Identity without accounts:** pick a display name, join with a
  short **room code**; progression saves on the server under that name.
- G7. **Progression loop:** finishing stages earns coins; coins buy
  cosmetic hats (and a few palette variants) in a wardrobe.
- G8. **Stage-by-stage flow:** main menu → create/join room → pick a
  world → play stage → results → next. Worlds are lists of stages.
- G9. Low-poly stylized 3D look built from **CC0 asset packs** (e.g.
  Kenney) recolored to one consistent palette.

## Non-goals

- No accounts, matchmaking, or play with strangers — rooms are private by
  obscurity through codes.
- No competitive modes, combat, or AI enemies. Cooperation only.
- No voice/text chat in-game (friends use Discord).
- No mobile/phone support. Desktop browsers only.
- No user-generated levels, level editor, or moderation tooling this
  version. (Group-forum-style level suggestions by hand remain possible.)
- No per-player passcodes/accounts; no email/crypto anything.

## Anti-goals (failure conditions, even if it "works")

- **Setup friction**: if joining a friend's session requires anything
  beyond "open link, type code", the product has failed.
- **Combat/platformer drift**: levels solvable solo, or roles that make
  one player a passenger, erode the reason this game exists.
- **Sluggish or desynced feel**, especially grabbing: comedy needs
  immediate, readable physics.

## Constraints

- **Engine: Godot 4.x** (latest stable). Owner's choice of engine.
- **Transport: WebSockets only.** Web export cannot use ENet/UDP; the
  dedicated server must use Godot's WebSocket multiplayer. The game page
  is HTTPS, so the socket must be `wss://` (TLS).
- First web load is a **~50–80 MB one-time download** (cached after).
- Web builds run **slower than native** (~2–4×). Target hardware is
  known: the friend group plays on **Windows with Chrome/Edge/Firefox** —
  the best-supported web path; budgets still aim at a modest 5-year-old
  laptop.
- Cloudflare Pages static hosting **per-file size limit (~25 MiB)** may
  reject a Godot wasm file; this must be verified at build time.
- Owner's VPS: a single Linux box, no special hardware; server runs as a
  systemd service.
- 1970s of server compute are unnecessary — physics for ≤4 ragdolls fits
  comfortably on a small VPS.

## Approaches considered

### Multiplayer topology
1. **Friend-hosts + VPS relay** (leanest to ship; session dies with the
   host's laptop; players' home connections carry game traffic).
2. **Dedicated headless Godot server on the VPS** ✅ — chosen. Sessions
   don't die with any player, everyone connects out to one stable
   endpoint, and the owner explicitly wants to use their VPS. Costs:
   server ops (systemd unit, redeploy-on-update) from day one.
3. Direct host/join with UPnP — rejected: fails behind most home
   routers; unacceptable for the no-friction goal.

### Distribution
1. **Web build hosted on Cloudflare Pages + desktop zip on itch.io
   (private page)** ✅ — chosen. Zero-install for friends; itch is free
   for the desktop fallback build.
2. Discord-only zips — rejected: no download page or changelog.
3. Web on the VPS itself (Caddy/nginx serving Godot static build + wss
   on one box) — kept as **fallback** if Cloudflare Pages' per-file limit
   blocks the wasm binary; actually the leaner single-host option.

### Teamwork model
1. **Shared abilities, cooperative geometry** ✅ — chosen (Together's
   own approach; every stage is a handshake, not a role assignment).
2. Asymmetric permanent roles/classes — rejected: richer puzzles, but
   multiplies design work per stage and can strand a 3-player group.
3. Shared base + temporary per-stage role pickups — deferred; a natural
   later extension once the base moveset works, not launch scope.

### Comedy/physics
1. **Full ragdoll + grab/carry** ✅ — chosen (owner wants maximum
   goofiness; grabbing other players is itself a puzzle verb).
2. Bouncy knockback only — rejected by owner (comedy-per-effort better,
   but loses grabbing; grabbing is load-bearing for level design).

### Player count
- 2–4 per room ✅ (over fixed-2: friend groups of 3–4 stay included;
  over 4–8: party-scale servers multiply netcode, physics and UI cost
  against a "repo for our friend group" goal).

### Camera/view & art
- Low-poly stylized 3D, third-person follow camera; CC0 packs (Kenney)
  recolored to one palette ✅. Hand-built geometry kept as a supplement
  for platforms/upper stages (CC0 kits alone can look "asset-flip").

### Session content shape
- Stage-by-stage menu with worlds ✅ (over a continuous open world:
  cheaper per stage; over random daily chains: loses designed
  difficulty ramp; may be added later as a "shuffle" button).

## Decided how (owner's calls, on the record)

| Decision | Owner's call |
|---|---|
| Who plays | 2–4 friends per room, online |
| Engine / view | Godot 4.x, low-poly stylized 3D |
| Where it runs | Browser (no install) + desktop build |
| Server | Dedicated headless Godot server on owner's Linux VPS |
| Hosting | Cloudflare Pages (web), itch private page (desktop zip) |
| Identity / privacy | Display names + room codes; no accounts |
| Teamwork style | Same moveset for everyone; stages force cooperation |
| Physics | Full ragdoll on failure; grab/carry other players |
| Session flow | Menu → room → world/stage select → play → results → next |
| Progression | Stage completion → coins → hats/cosmetics; saved server-side |
| Art source | CC0 low-poly packs, recolored to a single palette |
| Movement feel | Tight platformer control while alive; ragdoll flop on failure and big impacts |
| Fail rules | Fast individual respawn; a stage clears when **all** players reach the goal; whole-group resets only for stage-wide mechanics (timers) |
| Audience hardware | Windows laptops/desktops, Chrome/Edge/Firefox |
| Domain | Owner has a domain for the VPS (game page + `wss://` server) |
| Audio (my call) | Thin CC0 SFX layer (flops, boings, coins) + one music track |
| Join/leave (my call) | Joining works between stages (latecomers wait in lobby); stages must be beatable at 2, 3, and 4 players; below 2 players a stage restarts |
| Audience | The owner's friend group; fun first, lean scope |

## First-playable content (my proposal — correct me)

This is my scoping proposal, not an owner decision; trivially adjustable
before/during planning:

- **1 world, 8 stages** teaching the cooperation verbs one at a time and
  combining them at the end:
  1. Movement basics (solo-warmup inside a co-op corridor)
  2. Button-hold platforms
  3. Sequenced buttons (two plates, two doors)
  4. Boost jump (stand on a friend to launch)
  5. See-saw / counterweight
  6. Grab-and-pass across a gap
  7. Timed pair-lever finale (needs 2 of 4 plates held)
  8. Final gauntlet mixing 2–7
- **6–10 hats + 4 palette skins** in the wardrobe; coins per stage
  first-completion + small replay reward.
- **Rooms:** create → 4-character code; join by code; name + color pick;
  host controls stage selection; joining works between stages (late
  arrivals wait in the lobby until the next stage loads); stages are
  designed and verified beatable at 2, 3, and 4 players; a stage
  restarts if the room drops below 2 players mid-stage.
- **Persistence:** JSON per display name on the VPS (coins, owned items,
  per-stage best time/clear count). No auth — the VPS is for friends; a
  name collision/overwrite is accepted for v1.

## What's left to the builder (explicitly not decided here)

- Godot version pin; WebSocketMultiplayerPeer setup; server tick rate;
  physics authority model (server-sim with client prediction for own
  avatar, or lockstep — builder's call, comedy must stay responsive);
  interpolation.
- Grab/ragdoll implementation details on top of the tight base
  controller (real physics ragdoll vs. lightweight fake flop if the
  browser build proves too slow); grab/carry verb tuning.
- Stage/world data format and enumeration; checkpoint scheme.
- Actual asset pack choice and palette.
- Cloudflare Pages headers (COOP/COEP for SharedArrayBuffer) and the
  per-file-limit verification; **fallback path: serve the web build from
  the VPS next to the game server.**
- TLS termination for `wss://` on the owner's domain (Cloudflare proxy
  fronting the VPS, or Caddy + Let's Encrypt on the VPS).
- Deploy script + systemd unit for the headless server; update flow.
- Web export sizing budget (progressive loading if first load feels slow).
- In-HUD/level UI layout, results screen copy, wardrobe UI.

## Success (for this version)

A friend sends a link in Discord; three others are laughing inside a
stage within two minutes, nobody installs anything, nobody configures
anything; failing repeatedly is fun; finishing earns a hat; the group
comes back next week without the owner shepherding them in.
