@tool
class_name ActSetAlert
extends BTAction
## Sets the investigation target from awareness.last_known_pos() (if available)
## or falls back to the current player position. Returns SUCCESS immediately.

func _tick(_delta: float) -> Status:
	var cre: NightmareCreature = agent as NightmareCreature
	if cre == null:
		return FAILURE
	cre.set_task_tag(NightmareCreature.TaskTag.SET_ALERT)

	var target: Vector3 = cre.player_pos()
	if cre.awareness != null and cre.awareness.has_memory():
		target = cre.awareness.last_known_pos()

	cre.set_alert(target, false)
	return SUCCESS
