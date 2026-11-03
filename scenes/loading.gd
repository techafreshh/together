extends Control
## Loading indicator (issue #20): thin progress overlay shown while stages
## and audio warm up.
##
## Progress API: set_progress(done, total) advances the bar, set_status
## names the current step, is_complete goes true once done reaches total,
## reset returns to the empty state. All node lookups are guarded so the
## script never errors when instantiated bare in unit tests.
## Net. autoload placeholder: Net.room_state drives future staged progress.


## Contract nodes the audiovisual unit runner asserts on.
static func required_nodes() -> Array:
	return ["StatusLabel", "LoadBar"]


func _ready() -> void:
	reset()


## Advances the bar; clamps done into 0..total and guards total <= 0.
func set_progress(done: int, total: int) -> void:
	var bar := get_node_or_null("LoadBar") as ProgressBar
	var safe_total := maxi(1, total)
	var safe_done := clampi(done, 0, safe_total)
	if bar != null:
		bar.max_value = safe_total
		bar.value = safe_done


## Names the current loading step on the status label.
func set_status(text: String) -> void:
	var label := get_node_or_null("StatusLabel") as Label
	if label != null:
		label.text = str(text)


## True once the bar has reached its maximum.
func is_complete() -> bool:
	var bar := get_node_or_null("LoadBar") as ProgressBar
	if bar == null:
		return false
	return bar.value >= bar.max_value


## Returns the indicator to the empty state.
func reset() -> void:
	var bar := get_node_or_null("LoadBar") as ProgressBar
	if bar != null:
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = 0.0
	set_status("Loading...")
