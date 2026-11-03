# PRD: Together (working title)

**Status:** Draft — derives from [design doc](../../docs/superpowers/specs/2026-11-03-together-coop-platformer-design.md) (pending owner approval)
**Date:** 2026-11-03
**Owner:** techafresh

---

## 1. Executive Summary

**Together** is a low-poly 3D co-op party platformer for 2–4 friends, inspired by the Roblox game *Together [Party Game]*. Groups of players clear short obstacle stages that are impossible alone: holding buttons for each other, boosting friends' jumps, counterweighting see-saws, and carrying players across gaps. Movement is a precise, responsive platformer controller; failures trigger goofy ragdoll flops that respawn instantly — failing is the comedy, never the punishment.

The defining product promise is **zero-friction access**: a friend receives a link, opens it in a desktop browser (Chrome/Edge/Firefox on Windows), types a display name and a 4-character room code, and is playing within two minutes. No install, no account, no port forwarding. A downloadable desktop build is exported from the same project as a fallback.

Sessions run on a **headless Godot dedicated server** on the owner's existing VPS over WebSockets, so games don't die with any single player's laptop. Progression is lean and social: clearing stages earns coins, coins buy cosmetic hats and palette skins, and progress persists server-side under the player's display name. Built by the owner with AI-agent assistance as a fun project for a private friend group — deliberately out of the apps-store/streaming/platform economy.

**MVP goal:** one world of eight handmade teamwork stages, the grab/carry-ragdoll physics kit, room codes, and the coins→hats loop, playable in the browser by the owner's friend group.

---

## 2. Mission

**Mission statement:** Make it embarrassingly easy for a group of friends to end up laughing inside a teamwork platformer together — no installs, no accounts, no setup.

**Core principles:**

1. **Seconds to play.** Any step between "friend pasted the link" and "I am flopping off a platform" must justify its existence. Anti-goal condition: anything that requires setup beyond open-link-and-type-a-code.
2. **Cooperation is the game.** Every stage must be unsolvable solo and solvable by any subset of 2–4 players cooperating. No classes, no asymmetry that strands a party size.
3. **Failure is the fun.** Ragdoll flops, friend-catapults, and quick respawns mean failure costs seconds, not dignity. If a fail restarts the group or costs real progress, it is wrong.
4. **Lean scope, honest cuts.** Cut content (stage 8, wardrobe polish) before cutting feel, netcode, or access friction.
5. **The server is for friends, not adversaries.** No anti-cheat arms race, no accounts, no moderation machinery. Privacy-by-codes is enough for a private group.

---

## 3. Target Users

**Primary persona: The Friend** — a member of the owner's social circle, plays games casually with the group (Roblox, party games), is *not* technical: will not port-forward, compile, or create an account, and will not read a README. Plays on a Windows laptop or desktop in Chrome/Edge/Firefox, typically while in the group's Discord voice channel. Needs: instant access, controls that work on first contact, and a session that survives a friend's flaky connection.

**Secondary persona: The Owner** — technical, hosts and operates the VPS, distributes builds and links, plays all sessions. Needs: one-command deploys, a server that asked nothing of them mid-session, and cheap content updates (drop in a new stage, redeploy).

**Explicitly not users this version:** strangers, mobile players, macOS/Safari and Linux users (desktop build may incidentally work; not a target).

---

## 4. MVP Scope

### In Scope

**Core gameplay**
- [ ] Tight 3D platformer controller (run, jump, air control; tunable coyote time / jump buffering)
- [ ] Ragdoll flop on failure and big impacts; instant self-respawn at last checkpoint
- [ ] Grab/carry other players (grab, lift, carry, throw; works while alive)
- [ ] Cooperation prop kit: hold-buttons, sequenced buttons, boost pads/stands, see-saws, counterweights, timed levers, checkpoints, stage goal
- [ ] 8 handmade stages in 1 world, each verified beatable at 2, 3, and 4 players
- [ ] Stage flow: fail → individual quick respawn; stage clears when **all** players reach the goal

**Multiplayer**
- [ ] Headless dedicated Godot server (Linux VPS) speaking `wss://` (WebSocket multiplayer)
- [ ] Rooms: create → 4-char code; join by code; display name + color pick; 2–4 players
- [ ] Server-authoritative simulation; plays feel responsive on a normal home connection
- [ ] Join between stages (latecomers wait in lobby); room continues if a player disconnects; stage restarts if room drops below 2
- [ ] Host (room initiator) controls stage selection; group advances stage→stage without re-lobbying

**Progression & meta**
- [ ] Coins awarded on first stage completion (+ small replay reward)
- [ ] Wardrobe: 6–10 hats + 4 palette skins, purchasable in coins
- [ ] Server-side JSON persistence keyed by display name (coins, owned items, per-stage best clears/times)

**Presentation**
- [ ] Low-poly look from CC0 packs (e.g. Kenney) recolored to a single consistent palette
- [ ] Third-person follow camera
- [ ] Thin audio layer: CC0 SFX (flops, boings, coins, jingles) + one music track
- [ ] Menu → room → world/stage select → stage → results → next

**Deployment**
- [ ] CI workflow (GitHub Actions) running headless Godot checks (parse/import + smoke) on every PR
- [ ] Web export (Cloudflare Pages static hosting, cross-origin isolation headers) — *(page/account setup = operator, see checklist)*
- [ ] Desktop (Windows) export on a private itch.io page — *(page/account = operator)*
- [ ] ECS-free but scripted deploy: one command to build + upload server, systemd service on VPS — *(VPS hands-on = operator)*
- [ ] TLS for the game socket on the owner's domain (Caddy + Let's Encrypt or Cloudflare proxy) — *(DNS/domain = operator)*

### Out of Scope (deferred)

- [ ] Accounts, matchmaking with strangers, or any public-facing server
- [ ] Mobile/phone support; macOS/Safari and Linux as supported targets
- [ ] In-game voice/text chat (Discord covers it)
- [ ] Competitive modes, combat, AI enemies
- [ ] Level editor, user-generated stages, moderation tooling
- [ ] Asymmetric permanent roles; temporary per-stage role pickups (natural later extension)
- [ ] Second world; "shuffle" run mode; seasonal cosmetics
- [ ] Steam release

---

## 5. User Stories

1. **As a friend, I want to open a link, type my name and a room code, and immediately be in my buddies' game**, so that nobody has to "get the game working" before game night. *Concrete: Discord message → click → 90 seconds later I'm flopping off a platform with three friends.*
2. **As a player, I want a tight, predictable platforming controller**, so that teamwork stages are about timing with my friends rather than fighting floppy controls. *Concrete: I can consistently hit a 3-tile-wide ledge 10 times in a row; my jump arc feels the same every time.*
3. **As a player, I want to grab, carry, and throw my friends**, so that we can bridge gaps and boost each other — and laugh when we botch the handoff. *Concrete: two players ferry the third across a 12-tile gap by relay-carrying.*
4. **As a player, I want failures to be fast and funny** — flop, respawn, keep playing — so that retrying is always faster than complaining. *Concrete: from falling into the void to running again takes under 3 seconds.*
5. **As a group, we want a stage to complete only when everyone reaches the goal together**, so that nobody is ever left behind or racing against teammates. *Concrete: the last player's landing triggers the group celebration and coins.*
6. **As a returning player, I want coins for clearing stages and a wardrobe to spend them on hats**, so that progress feels like mine and gives next session a reason. *Concrete: I finish stage 5, buy the traffic-cone hat, and my friends see it on me in stage 6.*
7. **As the room host, I want to pick the next stage for the group**, so that the party flows without disbanding between stages. *Concrete: results screen → host picks next stage → every player loads in without leaving the room.*
8. **As the owner/developer, I want a one-command server deploy and a systemd service**, so that mid-session the game never depends on anyone's laptop and updates are a five-minute chore. *Concrete: `./deploy server` rebuilds the headless export, uploads, restarts the service; friends reconnect by re-entering the room code.* (Technical)

---

## 6. Core Architecture & Patterns

**Topology:** three roles — *web client* (browser, Godot web export), *desktop client* (Windows), *dedicated server* (headless Godot export on the VPS). Clients connect **out** to the server; server is authoritative for gameplay and persistence.

**Key technical pattern choices** (final details are builder's call per the design doc):

- **Transport:** Godot high-level multiplayer over `WebSocketMultiplayerPeer` (`wss://`). All high-level machinery — `@rpc` calls, `MultiplayerAuthority`, `MultiplayerSpawner`, `MultiplayerSynchronizer` — applies over WebSockets unchanged. *Note: the `godot-multiplayer` skill demonstrates ENet setup; substitute the WebSocket peer — everything above the transport is identical.*
- **Authority model:** server simulates physics and stage logic; clients send input state, render interpolated snapshots, and predict their own avatar's movement to mask latency. Grab/carry interactions are server-resolved (single authority prevents tug-of-war desync).
- **Stage representation:** every stage is a scene extending one shared scaffold (spawn points, checkpoints, kill plane, goal, prop instances, 2/3/4-player scaling config). Stages are data-over-structure where possible (which props, which gates) so authoring a new stage is composition, not coding.
- **Persistence:** server-side JSON files, one per player display name (coins, owned cosmetics, equipped cosmetic, per-stage best clear/time). No database.
- **Room model:** server hosts independent rooms (code 4 chars); room holds players, selected world/stage, in-progress run state. Cap on concurrent rooms is a config value.

**Godot project layout (target):**

```
together/
├── project.godot / export_presets.cfg
├── autoload/            # Net (client), Session (room state on server), Config
├── actors/
│   ├── player/          # controller, ragdoll rig, grabber, cosmetics attach points
│   └── props/           # button, seesaw, boost, lever, checkpoint, goal, killplane
├── stages/
│   ├── common/          # stage scaffold base scene
│   └── world1/          # stage_01 … stage_08
├── scenes/              # main_menu, rooms/lobby, wardrobe, results, hud
├── server/              # headless bootstrap, room manager, persistence service
├── assets/              # kenney packs (recolored), sfx/, music/
└── docs/superpowers/specs/
```

**Design patterns in play:** server-authoritative netcode with client prediction; data-driven stage composition; autoload singletons for cross-cutting services; scene-instanced prop kit (each scene = one behavior).

---

## 7. Tools/Features (detail)

**Player controller** — third-person, camera-relative movement, coyote time + jump buffering for forgiveness; small physics footprint (capsule) while alive. Tuning surfaces exposed in one place (jump arcs, air control, push strength).

**Ragdoll & flop** — physical body switch on lethal/hard impact events (not while walking); squash/stretch + impact SFX layered at the flop moment; auto-recover to controller at respawn. Fallback if web perf disappoints: scripted flop animation (builder's call, design doc).

**Grab/carry** — pick up a ragdolled *or* alive player within short range; carrier moves slower; throw applies fixed impulse modes. Server arbitrates who's holding whom; UI tells the carrier where their passenger is allowed to go (some stages gate carried players).

**Cooperation prop kit** — the eight-stage lineup teaches verbs in order: movement warmup → hold-button platforms → sequenced buttons → boost jump → see-saw/counterweight → grab-and-pass gap → timed pair-lever → finale remixing all. Each prop exposes simple signals (pressed/released/activated) consumed by stage logic, keeping stages declarative.

**Rooms & lobby UI** — create/join by code, name + color pick, player list with ready-badges, host stage picker with per-stage personal bests, wardrobe screen. Late joiners spectate the lobby until the next stage loads.

**Wardrobe progression** — first-clear coins per stage, replay trickle; hats (6–10) + palette skins (4) priced to be earnable in one full-world run; equipped cosmetic visible to all room members; persists server-side.

**Audio** — one music track in menu/stages, event SFX for flop, jump, grab, button press, checkpoint, goal, coin. All CC0.

---

## 8. Technology Stack

| Layer | Choice | Notes |
|---|---|---|
| Engine | Godot **4.7-stable**, pinned | Matches the factory's `factory-godot-r1` machine snapshot (Godot 4.7 + web export templates); GDScript only |
| Language | GDScript | Whole codebase; no GDExtension/C# |
| Netcode | Godot high-level multiplayer over `WebSocketMultiplayerPeer` | Server + browser-capable |
| Server host | Owner's Linux VPS, systemd service | Headless export of the same project |
| TLS | Caddy + Let's Encrypt on the VPS *or* Cloudflare proxy in front | Owner has a domain |
| Web hosting | Cloudflare Pages (free static), cross-origin isolation headers | Fallback: serve web build from VPS via Caddy |
| Desktop distribution | Private itch.io page (Windows zip) | Free |
| Art | Kenney CC0 low-poly packs + recolor | Hand-built geometry for gaps |
| Audio | CC0 SFX/music packs | Thin layer by design |
| Persistence | JSON files on VPS | No DB, no auth |

---

## 9. Security & Configuration

**Security scope (deliberately minimal, friends-only):**
- **In scope:** treat all client input as untrusted and validate/server-authoritize it; room codes as capacity control (random 4-char, collision-checked); TLS for the socket; basic join flood limiting (e.g. per-IP join attempt cooldown); no secrets in client builds.
- **Out of scope:** anti-cheat beyond sanity clamps (movement speed/teleport), account security, moderation, DDoS hardening beyond what the VPS/CDN gives, encryption of save files.

**Configuration management:** server reads config at boot via CLI flags or env vars — listen port, TLS mode (terminated locally vs. behind proxy), data directory for saves, max rooms, max players per room. Client build bakes in the server URL; no user-facing config.

**Identity & privacy:** display name + room code only. Name collisions share/overwrite a save (accepted for v1). No personal data collected; server logs stay minimal (connections, room events, errors).

---

## 10. API Specification (multiplayer protocol sketch)

Not REST — a session protocol over the WebSocket multiplayer connection. Message *families* (exact channel/RPC naming is the builder's):

**Server contract (pinned — the factory's acceptance scenarios test exactly this):**
The headless dedicated server boots as a single foreground command:
`godot --headless --path . -- --serve --port $PORT`
and serves, on that one port:
- `GET /` → **200** with JSON health (at least `{"ok": true}` + a version field) — plain HTTP, no upgrade;
- WebSocket upgrade on **`/ws`** → the game socket (all protocol messages above flow here);
- anything else → 4xx, never 500.

The walking-skeleton issue delivers exactly this contract.

| Direction | Message | Payload (sketch) |
|---|---|---|
| C→S | `join_room` | `{code, name, cosmetic_hash}` → ack/deny |
| S→C | `room_state` | `{players[], host_id, world, current_screen, stage_id?}` (broadcast on change) |
| C→S | `select_stage` | `{stage_id}` (host only, lobby screen) |
| C→S | `ready_vote` / `start_stage` | host-initiated stage load |
| S→C | `stage_boot` | `{stage_id, checkpoints[], spawn_map, prop_states[]}` |
| C→S | `input_state` | `{move_vec, jump, grab, snapshot_tick}` (rate-limited, e.g. 20–30 Hz) |
| S→C | `snapshots` | per-player transforms + prop states (interpolated on client) |
| S→C | `game_event` | `{type: grabbed\|thrown\|flopped\|checkpoint\|goal_all\|coin, player, at}` |
| C→S | `leave_room` | — |
| S→C | `results` | `{clears[], bests[], coins_awarded[]}` |

**Persistence file sketch (per player name):** `{"coins": 240, "owned": ["hat_cone","skin_charcoal"], "equipped": {"head": "hat_cone"}, "stages": {"w1s5": {"clears": 3, "best_ms": 74210}}}`

**No HTTP API is exposed by the game server.** The only web-served assets are the static game files (Pages/VPS) — the socket is the sole runtime endpoint.

---

## 11. Success Criteria

**MVP success = the two-minute test, repeatedly:** a friend who has never seen the game goes from Discord link to laughing inside a stage within two minutes, three times out of three, without the owner helping.

- [ ] Join-to-gameplay ≤ 2 minutes on Windows Chrome/Edge/Firefox, first visit and cached
- [ ] All 8 stages beatable and verified at 2, 3, and 4 players
- [ ] Stages 1–5 unsolvable solo (verified)
- [ ] Controller: consistent, tunable, no input fighting; grab/carry reads as instant (no visible desync tug-of-war)
- [ ] Fail → respawn < 3 s; flops trigger audio/visual comedy feedback
- [ ] Session survives one player disconnecting (room continues); stage restarts below 2 players
- [ ] Late join between stages works; mid-stage joiners wait in lobby
- [ ] Persistence: coins/hats/bests survive server restart and client cache-clear
- [ ] Performance: 60 FPS native on a 5-year-old Windows laptop; ≥ 30 FPS in web export on same
- [ ] Web first-load ≤ ~80 MB with a loading indicator; cached loads are instant-enough (< 5 s)
- [ ] Server ops: `./deploy` does build→upload→restart in one step; service auto-starts on boot

**Quality indicators:** flops get audibly laughed at in playtests; players voluntarily try to throw each other; nobody asks "how do I join?" twice.

---

## 12. Implementation Phases

**Phase 1 — Core feel (single-player vertical slice)**
Goal: prove the game is fun alone before it is fun together.
- [ ] Project scaffold, repo hygiene, palette + first Kenney assets imported
- [ ] Tight controller + follow camera + tunable jump feel
- [ ] Ragdoll flop on failure + instant respawn; grab/carry against dummy players (AI-less test mannequins)
- [ ] Prop kit v1 (button, boost, see-saw, checkpoint, goal) in a test stage
- [ ] Thin SFX layer on every interaction
**Validation:** 60 FPS native on the reference laptop; a non-friend playtester flops, laughs, and retries unprompted; *web-export spike of this slice on Pages to de-risk size/isolation/perf early*.

**Phase 2 — Multiplayer spine**
Goal: 2–4 real clients in one stage through the real server.
- [ ] `WebSocketMultiplayerPeer` server + client net stack; server-authoritative sim + own-avatar prediction
- [ ] Rooms (codes), lobby, names/colors; join-between-stages; disconnect handling
- [ ] Individual respawn + all-at-goal completion rules; grab/carry server arbitration
- [ ] Local CI-style headless test for netcode sanity (`godot-gdscript-headless-testing` patterns)
**Validation:** two browser clients + one desktop client join one VPS-hosted room; no grab desync in a 10-minute fuzz session; one client hard-killed mid-stage and the room continued.

**Phase 3 — Content, progression, polish**
Goal: the game the friends will recognize.
- [ ] 8 stages in World 1, each verified at 2/3/4 players
- [ ] Coins, wardrobe (6–10 hats, 4 skins), results screen, personal bests
- [ ] Server-side persistence + name-based saves
- [ ] Music track + full SFX set; recolor pass for visual cohesion
**Validation:** full world run at 2/3/4 players with persistence across restart; every stage unsolvable-solo check; hats visible on all clients.

**Phase 4 — Ship to friends (release engineering)**
Goal: the two-minute test passes for real friends.
- [ ] Web export on Cloudflare Pages (headers, size, caching) — or VPS fallback if the 25 MiB/file limit blocks
- [ ] Desktop Windows export on private itch page
- [ ] TLS on the domain; systemd deploy script; server monitoring-lite (logs)
- [ ] Small friends & family playtest; fix the top friction points found
**Validation:** three separate friend groups-of-2–4 all pass the two-minute test; owner runs one deploy mid-conversation without anyone noticing.

---

## 13. Future Considerations

- World 2+ and a community-suggestion pipeline (the *Together* tradition: read every suggestion)
- "Shuffle" run mode (random stage chain) and daily seeds
- Temporary per-stage roles (grabber/glider style pickups) on top of the shared moveset
- Optional tiny account-less friend list ("remember my name + last room")
- Public web landing page; Steam if the game unexpectedly outgrows the friend group
- Fake-flop → full-physics ragdoll upgrade path if native-only performance allows

---

## 14. Risks & Mitigations

| # | Risk | Mitigation |
|---|---|---|
| 1 | **Cloudflare Pages ~25 MiB/file limit rejects Godot's wasm binary** — the web-first pillar depends on this host | Phase 1 web spike decides early; fallback documented: serve the web build from the VPS via Caddy (same box as the game server, arguably leaner). Precompressed `.br`/`.gz` and engine flags reduce wasm size further |
| 2 | **Web-export performance with 4 physical players** threatens the "5-year-old laptop ≥ 30 FPS" bar | Low-poly budgets are a hard constraint from day one; ragdoll is event-triggered, not perpetual; fake-flop fallback exists; profile the exported web build in Phase 1, not at the end |
| 3 | **Grab/carry netcode feel** — server arbitration can read as laggy tug-of-war and kill the comedy | Server-authoritative with client prediction for own avatar; grab resolution is discrete (who-holds-whom), carrying is positionally forgiving; Phase 2 fuzz test explicitly measures desync |
| 4 | **Level-design unknowns**: stages trivializied by 4-player stacking, or impossible at 2 | Every stage verified at 2/3/4 as an exit criterion; shared prop scaffold keeps iteration cheap; solo-solvability check for stages 1–5 |
| 5 | **Server ops drift** (manual deploys rot, friends hit a stale/broken server) | One-command deploy + systemd from Phase 2; the design treats "owner updates mid-conversation invisibly" as a success criterion |

---

## 15. Appendix

### Operator checklist (NOT buildable issues — laps cannot do these; kept here so the slicer never turns them into GitHub issues)

1. Create the itch.io private page and upload the desktop zip lap artifact.
2. Create the Cloudflare Pages project pointing at the repo's web-export artifact; set COOP/COEP headers; connect the domain DNS.
3. Issuing/configuring TLS on the VPS (Caddy + Let's Encrypt, or Cloudflare proxy) for `wss://`.
4. Install and start the systemd service for the platform's release artifact (hands-on VPS step); run the one-command deploy script thereafter.
5. Share the production link + invite friends; Discord playtest coordination.

### Repo facts

- **Source design doc:** `docs/superpowers/specs/2026-11-03-together-coop-platformer-design.md` (contains the approaches considered and the owner's on-the-record decisions; this PRD inherits them)
- **Installed gamedev skills** (project-local, `.agents/skills/`): Tier 1 — godot-multiplayer, godot-physics, physics-tuning, godot-3d-essentials, game-feel, godot-export, godot-gdscript-headless-testing; Tier 2 — level-design, platformer, godot-ui-control, camera-systems, godot-audio, save-systems, itch-publish, performance-optimization, godot-shaders
- **Key external references:** Roblox *Together [Party Game]* (genre reference), Kenney.nl (CC0 packs), Godot docs: WebSocket multiplayer, web export / cross-origin isolation
- **Repo:** `/home/techafresh/projects/together` (git; no remote yet)
