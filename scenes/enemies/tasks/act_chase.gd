@tool
class_name ActChase
extends BTAction
## Runs at the player, but STOPS at agent.attack_standoff instead of closing to
## the arrival radius. Returns RUNNING always -- that is correct for a chase.
##
## ROUND 6: what was NOT correct was sitting under a plain BTSelector. LimboAI's
## BTSelector remembers the child that returned RUNNING and resumes ONLY that
## child, so the first tick that reached this task parked the whole tree here for
## the rest of the session: CondInSwipeRange / CondCanLunge / CondSeesPlayer /
## CondNeutralized were never evaluated again. Evidence in creature_log R5:
## anim=Run in 274/274 awake samples, zero WINDUP/SWIPE/LUNGE events, dist pinned
## at 0.76 m -- far inside swipe_range 1.9 m -- for 276 seconds.
## The combat selector above this is now a BTDynamicSelector, which re-tests its
## earlier children every tick and abort()s this one when a swing goes live.

func _tick(_delta: float) -> Status:
	var cre: NightmareCreature = agent as NightmareCreature
	if cre == null:
		return FAILURE
	cre.set_task_tag("ActChase")
	if cre.dist_to_player() <= cre.attack_standoff:
		# In contact: hold station and menace. Playing Run while pinned is the
		# "running in place at the same spot" look from rounds 2-5.
		cre.stop_move()
		cre.play_anim(cre.anim_battle_idle)
	else:
		cre.move_toward_point(cre.player_pos(), cre.run_speed, cre.attack_standoff)
		cre.play_gait(cre.run_speed)
	return RUNNING
