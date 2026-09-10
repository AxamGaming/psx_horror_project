@tool
class_name CondHasAlert
extends BTCondition
## Succeeds while the agent holds an investigation target (set by gunshots,
## hearing, or ActSetAlert). Stored on the agent, not the blackboard.

func _tick(_delta: float) -> Status:
	var cre: NightmareCreature = agent as NightmareCreature
	if cre == null:
		return FAILURE
	return SUCCESS if cre.has_alert() else FAILURE
# NOTE: canonical file (a stale PascalCase duplicate condHasAlert.gd that called the removed get_memory() API was deleted in the R16 pass — on case-insensitive file systems the two used to collide).
