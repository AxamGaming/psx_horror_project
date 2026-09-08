@tool
class_name CondHearsPlayer
extends BTCondition
## Succeeds while the player's noise (sprint/walk/crouch) is inside the
## creature's hearing radius.

func _tick(_delta: float) -> Status:
	var cre: NightmareCreature = agent as NightmareCreature
	if cre == null:
		return FAILURE
	return SUCCESS if cre.hears_player() else FAILURE
