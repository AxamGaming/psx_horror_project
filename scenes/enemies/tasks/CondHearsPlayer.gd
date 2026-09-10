@tool
class_name CondHearsPlayer
extends BTCondition

func _tick(_delta: float) -> Status:
    var cre = agent as NightmareCreature
    if not cre:
        return FAILURE
    if cre.is_amnesiac():
        return FAILURE
    var mem = cre.get_memory()
    return SUCCESS if mem.has_recent_hearing(1.0) else FAILURE
