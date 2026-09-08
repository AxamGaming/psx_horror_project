@tool
class_name ActLunge
extends BTAction
## Charging dash: one burst toward the player's position at launch; contact
## deals lunge damage + heavy knockback. SUCCESS when the lunge window ends.

var _started: bool = false


func _enter() -> void:
	_started = false


func _tick(_delta: float) -> Status:
	var cre: NightmareCreature = agent as NightmareCreature
	if cre == null:
		return FAILURE
	if not _started:
		cre.start_lunge()
		_started = true
		return RUNNING
	if not cre.lunge_done():
		return RUNNING
	return SUCCESS
