@tool
class_name ActSwipe
extends BTAction
## Telegraphed melee: windup (attack anim + growl) for windup_time, then one
## swipe check (damage + knockback via the agent), then SUCCESS.
##
## ROUND 6: _exit() cancels an in-flight telegraph. The BTDynamicSequence /
## BTDynamicSelector above this task can abort() a RUNNING child when a
## higher-priority branch goes live (e.g. you neutralize it mid-swing). Without
## this, _winding stays true, the play_anim() authority guard freezes the model
## on attack_1, and the leftover _windup_t fires a phantom swipe after recover().
## The agent also clears these flags in take_damage()/recover(), so this is
## belt-and-braces rather than the only line of defence.

var _started: bool = false


func _enter() -> void:
	_started = false


func _tick(_delta: float) -> Status:
	var cre: NightmareCreature = agent as NightmareCreature
	if cre == null:
		return FAILURE
	cre.set_task_tag("ActSwipe")
	if not _started:
		cre.start_windup()
		_started = true
		return RUNNING
	if not cre.windup_done():
		return RUNNING
	cre.do_swipe()
	return SUCCESS


func _exit() -> void:
	var cre: NightmareCreature = agent as NightmareCreature
	if cre != null and cre.is_winding():
		cre.cancel_windup()
	_started = false
