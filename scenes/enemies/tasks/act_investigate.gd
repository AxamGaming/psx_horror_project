@tool
class_name ActInvestigate
extends BTAction
## ROUND 16, reference state_searching: go to the last-known position, then sweep
## up to 2 walkable search points around it, then dwell (sniff sweep) and give up.
## R15 parked at one point and dwelt, which read as "standing there bugging out".

var _dwell: float = 0.0
var _total: float = 0.0      # ROUND 19: hard cap (reference search_time)
var _search_left: int = 2
var _target: Vector3 = Vector3.ZERO
var _has_target: bool = false


func _enter() -> void:
	_dwell = 0.0
	_total = 0.0
	_search_left = 2
	_has_target = false


func _tick(delta: float) -> Status:
	var cre: NightmareCreature = agent as NightmareCreature
	if cre == null or not cre.has_alert():
		return FAILURE
	cre.set_task_tag("ActInvestigate")
	_total += delta
	if _total > 25.0:
		cre.clear_alert()
		return SUCCESS
	if not _has_target:
		_target = cre.get_alert_target()
		_has_target = true
	if cre.move_toward_point(_target, cre.run_speed * 0.75, 0.8):
		if _search_left > 0:
			_search_left -= 1
			_target = cre.search_point_near(cre.get_alert_target(), 3.0)
			_dwell = 0.0   # <-- only reset here, on a new search point
			cre.play_gait(cre.run_speed * 0.75)
			return RUNNING
		cre.stop_move()
		cre.play_anim(cre.anim_battle_idle)
		cre.turn_slow(delta)
		_dwell += delta
		if _dwell > cre.investigate_dwell:
			cre.clear_alert()
			return SUCCESS
		return RUNNING
	# DO NOT reset _dwell here — traveling toward the dwell point shouldn't wipe it
	cre.play_gait(cre.run_speed * 0.75)
	return RUNNING
