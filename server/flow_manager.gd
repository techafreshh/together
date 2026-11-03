extends RefCounted
## Stage-to-stage party flow (issue #11): host-driven select/start, boot
## handoff, all-players-in-goal clear gate, and coin results.
##
## Pure synchronous flow state keyed by normalized room code: no sockets, no
## scene tree. The main-scene root (server/serve.gd) owns the `--selftest
## flow` branch; live socket broadcast stays out of scope. Coin values live
## here (first clear 100, replay trickle 10); persistence is the next issue.
## The goal gate mirrors stages/common/stage_base.gd: deduped roster, clear
## only when every roster member is inside (goal_all).

const ConfigScript := preload("res://autoload/Config.gd")

## Stage catalog: world 1, stages 1-8. Every stage ships the same two
## checkpoints; per-stage scenes and geometry stay out of scope.
const STAGE_IDS := ["w1s1", "w1s2", "w1s3", "w1s4", "w1s5", "w1s6", "w1s7", "w1s8"]
const STAGE_CHECKPOINTS := ["cp1", "cp2"]
## Coins awarded per clear inside the results dict (no wallets yet): first
## clear of a stage pays in full, later clears pay the replay trickle.
const FIRST_CLEAR_COINS := 100
const REPLAY_COINS := 10
## Proof shape the headless selftest relies on: stage w1s1, 2 peers.
const SELFTEST_STAGE := "w1s1"
const SELFTEST_PLAYERS := 2

var _flows: Dictionary = {}
var _clear_seq := 0


## True when stage_id names a catalog stage (w1s1..w1s8).
static func is_valid_stage(stage_id: Variant) -> bool:
	return STAGE_IDS.has(str(stage_id))


## Checkpoint ids for a catalog stage; empty for unknown stages.
static func checkpoints_for(stage_id: Variant) -> Array:
	if not is_valid_stage(stage_id):
		return []
	return STAGE_CHECKPOINTS.duplicate()


## Uppercases and trims caller input so flow calls accept lowercase room
## codes while stored keys stay canonical uppercase.
static func normalize_code(code: Variant) -> String:
	return str(code).strip_edges().to_upper()


func _ensure_flow(code: String) -> Dictionary:
	if not _flows.has(code):
		_flows[code] = {
			"code": code,
			"roster": [],
			"host_id": 0,
			"pending_stage": "",
			"active_stage": "",
			"stage_boot": {},
			"goals": [],
			"goal_all": false,
			"clears": {},
			"bests": {},
			"gen": 0,
			"built_gen": -1,
			"last_results": {},
		}
	return _flows[code]


## Records the room roster (join order) the boot spawn_map and the goal_all
## gate derive from; safe to re-call as membership changes.
func bind_room(code: Variant, player_ids: Array, host_id: int) -> Dictionary:
	var c := normalize_code(code)
	var flow := _ensure_flow(c)
	var roster: Array = []
	for pid in player_ids:
		var n := int(pid)
		if n > 0 and not roster.has(n):
			roster.append(n)
	flow["roster"] = roster
	flow["host_id"] = int(host_id)
	return {"ok": true, "code": c, "players": roster.size()}


## Host-only stage pick: unknown ids fail with unknown_stage, callers other
## than the host fail with host_only. Stores the pending stage for start_stage.
func select_stage(code: Variant, player_id: int, host_id: int, stage_id: Variant) -> Dictionary:
	var stage := str(stage_id)
	if not is_valid_stage(stage):
		return {"ok": false, "error": "unknown_stage"}
	if int(player_id) != int(host_id):
		return {"ok": false, "error": "host_only"}
	var c := normalize_code(code)
	var flow := _ensure_flow(c)
	flow["host_id"] = int(host_id)
	flow["pending_stage"] = stage
	return {"ok": true, "code": c, "stage_id": stage}


## Opens the pending stage: emits the stage_boot handoff {stage_id,
## checkpoints, spawn_map} and resets the goal roster for the new run.
## spawn_map assigns each roster player a slot 0..3, wrapping like
## stage_base.get_spawn_point.
func start_stage(code: Variant) -> Dictionary:
	var c := normalize_code(code)
	if not _flows.has(c):
		return {"ok": false, "error": "no_stage"}
	var flow: Dictionary = _flows[c]
	var stage := str(flow.get("pending_stage", ""))
	if stage == "":
		return {"ok": false, "error": "no_stage"}
	var roster: Array = flow.get("roster", [])
	var spawn_map := {}
	for i in range(roster.size()):
		spawn_map[int(roster[i])] = posmod(i, ConfigScript.MAX_ROOM_PLAYERS)
	var stage_boot := {
		"stage_id": stage,
		"checkpoints": checkpoints_for(stage),
		"spawn_map": spawn_map,
	}
	flow["active_stage"] = stage
	flow["pending_stage"] = ""
	flow["stage_boot"] = stage_boot
	flow["goals"] = []
	flow["goal_all"] = false
	flow["gen"] = int(flow.get("gen", 0)) + 1
	return {"ok": true, "code": c, "stage_boot": stage_boot}


## Records one player reaching the goal (deduped by player id, mirroring
## stage_base.notify_goal_entered); goal_all flips only once every roster
## member is inside. With no bound roster, two distinct goals complete.
func notify_goal(code: Variant, player_id: int) -> Dictionary:
	var c := normalize_code(code)
	var flow := _ensure_flow(c)
	var goals: Array = flow.get("goals", [])
	var pid := int(player_id)
	if not goals.has(pid):
		goals.append(pid)
	flow["goals"] = goals
	var roster: Array = flow.get("roster", [])
	if roster.is_empty():
		flow["goal_all"] = goals.size() >= ConfigScript.MIN_ROOM_PLAYERS
	else:
		var all_in := true
		for member in roster:
			if not goals.has(int(member)):
				all_in = false
				break
		flow["goal_all"] = all_in
	return {"ok": true, "code": c, "goal_count": goals.size(), "goal_all": bool(flow.get("goal_all", false))}


## Drops one player from the roster mid-stage (issue #12). When a stage is
## active and the survivors drop below Config.MIN_ROOM_PLAYERS the same
## stage re-boots for the survivors: fresh stage_boot, cleared goals,
## bumped generation. Otherwise the stage continues for the survivors.
func remove_player(code: Variant, player_id: int) -> Dictionary:
	var c := normalize_code(code)
	if not _flows.has(c):
		return {"ok": false, "error": "unknown_code"}
	var flow: Dictionary = _flows[c]
	var roster: Array = flow.get("roster", [])
	var pid := int(player_id)
	if not roster.has(pid):
		return {"ok": false, "error": "unknown_player"}
	roster.erase(pid)
	flow["roster"] = roster
	var goals: Array = flow.get("goals", [])
	if goals.has(pid):
		goals.erase(pid)
	flow["goals"] = goals
	if roster.is_empty():
		flow["goal_all"] = false
	else:
		var all_in := true
		for member in roster:
			if not goals.has(int(member)):
				all_in = false
				break
		flow["goal_all"] = all_in
	var n := roster.size()
	var active_stage := str(flow.get("active_stage", ""))
	if active_stage != "" and n < ConfigScript.MIN_ROOM_PLAYERS:
		var spawn_map := {}
		for i in range(roster.size()):
			spawn_map[int(roster[i])] = posmod(i, ConfigScript.MAX_ROOM_PLAYERS)
		var stage_boot := {
			"stage_id": active_stage,
			"checkpoints": checkpoints_for(active_stage),
			"spawn_map": spawn_map,
		}
		flow["stage_boot"] = stage_boot
		flow["goals"] = []
		flow["goal_all"] = false
		flow["gen"] = int(flow.get("gen", 0)) + 1
		return {"ok": true, "code": c, "restarted": true, "continued": false, "stage_boot": stage_boot, "players": n}
	return {"ok": true, "code": c, "restarted": false, "continued": true, "players": n}


## How many distinct roster players have reached the goal on the active run.
func goal_count(code: Variant) -> int:
	var c := normalize_code(code)
	if not _flows.has(c):
		return 0
	return ((_flows[c] as Dictionary).get("goals", []) as Array).size()


## True while every roster member stands in the goal.
func is_goal_all(code: Variant) -> bool:
	return goal_all(code)


## goal_all flag accessor for the clear gate.
func goal_all(code: Variant) -> bool:
	var c := normalize_code(code)
	if not _flows.has(c):
		return false
	return bool((_flows[c] as Dictionary).get("goal_all", false))


## Builds the results handoff {clears, bests, coins_awarded} for a cleared
## stage: the first clear per player per stage pays FIRST_CLEAR_COINS, later
## clears pay the REPLAY_COINS trickle. Requires the goal_all gate; repeat
## builds for the same run return the cached results without double counting.
func build_results(code: Variant) -> Dictionary:
	var c := normalize_code(code)
	if not _flows.has(c):
		return {"ok": false, "error": "no_stage"}
	var flow: Dictionary = _flows[c]
	var stage := str(flow.get("active_stage", ""))
	if stage == "":
		return {"ok": false, "error": "no_stage"}
	if not bool(flow.get("goal_all", false)):
		return {"ok": false, "error": "not_cleared"}
	if int(flow.get("built_gen", -1)) == int(flow.get("gen", 0)) and (flow.get("last_results", {}) as Dictionary).size() > 0:
		return {"ok": true, "code": c, "results": (flow.get("last_results", {}) as Dictionary).duplicate(true)}
	var clears: Dictionary = flow.get("clears", {})
	var bests: Dictionary = flow.get("bests", {})
	if not clears.has(stage):
		clears[stage] = {}
	var stage_clears: Dictionary = clears[stage]
	var coins_awarded := {}
	var goals: Array = flow.get("goals", [])
	for pid in goals:
		var key := str(int(pid))
		var prior := int(stage_clears.get(key, 0))
		stage_clears[key] = prior + 1
		coins_awarded[key] = FIRST_CLEAR_COINS if prior == 0 else REPLAY_COINS
	if not bests.has(stage):
		_clear_seq += 1
		bests[stage] = _clear_seq
	flow["clears"] = clears
	flow["bests"] = bests
	var results := {
		"clears": (clears as Dictionary).duplicate(true),
		"bests": bests.duplicate(true),
		"coins_awarded": coins_awarded,
	}
	flow["last_results"] = (results as Dictionary).duplicate(true)
	flow["built_gen"] = int(flow.get("gen", 0))
	return {"ok": true, "code": c, "results": results}


## Synchronous self-test: drives two virtual players through host-select ok,
## non-host-select rejected (host_only), boot shape, single-goal incomplete,
## dual-goal complete, and first-clear vs replay coin amounts. Returns
## [passed, failed]; never awaits, never touches the tree.
static func run_selftest() -> Array:
	var passed := 0
	var failed := 0
	seed(12345)
	var ManagerScript = load("res://server/flow_manager.gd")
	var mgr = ManagerScript.new()
	if STAGE_IDS.size() == 8 and STAGE_IDS[0] == "w1s1" and STAGE_IDS[7] == "w1s8" and is_valid_stage(SELFTEST_STAGE):
		passed += 1
	else:
		failed += 1
		push_error("flow selftest: catalog must be w1s1..w1s8")
	if FIRST_CLEAR_COINS == 100 and REPLAY_COINS == 10:
		passed += 1
	else:
		failed += 1
		push_error("flow selftest: coin values must be 100 first / 10 replay")
	var bound: Dictionary = mgr.bind_room("ABCD", [101, 102], 101)
	if bool(bound.get("ok", false)) and int(bound.get("players", 0)) == SELFTEST_PLAYERS:
		passed += 1
	else:
		failed += 1
		push_error("flow selftest: bind_room must stage %d players" % SELFTEST_PLAYERS)
	var picked: Dictionary = mgr.select_stage("ABCD", 101, 101, SELFTEST_STAGE)
	if bool(picked.get("ok", false)) and str(picked.get("stage_id", "")) == SELFTEST_STAGE:
		passed += 1
	else:
		failed += 1
		push_error("flow selftest: host select_stage must accept w1s1")
	var denied: Dictionary = mgr.select_stage("ABCD", 102, 101, "w1s2")
	if not bool(denied.get("ok", false)) and str(denied.get("error", "")) == "host_only":
		passed += 1
	else:
		failed += 1
		push_error("flow selftest: non-host select_stage must fail host_only")
	var unknown: Dictionary = mgr.select_stage("ABCD", 101, 101, "w9s9")
	if not bool(unknown.get("ok", false)) and str(unknown.get("error", "")) == "unknown_stage":
		passed += 1
	else:
		failed += 1
		push_error("flow selftest: unknown stage must fail unknown_stage")
	var started: Dictionary = mgr.start_stage("ABCD")
	var stage_boot: Dictionary = started.get("stage_boot", {})
	var boot_ok := bool(started.get("ok", false)) and str(stage_boot.get("stage_id", "")) == SELFTEST_STAGE
	boot_ok = boot_ok and (stage_boot.get("checkpoints", []) as Array) == ["cp1", "cp2"]
	boot_ok = boot_ok and ((stage_boot.get("spawn_map", {}) as Dictionary).size() == SELFTEST_PLAYERS)
	if boot_ok:
		passed += 1
	else:
		failed += 1
		push_error("flow selftest: stage_boot must carry stage_id, 2 checkpoints, spawn per player")
	mgr.notify_goal("ABCD", 101)
	if mgr.goal_count("ABCD") == 1 and not mgr.is_goal_all("ABCD") and not mgr.goal_all("ABCD"):
		passed += 1
	else:
		failed += 1
		push_error("flow selftest: one goal must be incomplete")
	mgr.notify_goal("ABCD", 101)
	if mgr.goal_count("ABCD") == 1:
		passed += 1
	else:
		failed += 1
		push_error("flow selftest: duplicate goal must not double-count")
	var early: Dictionary = mgr.build_results("ABCD")
	if not bool(early.get("ok", false)) and str(early.get("error", "")) == "not_cleared":
		passed += 1
	else:
		failed += 1
		push_error("flow selftest: results before goal_all must fail not_cleared")
	mgr.notify_goal("ABCD", 102)
	if mgr.is_goal_all("ABCD") and mgr.goal_all("ABCD"):
		passed += 1
	else:
		failed += 1
		push_error("flow selftest: both goals must complete goal_all")
	var built: Dictionary = mgr.build_results("ABCD")
	var results: Dictionary = built.get("results", {})
	var coins: Dictionary = results.get("coins_awarded", {})
	var first_ok := bool(built.get("ok", false)) and results.has("clears") and results.has("bests") and results.has("coins_awarded")
	first_ok = first_ok and int(coins.get("101", 0)) == FIRST_CLEAR_COINS and int(coins.get("102", 0)) == FIRST_CLEAR_COINS
	if first_ok:
		passed += 1
	else:
		failed += 1
		push_error("flow selftest: first clear must award %d per player" % FIRST_CLEAR_COINS)
	mgr.select_stage("ABCD", 101, 101, SELFTEST_STAGE)
	mgr.start_stage("ABCD")
	mgr.notify_goal("ABCD", 101)
	mgr.notify_goal("ABCD", 102)
	var replay: Dictionary = mgr.build_results("ABCD")
	var replay_results: Dictionary = replay.get("results", {})
	var replay_coins: Dictionary = replay_results.get("coins_awarded", {})
	var replay_clears: Dictionary = (replay_results.get("clears", {}) as Dictionary).get(SELFTEST_STAGE, {})
	var replay_ok := bool(replay.get("ok", false))
	replay_ok = replay_ok and int(replay_coins.get("101", 0)) == REPLAY_COINS and int(replay_coins.get("102", 0)) == REPLAY_COINS
	replay_ok = replay_ok and int(replay_clears.get("101", 0)) == 2 and int(replay_clears.get("102", 0)) == 2
	replay_ok = replay_ok and (replay_results.get("bests", {}) as Dictionary).has(SELFTEST_STAGE)
	if replay_ok:
		passed += 1
	else:
		failed += 1
		push_error("flow selftest: replay clear must award %d with clears at 2" % REPLAY_COINS)
	return [passed, failed]
