extends Control
## Results screen (issue #19): coin totals, bests, next-stage vote.
##
## Thin Control scene fed by FlowManager.build_results ({clears, bests,
## coins_awarded}): show_results writes per-player coin totals into
## CoinsLabel and the clears/bests lines into ResultsBests. VoteBox buttons
## emit stage_voted; the vote itself rides the net lap.
## Net. autoload placeholder: Net.push_results broadcasts coins_awarded / Net.cast_vote sends stage_voted.

signal stage_voted(stage_id: String)
signal next_requested

var _last_vote := ""


## Contract nodes the serve selftest and the unit runner assert on.
static func required_nodes() -> Array:
	return ["CoinsLabel", "ResultsBests", "VoteBox", "VoteBox/VoteYes", "VoteBox/VoteNo", "NextButton"]


func _ready() -> void:
	var yes := get_node_or_null("VoteBox/VoteYes") as Button
	if yes != null:
		yes.grab_focus()
		if not yes.is_connected("pressed", _on_vote_yes):
			yes.connect("pressed", _on_vote_yes)
	var no := get_node_or_null("VoteBox/VoteNo") as Button
	if no != null and not no.is_connected("pressed", _on_vote_no):
		no.connect("pressed", _on_vote_no)
	var next := get_node_or_null("NextButton") as Button
	if next != null and not next.is_connected("pressed", _on_next_pressed):
		next.connect("pressed", _on_next_pressed)


## Writes coins_awarded per-player totals into CoinsLabel and the
## clears/bests records into ResultsBests. Unknown shapes clear without
## erroring.
func show_results(results: Dictionary) -> void:
	var coins_label := get_node_or_null("CoinsLabel") as Label
	var bests_label := get_node_or_null("ResultsBests") as Label
	var coins: Dictionary = results.get("coins_awarded", {}) as Dictionary
	var clears: Dictionary = results.get("clears", {}) as Dictionary
	var bests: Dictionary = results.get("bests", {}) as Dictionary
	if coins_label != null:
		if coins.is_empty():
			coins_label.text = ""
		else:
			var lines: Array = []
			var keys: Array = coins.keys()
			keys.sort()
			for k in keys:
				lines.append("P%s: %sc" % [str(k), str(coins[k])])
			coins_label.text = "\n".join(lines)
	if bests_label != null:
		var lines: Array = []
		var stages: Array = clears.keys()
		stages.sort()
		for stage_id in stages:
			var stage_clears: Dictionary = clears.get(stage_id, {}) as Dictionary
			var total := 0
			for pid in stage_clears.keys():
				total += int(stage_clears[pid])
			var best := str(bests.get(stage_id, "-"))
			lines.append("%s: clears=%d best=%s" % [str(stage_id), total, best])
		bests_label.text = "\n".join(lines)


## Last stage id voted for via the VoteBox; "" when no vote yet.
func last_vote() -> String:
	return _last_vote


func _on_vote_yes() -> void:
	_play_sfx("button")
	_last_vote = "next"
	stage_voted.emit(_last_vote)
	_net_vote(_last_vote)


func _on_vote_no() -> void:
	_play_sfx("button")
	_last_vote = "replay"
	stage_voted.emit(_last_vote)
	_net_vote(_last_vote)


func _on_next_pressed() -> void:
	_play_sfx("button")
	next_requested.emit()


## Guarded Net hook: vote through the Net autoload when present, silent
## otherwise so headless instantiation never errors.
func _net_vote(stage_id: String) -> void:
	if not is_inside_tree():
		return
	var net := get_node_or_null("/root/Net")
	if net != null and net.has_method("cast_vote"):
		net.call("cast_vote", stage_id)


## Guarded SFX hook: plays through the Sfx autoload when present, silent
## otherwise so scene instantiations without autoloads never error.
func _play_sfx(sfx_name: String) -> void:
	if not is_inside_tree():
		return
	var bus := get_node_or_null("/root/Sfx")
	if bus != null and bus.has_method("play"):
		bus.call("play", sfx_name)
