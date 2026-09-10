@tool
class_name CondInSwipeRange
extends BTCondition
## Succeeds when the player is inside melee swipe range AND the swing is off
## cooldown.
##
## ROUND 6, two changes:
##  1. attack_ready() gate. Nothing checked _attack_cd anywhere before, so once
##     the tree latch is removed the creature would swing every windup_time
##     (0.55 s) instead of every swipe_cooldown (1.6 s).
##  2. STICKY while winding. This condition now sits under a BTDynamicSequence,
##     which re-executes it every tick and aborts the RUNNING child if it fails.
##     Without the is_winding() term, a player stepping 5 cm backwards mid-swing
##     would cancel the telegraph every time and the swipe could never land.

func _tick(_delta: float) -> Status:
	var cre: NightmareCreature = agent as NightmareCreature
	if cre == null:
		return FAILURE
	if cre.is_winding():
		return SUCCESS                    # commit to the telegraph already started
	if not cre.attack_ready():
		return FAILURE                    # on cooldown -> fall through to lunge/chase
	# R18: vertical gate — don't wind up at a target it physically can't reach
	# (hovering debug-fly player, tall ledge). Stage-height (0.4 m) is fine.
	if absf(cre.player_pos().y - cre.global_position.y) > 1.6:
		return FAILURE
	return SUCCESS if cre.dist_to_player() < cre.swipe_range else FAILURE
