@tool
class_name CondSeesPlayer
extends BTCondition

var _see_t: float = 0.0
var _lock_t: float = 0.0

func _tick(delta: float) -> Status:
    var cre = agent as NightmareCreature
    if not cre:
        return FAILURE
    if cre.is_amnesiac():
        _see_t = 0.0
        _lock_t = 0.0
        return FAILURE
    var mem = cre.get_memory()
    if mem.is_visible:
        _see_t = min(cre.confirm_time + 0.5, _see_t + delta)
    else:
        _see_t = max(0.0, _see_t - delta)
        _lock_t = max(0.0, _lock_t - delta)
    if _see_t > cre.confirm_time:
        _lock_t = 3.0
        cre.note_combat_start()
        return SUCCESS
    if _lock_t > 0.0:
        return SUCCESS
    return FAILURE
