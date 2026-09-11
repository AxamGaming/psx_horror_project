@tool
class_name ActChase
extends BTAction
## Chase the player. When confirmed visible, uses player_pos(). When in the
## combat-lock window (awareness.confirmed() is still true but LOS just dropped),
## chases awareness.last_known_pos() — the creature pursues where it last SAW
## you rather than standing confused.
##
## Returns RUNNING always (BTDynamicSelector above re-tests CondSeesPlayer each
## tick and aborts when the lock window expires and LOS is gone).

var _at_standoff: bool = false


func _enter() -> void:
	_at_standoff = false


func _tick(_delta: float) -> Status:
	var cre: NightmareCreature = agent as NightmareCreature
	if cre == null:
		return FAILURE
	cre.set_task_tag("ActChase")

	# Target: actual player position if we have memory, else last-known.
	var target: Vector3 = cre.player_pos()
	if cre.awareness != null and cre.awareness.has_memory():
		target = cre.awareness.last_known_pos()
		# Prefer actual player pos when close enough to confirm they're there.
		if (cre.player_pos() - cre.global_position).length() < cre.sight_range:
			target = cre.player_pos()

	# R19 hysteresis: at point-blank the distance oscillates around the
	# standoff radius (depenetration pushes, knockback, player kiting), and
	# the hard <= test flipped stop+battle_idle <-> run+Run EVERY TICK —
	# visibly flickering animations. Enter standoff at 1.35 m, leave only
	# past 1.70 m.
	var d: float = cre.dist_to_player()
	if _at_standoff:
		if d > cre.attack_standoff + 0.35:
			_at_standoff = false
	elif d <= cre.attack_standoff:
		_at_standoff = true
	if _at_standoff:
		cre.stop_move()
		cre.play_anim(cre.anim_battle_idle)
	else:
		cre.move_toward_point(target, cre.run_speed, cre.attack_standoff)
		cre.play_gait(cre.run_speed)
	return RUNNING
# NOTE: canonical file (a stale PascalCase duplicate actChase.gd that called the removed get_memory() API was deleted in the R16 pass — on case-insensitive file systems the two used to collide).
