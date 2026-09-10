@tool
class_name CondHearsPlayer
extends BTCondition
## Queries CreatureAwareness.heard(). Amnesiac check lives in awareness.tick().

func _tick(_delta: float) -> Status:
	var cre: NightmareCreature = agent as NightmareCreature
	if cre == null:
		return FAILURE
	if cre.awareness == null:
		return FAILURE
	return SUCCESS if cre.awareness.heard() else FAILURE
