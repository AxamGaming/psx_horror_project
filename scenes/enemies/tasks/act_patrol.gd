@tool
class_name ActPatrol
extends BTAction
## Walks the exported patrol ring/points forever (advances on arrival).
## Always RUNNING while patrolling; higher-priority selector branches
## (combat/investigate/hear) preempt it -- and now actually CAN preempt it,
## because the root is a BTDynamicSelector (round 6).

func _tick(_delta: float) -> Status:
	var cre: NightmareCreature = agent as NightmareCreature
	if cre == null:
		return FAILURE
	cre.set_task_tag("ActPatrol")
	if cre.is_stuck():
		cre.next_patrol_point()   # point inside geometry: skip it, keep walking
		cre.clear_stuck()         # else the hot flag chain-skips every point
	var p: Vector3 = cre.current_patrol_point()
	if cre.move_toward_point(p, cre.walk_speed):
		cre.next_patrol_point()
		cre.clear_stuck()         # R6: arrival is not "stuck"
	cre.play_gait(cre.walk_speed)
	return RUNNING
