extends Node
class_name CreatureNavigator
## ============================================================================
## CREATURE NAVIGATOR — owns all navigation and steering.
##
## This node is the single writer of the creature's velocity.x / velocity.z.
## No other node (no BT task, no creature script) writes those components
## except during lunges (agent-owned animation physics, explicitly documented).
##
## Design:
##   Tasks call  nav.travel_to(target, speed, arrive)  → returns bool (arrived)
##   Tasks call  nav.stop()  when they want the body stationary.
##   _physics_process on the creature calls  nav.tick(delta)  every frame.
##   The steering output (velocity.x/z + _move_dir) is written here and
##   nowhere else — the "one writer" rule from the referenced enemy.gd.
##
## Unstick ladder (escalating, never looping):
##   0.8 s pinned → try door open or strafe right
##   1.6 s pinned → strafe left
##   2.4 s pinned → back off 0.45 s
##   3.2 s pinned → give up target (clear alert / skip patrol point)
##
## Nav-dead fallback: after 3 give-ups with nav unreachable, straight-line
## movement replaces path following. Re-checks nav reachability every 1 s.
## ============================================================================

# ── Constants ────────────────────────────────────────────────────────────────
const STUCK_THRESHOLD    := 0.1    # m/s below which we count as pinned
const JAM_PROGRESS       := 0.2    # m/s net progress below which jam fires
const JAM_WINDOW         := 1.5    # seconds of poor progress → jammed
const UNSTICK_INTERVAL   := 0.8    # seconds per unstick escalation step
const BACKOFF_DURATION   := 0.45
const NAV_FAIL_TIMEOUT   := 2.0    # seconds of unreachable before give-up
const NAV_GIVEUP_CD      := 6.0
const NAV_DEAD_REPROBE   := 1.0
const NAV_DEAD_GIVEUPS   := 3

# ── Wired by NightmareCreature._ready() ──────────────────────────────────────
var _creature: NightmareCreature = null
var _nav: NavigationAgent3D = null
var _baker: Node = null

# ── Travel request ────────────────────────────────────────────────────────────
var _active: bool = false          # is a travel request in flight?
var _target: Vector3 = Vector3.ZERO
var _speed: float = 0.0
var _arrive: float = 0.7

# ── Steering output (read by creature for facing / animation) ─────────────────
var move_dir: Vector3 = Vector3.ZERO    # last commanded horizontal direction
var real_hspd: float = 0.0             # actual ground speed, m/s (set by tick)

# ── Internal navigation ───────────────────────────────────────────────────────
var _nav_wp: Vector3 = Vector3.ZERO    # polled each frame from NavigationAgent3D
var _nav_finished: bool = false
var _nav_goal: Vector3 = Vector3.ZERO  # possibly snapped goal
var _nav_snapped: bool = false
var _map_bound: bool = false
var _nav_reachable: bool = true
var _nav_dead: bool = false
var _nav_dead_probe_t: float = 0.0
var _giveups: int = 0
var _giveup_cd: float = 0.0
var _nav_fail_t: float = 0.0

# ── Unstick / jam state ───────────────────────────────────────────────────────
var _pinned_t: float = 0.0
var _unstick_fails: int = 0
var _unstick_clear_t: float = 0.0
var _backoff_t: float = 0.0
var _backoff_dir: Vector3 = Vector3.ZERO
var _door_cd: float = 0.0

# ── Jam detector (net progress, not per-frame speed) ─────────────────────────
var _net_pos: Vector3 = Vector3.ZERO
var _net_t: float = 0.0
var _jam_t: float = 0.0
var _jammed: bool = false

# ── Held heading (survives path stalls) ──────────────────────────────────────
var _held_dir: Vector3 = Vector3.ZERO

# ── Move stamp (velocity watchdog — kills ghost velocity) ─────────────────────
var _stamp: int = 0
var _stamp_prev: int = -1

# ── Previous position for real_hspd ──────────────────────────────────────────
var _prev_pos: Vector3 = Vector3.ZERO


func setup(creature: NightmareCreature, nav_agent: NavigationAgent3D) -> void:
	_creature = creature
	_nav = nav_agent
	_nav.path_desired_distance  = 0.4
	_nav.target_desired_distance = 0.4
	_nav.path_max_distance       = 6.0
	_nav.avoidance_enabled       = false
	_net_pos = creature.global_position
	_prev_pos = creature.global_position


## Request movement toward target at speed; returns true when arrived.
## This is the ONLY call BT tasks make to produce creature movement.
func travel_to(target: Vector3, speed: float, arrive: float = 0.7) -> bool:
	var to_t: Vector3 = target - _creature.global_position
	to_t.y = 0.0

	# Personal-space: don't drive into the player capsule.
	if _creature._player != null and target.distance_to(_creature.player_pos()) < 1.0:
		arrive = maxf(arrive, 0.95)

	if to_t.length() < arrive:
		stop()
		return true

	# React telegraph: stand still even when chase is active.
	if _creature._react_t > 0.0:
		stop()
		return false

	# Already finished the nav path near the goal.
	if _active and _nav_finished and (_nav_goal - _creature.global_position).length() < 1.0:
		stop()
		return true

	_active = true
	_target = target
	_speed = speed
	_arrive = arrive
	_stamp += 1
	return false


## Stop all movement.
func stop() -> void:
	_active = false
	_creature.velocity.x = 0.0
	_creature.velocity.z = 0.0
	move_dir = Vector3.ZERO
	_stamp += 1


## Called every physics frame by NightmareCreature BEFORE move_and_slide().
func tick(delta: float) -> void:
	if _creature == null or _nav == null:
		return

	# ── Bind to baker's nav map (once) ───────────────────────────────────────
	if _baker == null:
		_baker = _creature.get_tree().get_first_node_in_group("nav_baker")
	if not _map_bound and _baker != null:
		NavigationServer3D.agent_set_map(_nav.get_rid(), _baker.get_map_rid())
		_map_bound = true

	# ── Poll nav agent every frame (required by NavigationAgent3D docs) ───────
	if not _nav_dead and _creature._awake and not _creature._neutralized:
		_nav_wp = _nav.get_next_path_position()
		_nav_finished = _nav.is_navigation_finished() \
				and (_nav_goal - _creature.global_position).length() < 1.0

	# ── Measure real ground speed ─────────────────────────────────────────────
	var disp: Vector3 = _creature.global_position - _prev_pos
	real_hspd = Vector2(disp.x, disp.z).length() / maxf(delta, 0.0001)
	_prev_pos = _creature.global_position

	# ── Velocity watchdog: kill ghost velocity when no task is driving ────────
	if not _creature._lunging and not _creature._winding and not _creature._neutralized:
		if _stamp == _stamp_prev:
			_creature.velocity.x = 0.0
			_creature.velocity.z = 0.0
	_stamp_prev = _stamp

	# ── Jam / progress detector ───────────────────────────────────────────────
	_net_t += delta
	if _net_t >= 1.0:
		var net: Vector3 = _creature.global_position - _net_pos
		net.y = 0.0
		var progress: float = net.length() / _net_t
		if _active and not _creature._neutralized and _backoff_t <= 0.0 and progress < JAM_PROGRESS:
			_jam_t += _net_t
		else:
			_jam_t = 0.0
		_jammed = _jam_t > JAM_WINDOW
		_net_pos = _creature.global_position
		_net_t = 0.0

	# ── Pinned detection ──────────────────────────────────────────────────────
	var stuck: bool = _active and not _nav_finished and (real_hspd < STUCK_THRESHOLD or _jammed)
	if stuck:
		_pinned_t += delta
	else:
		_pinned_t = 0.0

	# ── Unstick timer ─────────────────────────────────────────────────────────
	var unstick_accumulating: bool = \
		_active and not _nav_finished and _backoff_t <= 0.0 and (real_hspd < 0.2 or _jammed)
	if unstick_accumulating:
		if _pinned_t > UNSTICK_INTERVAL * float(_unstick_fails + 1):
			_try_unstick()
	else:
		_unstick_clear_t += delta
		if _unstick_clear_t > 1.5:
			_unstick_fails = 0
		if not stuck:
			_unstick_clear_t = 0.0

	# ── Nav reachability / give-up / dead latch ───────────────────────────────
	var baker_ok: bool = _baker != null and _baker.is_ready()
	if _creature._awake and not _creature._neutralized and _active and not _nav_reachable and baker_ok:
		_nav_fail_t += delta
	else:
		_nav_fail_t = 0.0
		_giveups = 0

	_giveup_cd = maxf(0.0, _giveup_cd - delta)
	if _creature._awake and not _creature._neutralized and not _nav_dead and _active \
			and _nav_fail_t > NAV_FAIL_TIMEOUT and _giveup_cd <= 0.0:
		_nav_fail_t = 0.0
		_giveup_cd = NAV_GIVEUP_CD
		_giveups += 1
		_on_nav_giveup()
		if _giveups >= NAV_DEAD_GIVEUPS and not _nav_reachable:
			_nav_dead = true
			_creature._log("NAV DEAD — straight-line fallback")

	# ── Nav-dead re-probe ─────────────────────────────────────────────────────
	if _nav_dead and _active:
		_nav_dead_probe_t += delta
		if _nav_dead_probe_t > NAV_DEAD_REPROBE:
			_nav_dead_probe_t = 0.0
			if _nav.is_target_reachable():
				_nav_dead = false
				_giveups = 0
				_nav_fail_t = 0.0
				_creature._log("NAV RECOVERED")

	_backoff_t = maxf(0.0, _backoff_t - delta)
	_door_cd = maxf(0.0, _door_cd - delta)

	# ── Apply velocity for this frame ─────────────────────────────────────────
	if not _active or _creature._neutralized:
		return

	if _backoff_t > 0.0:
		var bd: Vector3 = _backoff_dir.normalized()
		move_dir = bd
		_creature.velocity.x = bd.x * _creature.walk_speed
		_creature.velocity.z = bd.z * _creature.walk_speed
		_stamp += 1
		return

	# Retarget nav every tick (reference: update_path_delay = 0).
	# Per-frame retarget is cheap; the 10 Hz throttle stalled the path for
	# 1-3 frames and re-introduced the R16/R17 crawl.
	var snapped_target: Vector3 = _target
	if not _nav.is_target_reachable():
		var snap: Vector3 = NavigationServer3D.map_get_closest_point(
				_nav.get_navigation_map(), _target)
		if snap.distance_squared_to(_target) < 9.0:
			snapped_target = snap
	_nav_goal = snapped_target
	_nav_snapped = snapped_target.distance_squared_to(_target) > 0.01
	_nav.target_position = snapped_target
	_nav_reachable = not _nav_snapped

	# Steering priority (proven R18 ordering):
	#  1. Nav path waypoint (corners, doorways)
	#  2. Straight line if lane is physically clear
	#  3. Held heading while path settles
	#  4. Straight line fallback
	var to_t: Vector3 = _target - _creature.global_position
	to_t.y = 0.0
	var dir: Vector3
	if _nav_dead:
		dir = to_t.normalized()
	else:
		var raw: Vector3 = _nav_wp - _creature.global_position
		raw.y = 0.0
		if raw.length_squared() > 0.0004:
			dir = raw.normalized()
		elif _clear_path(to_t.normalized(), minf(to_t.length(), 3.0)):
			dir = to_t.normalized()
		elif _held_dir.length_squared() > 0.001:
			dir = _held_dir
		else:
			dir = to_t.normalized()

	move_dir = dir
	_held_dir = dir
	_creature._move_dir = dir   # creature uses this for facing
	_creature.velocity.x = dir.x * _speed
	_creature.velocity.z = dir.z * _speed
	_stamp += 1


## True when the creature has been commanded but isn't moving (plays battle_idle).
func is_pinned() -> bool:
	return _active and _pinned_t > 0.8


## True when the creature has been stuck for more than 1 s (used by ActPatrol).
func is_stuck() -> bool:
	return _active and _pinned_t > 1.0


# ── Internal ──────────────────────────────────────────────────────────────────

func _try_unstick() -> void:
	_unstick_fails += 1

	# Try door open first.
	if _door_cd <= 0.0:
		var hit: Node = _forward_collider(2.2)
		var node: Node = hit
		while node != null:
			if node.has_method("force_open"):
				node.call("force_open")
				_door_cd = 4.0
				_creature._log("UNSTICK door open: %s" % node.name)
				return
			node = node.get_parent()

	# Escalation: strafe → strafe other way → backoff → give up.
	if _unstick_fails >= 4:
		_unstick_fails = 0
		_on_unstick_giveup()
		_creature._log("UNSTICK GIVEUP task=%s" % _creature._task_tag)
		return

	var md: Vector3 = move_dir.normalized() if move_dir.length_squared() > 0.001 \
			else Vector3(1.0, 0.0, 0.0)
	if _unstick_fails == 1:
		_backoff_dir = Vector3(-md.z, 0.0, md.x)   # strafe right
	elif _unstick_fails == 2:
		_backoff_dir = Vector3(md.z, 0.0, -md.x)   # strafe left
	else:
		_backoff_dir = -md                           # back off
	_backoff_t = BACKOFF_DURATION
	_creature._log("UNSTICK fail=%d dir=(%s)" % [_unstick_fails, str(_backoff_dir)])


func _on_nav_giveup() -> void:
	if _creature._task_tag == "ActInvestigate" and _creature.has_alert():
		_creature.clear_alert()
		_creature._log("NAV GIVEUP: cleared investigate alert")
	elif _creature._task_tag == "ActPatrol":
		_creature.next_patrol_point()
		_creature._log("NAV GIVEUP: skipped patrol point")


func _on_unstick_giveup() -> void:
	if _creature._task_tag == "ActInvestigate" and _creature.has_alert():
		_creature.clear_alert()
	elif _creature._task_tag == "ActPatrol":
		_creature.next_patrol_point()


func _clear_path(dir: Vector3, dist: float) -> bool:
	var world: World3D = _creature.get_world_3d()
	if world == null or world.direct_space_state == null:
		return true
	var from: Vector3 = _creature.global_position + Vector3(0.0, 0.7, 0.0)
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			from, from + dir * dist)
	q.exclude = [_creature.get_rid()]
	q.collision_mask = 17
	return world.direct_space_state.intersect_ray(q).is_empty()


func _forward_collider(dist: float) -> Node:
	var world: World3D = _creature.get_world_3d()
	if world == null or world.direct_space_state == null:
		return null
	var fwd: Vector3 = move_dir.normalized() if move_dir.length_squared() > 0.001 \
			else -_creature.global_transform.basis.z
	var from: Vector3 = _creature.global_position + Vector3(0.0, 0.7, 0.0)
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			from, from + fwd * dist)
	q.exclude = [_creature.get_rid()]
	q.collision_mask = 17
	var hit: Dictionary = world.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	return hit.get("collider") as Node
