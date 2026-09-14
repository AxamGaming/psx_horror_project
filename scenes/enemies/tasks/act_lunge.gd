@tool
class_name ActLunge
extends BTAction
## Charging dash: one burst toward the player's position at launch; contact
## deals lunge damage + heavy knockback. SUCCESS when the lunge window ends.
##
## ROUND 6: _exit() cancels an aborted lunge and charges the cooldown, so being
## interrupted mid-dash cannot leave _lunging stuck true (which would pin the
## model on the bite anim via the play_anim authority guard) and cannot be
## re-triggered for free.

var _started: bool = false


func _enter() -> void:
	_started = false


func _tick(_delta: float) -> Status:
	var cre: NightmareCreature = agent as NightmareCreature
	if cre == null:
		return FAILURE
	cre.set_task_tag(NightmareCreature.TaskTag.LUNGE)
	if not _started:
		cre.start_lunge()
		_started = true
		return RUNNING
	if not cre.lunge_done():
		return RUNNING
	return SUCCESS


func _exit() -> void:
	var cre: NightmareCreature = agent as NightmareCreature
	if cre != null and not cre.lunge_done():
		cre.cancel_lunge()
	_started = false
