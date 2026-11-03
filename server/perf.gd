extends RefCounted
## 60fps native budget hooks (issue #20): pure-const stub plus a headless
## skip, shared by the `--selftest perf` serve branch and the unit runner.
##
## TARGET_FPS pins the frame budget; FRAME_BUDGET_MS is its millisecond
## allowance; check_budget answers whether one frame sample fits. Headless
## CI has no vsync or GPU timing, so the serve probe prints
## PERF_SKIPPED_HEADLESS=1 there and FPS_OK on real hardware. No scene
## tree is touched; run_selftest returns [passed, failed]; never awaits.

const TARGET_FPS := 60
const FRAME_BUDGET_MS := 1000.0 / 60.0


## True when there is no display server to time against (CI headless runs).
static func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


## True when one frame sample fits inside the 60fps budget.
static func check_budget(frame_ms: float) -> bool:
	return frame_ms <= FRAME_BUDGET_MS


## Synchronous budget self-test: consts sane, helper answers both sides,
## headless detection callable. Returns [passed, failed]; never awaits.
static func run_selftest() -> Array:
	var passed := 0
	var failed := 0
	if TARGET_FPS == 60:
		passed += 1
	else:
		failed += 1
		push_error("perf selftest: TARGET_FPS must be 60, got %d" % TARGET_FPS)
	if absf(FRAME_BUDGET_MS - 1000.0 / 60.0) < 0.0001:
		passed += 1
	else:
		failed += 1
		push_error("perf selftest: FRAME_BUDGET_MS must be 1000/60, got %f" % FRAME_BUDGET_MS)
	if FRAME_BUDGET_MS > 16.0 and FRAME_BUDGET_MS < 17.0:
		passed += 1
	else:
		failed += 1
		push_error("perf selftest: 60fps budget must sit near 16.67 ms")
	if check_budget(0.0) and check_budget(16.0) and check_budget(FRAME_BUDGET_MS):
		passed += 1
	else:
		failed += 1
		push_error("perf selftest: in-budget samples must pass")
	if not check_budget(FRAME_BUDGET_MS + 1.0) and not check_budget(100.0):
		passed += 1
	else:
		failed += 1
		push_error("perf selftest: over-budget samples must fail")
	if DisplayServer.get_name() != "":
		passed += 1
	else:
		failed += 1
		push_error("perf selftest: display server name must be readable")
	return [passed, failed]
