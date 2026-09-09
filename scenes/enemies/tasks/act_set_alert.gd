@tool
class_name ActSetAlert
extends BTAction
## Stores the player's current position as the agent's investigation target.
##
## ROUND 10: returns FAILURE on purpose. This is a SIDE-EFFECT node, not a
## behaviour. While it returned SUCCESS, seq_hear succeeded on every audible
## tick and the root BTDynamicSelector stopped there -- ActInvestigate and
## ActPatrol could never run, and since no movement task ran at all, `velocity`
## was never touched: the creature slid along its last heading for up to 50 s
## (creature_log R9: 66 samples tagged ActSetAlert, walking, navr=0). Returning
## FAILURE lets the selector fall through to investigate/patrol in the same tick.

func _tick(_delta: float) -> Status:
	var cre: NightmareCreature = agent as NightmareCreature
	if cre == null:
		return FAILURE
	cre.set_task_tag("ActSetAlert")
	cre.set_alert(cre.player_pos())
	return FAILURE
