@tool
class_name CondSeesPlayer
extends BTCondition
## Succeeds once the player has been visually confirmed for agent.confirm_time
## seconds (FOV cone + line-of-sight). Confirmation timer lives on the task
## instance (LimboAI blackboards are plan-based; undeclared vars error).

var _see_t: float = 0.0


## NOTE: no _enter() reset here on purpose — the root Selector restarts every
## tick, so resetting on entry would wipe the confirmation timer after every
## completed combat cycle and the creature would abandon chases mid-fight.
## The timer decays while the player is unseen, which is the real reset.
func _tick(delta: float) -> Status:
	var cre: NightmareCreature = agent as NightmareCreature
	if cre == null:
		return FAILURE
	# Point-blank awareness: within proximity_range the creature knows you're
	# there regardless of facing (horror rule), else FOV cone + LOS + confirm.
	if cre.dist_to_player() < cre.proximity_range:
		_see_t = cre.confirm_time + 1.0
	elif cre.sees_player():
		_see_t += delta
	else:
		_see_t = maxf(0.0, _see_t - delta * 2.0)
	return SUCCESS if _see_t > cre.confirm_time else FAILURE
