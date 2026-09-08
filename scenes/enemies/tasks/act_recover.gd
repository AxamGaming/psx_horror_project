@tool
class_name ActRecover
extends BTAction
## Waits out the neutralize window while the creature lies collapsed, then
## recovers it (full health, amnesiac) and returns SUCCESS.

var _t: float = 0.0


func _enter() -> void:
	_t = 0.0


func _tick(delta: float) -> Status:
	var cre: NightmareCreature = agent as NightmareCreature
	if cre == null:
		return FAILURE
	_t += delta
	if _t >= cre.neutralize_time:
		cre.recover()
		return SUCCESS
	return RUNNING
