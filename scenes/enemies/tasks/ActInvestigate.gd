@tool
class_name ActInvestigate
extends BTAction

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
    var cre = agent as NightmareCreature
    if not cre:
        return FAILURE
    cre.set_task_tag("ActInvestigate")
    var mem = cre.get_memory()
    if mem.is_visible:
        return FAILURE
    var alert_pos = cre.get_alert_target()
    if alert_pos == Vector3.ZERO:
        return FAILURE
    if not _has_target:
        _target = alert_pos
        _has_target = true
        _search_left = 2
    var arrived = cre.move_toward_point(_target, cre.walk_speed, 0.7)
    if arrived:
        _dwell += delta
        _total += delta
        if _dwell > 1.0 and _search_left > 0:
            var new_target = cre.search_point_near(_target, 3.0)
            if new_target != _target:
                _target = new_target
                _search_left -= 1
                _dwell = 0.0
        if _total > cre.investigate_dwell:
            cre.clear_alert()
            return SUCCESS
        cre.turn_slow(delta)
    else:
        cre.play_gait(cre.walk_speed)
    return RUNNING

func _exit() -> void:
    var cre = agent as NightmareCreature
    if cre:
        cre.stop_move()
