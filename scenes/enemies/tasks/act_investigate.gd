@tool
class_name ActInvestigate
extends BTAction
## Runs to the agent's alert target, dwells there sniffing around
## (investigate_dwell), then clears the alert and returns SUCCESS.

var _dwell: float = 0.0


func _enter() -> void:
	_dwell = 0.0


func _tick(delta: float) -> Status:
	var cre: NightmareCreature = agent as NightmareCreature
	if cre == null or not cre.has_alert():
		return FAILURE
	if not cre.move_toward_point(cre.get_alert_target(), cre.run_speed * 0.75):
		cre.play_anim(cre.anim_walk)
		_dwell = 0.0
		return RUNNING
	cre.stop_move()
	cre.play_anim(cre.anim_battle_idle)   # alert standing pose (idle = sit on this model)
	cre.turn_slow(delta)
	_dwell += delta
	if _dwell > cre.investigate_dwell:
		cre.clear_alert()
		return SUCCESS
	return RUNNING
