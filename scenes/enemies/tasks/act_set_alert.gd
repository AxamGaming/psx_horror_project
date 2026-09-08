@tool
class_name ActSetAlert
extends BTAction
## Stores the player's current position as the agent's investigation target.

func _tick(_delta: float) -> Status:
	var cre: NightmareCreature = agent as NightmareCreature
	if cre == null:
		return FAILURE
	cre.set_alert(cre.player_pos())
	return SUCCESS
