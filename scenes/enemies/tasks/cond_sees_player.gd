@tool
class_name CondSeesPlayer
extends BTCondition
## Queries CreatureAwareness.confirmed() — returns true when the player has been
## continuously visible for CONFIRM_TIME seconds, or within the post-sighting
## combat-lock window.
##
## All confirmation/lock timer logic lives in CreatureAwareness where it belongs.
## This task is now a clean query with no internal state.

func _tick(_delta: float) -> Status:
	var cre: NightmareCreature = agent as NightmareCreature
	if cre == null:
		return FAILURE
	if cre.awareness == null:
		return FAILURE
	return SUCCESS if cre.awareness.confirmed() else FAILURE
# NOTE: canonical file (a stale PascalCase duplicate condSeesPlayer.gd that called the removed get_memory() API was deleted in the R16 pass — on case-insensitive file systems the two used to collide).
