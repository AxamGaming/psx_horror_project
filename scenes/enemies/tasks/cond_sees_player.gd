@tool
class_name CondSeesPlayer
extends BTCondition
## Succeeds once the player has been visually confirmed for agent.confirm_time
## seconds (FOV cone + line-of-sight). Confirmation timer lives on the task
## instance (LimboAI blackboards are plan-based; undeclared vars error).

var _see_t: float = 0.0
## ROUND 10: once combat engages, hold it for this long even if FOV/LOS drops for
## a moment. Without it a one-second glimpse of the player produced a one-second
## ActChase blip and then a fall back to patrol/investigate -- the chase/patrol/
## investigate yo-yo in creature_log R9 (43 task transitions in 227 s).
var _lock_t: float = 0.0


## NOTE: no _enter() reset here on purpose — the root Selector restarts every
## tick, so resetting on entry would wipe the confirmation timer after every
## completed combat cycle and the creature would abandon chases mid-fight.
## The timer decays while the player is unseen, which is the real reset.
func _tick(delta: float) -> Status:
	var cre: NightmareCreature = agent as NightmareCreature
	if cre == null:
		return FAILURE
	# ROUND 11: post-recover amnesia. Without this the risen creature re-locked
	# on you the same tick it stood up ("immediately comes to kill me").
	if cre.is_amnesiac():
		_see_t = 0.0
		_lock_t = 0.0
		return FAILURE
	# Point-blank awareness: within proximity_range the creature knows you're
	# there regardless of FACING (horror rule) -- but NOT regardless of walls.
	if cre.dist_to_player() < cre.proximity_range:
		if cre.sees_player(false):
			_see_t = cre.confirm_time + 1.0
		else:
			_see_t = maxf(0.0, _see_t - delta * 1.0)
	elif cre.sees_player():
		# ROUND 11 CAP: _see_t grew unbounded while seeing, and R9's 0.5/s decay
		# then turned 20 s of line of sight into ~40 s of "still sees you" after
		# you broke it -- the "sees me through walls" report. Cap at confirm+0.5
		# and decay at 1.0/s; the 3 s lock below covers honest commitment.
		_see_t = minf(cre.confirm_time + 0.5, _see_t + delta)
	else:
		_see_t = maxf(0.0, _see_t - delta * 1.0)
	if _see_t > cre.confirm_time:
		_lock_t = 3.0
		cre.note_combat_start()
		return SUCCESS
	_lock_t = maxf(0.0, _lock_t - delta)
	return SUCCESS if _lock_t > 0.0 else FAILURE
