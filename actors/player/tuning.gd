extends RefCounted
## Single tuning surface for the third-person platformer controller.
## Every feel value the controller and the headless self-test use lives
## here as a typed const; controller.gd only reads these, so stages can
## be verified against one set of numbers.

const move_speed: float = 6.0
const jump_velocity: float = 7.0
const gravity: float = 20.0
const fall_multiplier: float = 1.8
const coyote_ms: int = 100
const buffer_ms: int = 120
const air_control: float = 0.6
const jump_cut: float = 0.45
const max_fall_speed: float = 30.0
## Horizontal response rate (1/s): reaches top speed in ~0.08 s on ground.
const ground_response: float = 12.0


## Symmetric-arc air-time estimate in ms (rise gravity only), used for the
## CONTROLLER_OK report line. The live arc is slightly shorter because
## falling integrates gravity * fall_multiplier.
static func jump_arc_ms() -> int:
	return int(2.0 * jump_velocity / gravity * 1000.0)
