@tool
class_name CondCanLunge
extends BTCondition
## Succeeds when a lunge is possible: mid-range window, cooldown ready,
## player confirmed visually.

func _tick(_delta: float) -> Status:
	var cre: NightmareCreature = agent as NightmareCreature
	if cre == null:
		return FAILURE
	var d: float = cre.dist_to_player()
	if d < cre.lunge_min or d > cre.lunge_max:
		return FAILURE
	if not cre.lunge_ready():
		return FAILURE
	return SUCCESS if cre.sees_player() else FAILURE
