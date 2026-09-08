@tool
class_name CondNeutralized
extends BTCondition
## Succeeds while the creature is down (health depleted). The recover action
## runs under this condition.

func _tick(_delta: float) -> Status:
	var cre: NightmareCreature = agent as NightmareCreature
	if cre == null:
		return FAILURE
	return SUCCESS if cre.is_neutralized() else FAILURE
