@tool
class_name ActPatrol
extends BTAction
## Walks the exported patrol ring/points forever (advances on arrival).
## Always RUNNING while patrolling; higher-priority selector branches
## (combat/investigate/hear) preempt it.

func _tick(_delta: float) -> Status:
	var cre: NightmareCreature = agent as NightmareCreature
	if cre == null:
		return FAILURE
	if cre.is_stuck():
		cre.next_patrol_point()   # point inside geometry: skip it, keep walking
		cre.clear_stuck()         # else the hot flag chain-skips every point
	var p: Vector3 = cre.current_patrol_point()
	if cre.move_toward_point(p, cre.walk_speed):
		cre.next_patrol_point()
	cre.play_anim(cre.anim_walk)
	return RUNNING
