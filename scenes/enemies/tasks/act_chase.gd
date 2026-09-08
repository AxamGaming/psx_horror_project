@tool
class_name ActChase
extends BTAction
## Runs straight at the player at full speed. Always RUNNING while active;
## swipe/lunge conditions sit above it in the selector.

func _tick(_delta: float) -> Status:
	var cre: NightmareCreature = agent as NightmareCreature
	if cre == null:
		return FAILURE
	cre.move_toward_point(cre.player_pos(), cre.run_speed)
	cre.play_anim(cre.anim_run)
	return RUNNING
