@tool
class_name ActSwipe
extends BTAction
## Telegraphed melee: windup (attack anim + growl) for windup_time, then one
## swipe check (damage + knockback via the agent), then SUCCESS.

var _started: bool = false


func _enter() -> void:
	_started = false


func _tick(_delta: float) -> Status:
	var cre: NightmareCreature = agent as NightmareCreature
	if cre == null:
		return FAILURE
	if not _started:
		cre.start_windup()
		_started = true
		return RUNNING
	if not cre.windup_done():
		return RUNNING
	cre.do_swipe()
	return SUCCESS
