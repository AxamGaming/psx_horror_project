@tool
class_name CondInSwipeRange
extends BTCondition
## Succeeds when the player is inside melee swipe range.

func _tick(_delta: float) -> Status:
	var cre: NightmareCreature = agent as NightmareCreature
	if cre == null:
		return FAILURE
	return SUCCESS if cre.dist_to_player() < cre.swipe_range else FAILURE
