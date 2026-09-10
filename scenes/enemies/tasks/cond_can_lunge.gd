@tool
class_name CondCanLunge
extends BTCondition
## Succeeds when a lunge is possible: mid-range window, cooldown ready,
## player confirmed visually.

func _tick(_delta: float) -> Status:
	var cre: NightmareCreature = agent as NightmareCreature
	if cre == null:
		return FAILURE
	var d: float = cre.dist_to_player()
	if d < cre.lunge_min or d > cre.lunge_max:
		return FAILURE
	# R18: no lunges at targets far above/below (debug-fly hover, high ledges) —
	# a horizontal dash can never reach them; it just looks silly. The Stage
	# (dy 0.4) and jumps stay well inside this window.
	if absf(cre.player_pos().y - cre.global_position.y) > 1.5:
		return FAILURE
	if not cre.lunge_ready():
		return FAILURE
	if not cre.sees_player():
		return FAILURE
	# ROUND 12: never lunge into a wall or a closed door. creature_log R11 shows
	# five consecutive LUNGE STARTs at dist=6.15 against Door2 -- sight grazed the
	# doorway, the body slammed the panel, cooldown, repeat.
	# R16: the clear_path ray now runs at knee height, so the 0.4 m Stage also
	# blocks lunges (the chest-height ray flew over it), and prowling -- the
	# navigator circling a goal it cannot reach (player on the Stage, in the
	# crawlspace) -- vetoes the lunge entirely instead of dash-ramming the
	# obstacle every cooldown.
	if cre.nav != null and cre.nav.prowling():
		return FAILURE
	var los: Vector3 = cre.player_pos() - cre.global_position
	los.y = 0.0
	if los.length_squared() < 0.0001:
		return FAILURE
	return SUCCESS if cre.clear_path(los.normalized(), d) else FAILURE
