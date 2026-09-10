@tool
class_name CondHasAlert
extends BTCondition

func _tick(_delta: float) -> Status:
    var cre = agent as NightmareCreature
    if not cre:
        return FAILURE
    return SUCCESS if cre.has_alert() else FAILURE
