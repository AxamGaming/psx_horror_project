@tool
class_name ActInvestigate
extends BTAction
## Go to the alert target (last known player position), then sweep two search
## points around it, then dwell-sniff and give up.
##
## Also uses awareness.last_known_pos() as a fallback target when has_alert()
## is true but the alert position is stale — ensures the creature always has
## a meaningful destination even when set_alert() debouncing holds back a
## re-stamp.

var _dwell: float = 0.0
var _total: float = 0.0
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
		# Prefer awareness memory (fresher) over debounced alert target.
		if cre.awareness != null and cre.awareness.has_memory():
			_target = cre.awareness.last_known_pos()
		else:
			_target = cre.get_alert_target()
		_has_target = true

	if cre.move_toward_point(_target, cre.run_speed * 0.75, 0.8):
		if _search_left > 0:
			_search_left -= 1
			_target = cre.search_point_near(cre.get_alert_target(), 3.0)
			_dwell = 0.0
			cre.play_gait(cre.run_speed * 0.75)
			return RUNNING
		# Reached all search points — dwell and sniff.
		cre.stop_move()
		cre.play_anim(cre.anim_battle_idle)
		cre.turn_slow(delta)
		_dwell += delta
		if _dwell > cre.investigate_dwell:
			cre.clear_alert()
			return SUCCESS
		return RUNNING

	_dwell = 0.0
	cre.play_gait(cre.run_speed * 0.75)
	return RUNNING
# NOTE: canonical file (a stale PascalCase duplicate actInvestigate.gd that called the removed get_memory() API was deleted in the R16 pass — on case-insensitive file systems the two used to collide).
