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
##
## R16 PROWL: when the travel target is unreachable (player on the Stage top,
## behind the barrel wedge, inside the crawlspace) and the creature has
## arrived at the closest reachable point, it no longer rams the obstacle
## forever. It circles the point at half speed, alternating direction every
## 2.8 s — reads as "hunting for a way in", keeps the step-assist probing new
## edges, and after 1.4 s of prowling travel_to() reports ARRIVED so
## investigate/patrol proceed to their search/dwell phases instead of
## flip-flopping tasks (the R15 log's Investigate↔Patrol↔SetAlert churn).
## Prowling never counts as stuck/jammed/nav-failed.
## ============================================================================

# ── Constants ────────────────────────────────────────────────────────────────
const STUCK_THRESHOLD    := 0.1    # m/s below which we count as pinned
const JAM_PROGRESS       := 0.2    # m/s net progress below which jam fires
const JAM_WINDOW         := 1.5    # seconds of poor progress → jammed
const UNSTICK_INTERVAL   := 0.8    # seconds per unstick escalation step
const BACKOFF_DURATION   := 0.6    # R17: 0.45 strafes were too short to clear
                                   # the door-blade/post pocket (needed ~1.3 m)
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
var _held_age: float = 999.0   # R16: held headings now EXPIRE (see steering)

# ── Move stamp (velocity watchdog — kills ghost velocity) ─────────────────────
var _stamp: int = 0
var _stamp_prev: int = -1

# ── Previous position for real_hspd ──────────────────────────────────────────
var _prev_pos: Vector3 = Vector3.ZERO

# ── Prowl (unreachable-goal circling) ────────────────────────────────────────
var _prowling: bool = false
var _prowl_accum: float = 0.0
var _prowl_off_t: float = 0.0    # hysteresis: how long the entry cond has been false
var _prowl_log_cd: float = 0.0   # rate-limit the PROWL telemetry line
var _circle_t: float = 0.0
var _circle_sign: float = 1.0
var _steer_dbg_t: float = 0.0   # stuck-steering telemetry (1 Hz while pinned)
## Cached end-of-partial-path. get_current_navigation_path() blips EMPTY on the
## frames right after the per-tick retarget, which made the prowl gate flicker
## on/off every frame (R16 test run: 488 PROWL log lines in 10 s and a jittery
## orbit). The cache holds the last real path end so the orbit centre is stable.
var _prowl_center: Vector3 = Vector3.ZERO
var _path_end: Vector3 = Vector3.ZERO   # last point of the live path (poll-time snapshot)
var _path_end_valid: bool = false


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

	# A substantially new destination restarts the prowl budget.
	if target.distance_to(_target) > 1.5:
		_prowl_accum = 0.0
		_prowl_center = target

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

	# Already finished the nav path near the goal (FLAT distance: the old 3D
	# check never fired when the goal sat 0.4 m up on the Stage).
	if _active and _nav_finished:
		var fg: Vector3 = _nav_goal - _creature.global_position
		fg.y = 0.0
		if fg.length() < 1.0:
			stop()
			return true

	_active = true
	_target = target
	_speed = speed
	_arrive = arrive
	_stamp += 1

	# Circled an unreachable goal long enough → report arrival. Chase ignores
	# the return value and keeps prowling; investigate/patrol move on to their
	# search/dwell/skip logic instead of ramming forever.
	if _prowling and _prowl_accum > 1.4:
		return true
	return false


## Stop all movement.
func stop() -> void:
	_active = false
	_prowling = false
	_prowl_accum = 0.0
	_prowl_off_t = 0.0
	_prowl_center = _creature.global_position if _creature != null else Vector3.ZERO
	_creature.velocity.x = 0.0
	_creature.velocity.z = 0.0
	move_dir = Vector3.ZERO
	_stamp += 1


## Called every physics frame by NightmareCreature BEFORE move_and_slide().
func tick(delta: float) -> void:
	if _creature == null or _nav == null:
		return

	# ── Bind to baker's nav map (once) ───────────────────────────────────────
	# R17 — THE BIG ONE: this used to call NavigationServer3D.agent_set_map()
	# directly, which only rebinds the agent SERVER-SIDE. NavigationAgent3D
	# runs its own path queries through the NODE-cached map RID
	# (get_navigation_map()), which stayed on the EMPTY default world map —
	# so get_current_navigation_path() was always [] and
	# get_next_path_position() always returned the agent's own feet (the
	# STEERDBG dumps: pp=0, wp==pos, reachability flickering). Every "nav"
	# behaviour this project ever had was the straight-line/held-dir/unstick
	# fallback compensating. set_navigation_map() sets the server binding AND
	# the node cache, so real paths finally flow: waypoint steering, honest
	# is_target_reachable(), real closest-point snaps, real prowl centres.
	if _baker == null:
		_baker = _creature.get_tree().get_first_node_in_group("nav_baker")
	if not _map_bound and _baker != null:
		_nav.set_navigation_map(_baker.get_map_rid())
		_map_bound = true

	# ── Poll nav agent every frame (required by NavigationAgent3D docs) ───────
	if not _nav_dead and _creature._awake and not _creature._neutralized:
		_nav_wp = _nav.get_next_path_position()
		# R17: the path is retargeted EVERY tick, and a fresh path starts at the
		# agent's own feet — get_next_path_position() then returns a point ~0 m
		# away, raw-steering collapsed to the straight-line fallback, and the
		# creature body-checked door posts instead of aiming at the doorway
		# corner (run-3: pinned between the open Door2 panel and PostA while the
		# 1.8 m gap was 0.5 m to its right). Pick the first path point actually
		# ahead of the body; that keeps priority-1 corner steering alive.
		var ppath: PackedVector3Array = _nav.get_current_navigation_path()
		var cpos: Vector3 = _creature.global_position
		_path_end_valid = ppath.size() > 0
		if _path_end_valid:
			_path_end = ppath[ppath.size() - 1]
		for pt in ppath:
			var flat_pt: Vector3 = pt - cpos
			flat_pt.y = 0.0
			if flat_pt.length() > 0.35:
				_nav_wp = pt
				break
		var fg: Vector3 = _nav_goal - _creature.global_position
		fg.y = 0.0
		_nav_finished = _nav.is_navigation_finished() and fg.length() < 1.0

	# ── Measure real ground speed ─────────────────────────────────────────────
	var disp: Vector3 = _creature.global_position - _prev_pos
	real_hspd = Vector2(disp.x, disp.z).length() / maxf(delta, 0.0001)
	_prev_pos = _creature.global_position

	# ── Velocity watchdog: kill ghost velocity when no task is driving ────────
	# R19: winding NO LONGER exempt — the navigator is stopped for the swing,
	# so without this the chase speed bled through the whole attack pose
	# (skating swipes at point-blank). Lunges still own their velocity.
	if not _creature._lunging and not _creature._neutralized:
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
		if _active and not _prowling and not _creature._neutralized \
				and _backoff_t <= 0.0 and progress < JAM_PROGRESS:
			_jam_t += _net_t
		else:
			_jam_t = 0.0
		_jammed = _jam_t > JAM_WINDOW
		_net_pos = _creature.global_position
		_net_t = 0.0

	# ── Pinned detection ──────────────────────────────────────────────────────
	var stuck: bool = _active and not _prowling and not _nav_finished \
			and (real_hspd < STUCK_THRESHOLD or _jammed)
	if stuck:
		_pinned_t += delta
	else:
		_pinned_t = 0.0

	# ── Unstick timer ─────────────────────────────────────────────────────────
	# R16 reset fix: the old ladder ended with `if not stuck: clear_t = 0`,
	# which zeroed the recovery timer on EVERY healthy frame — so
	# _unstick_fails never decayed and after ~4 lifetime fails every later
	# episode jumped straight to fail=3→GIVEUP (door never got its force_open
	# retries; log 1769→1782→2238 shows fails never resetting across 12 s of
	# clean walking). Now: 1.5 s of genuinely-free movement clears the ladder.
	var unstick_accumulating: bool = \
		_active and not _prowling and not _nav_finished and _backoff_t <= 0.0 \
		and (real_hspd < 0.2 or _jammed)
	if unstick_accumulating:
		_unstick_clear_t = 0.0
		if _pinned_t > UNSTICK_INTERVAL * float(_unstick_fails + 1):
			_try_unstick()
	elif stuck:
		_unstick_clear_t = 0.0
	else:
		_unstick_clear_t += delta
		if _unstick_clear_t > 1.5:
			_unstick_fails = 0

	# ── Nav reachability / give-up / dead latch ───────────────────────────────
	var baker_ok: bool = _baker != null and _baker.is_ready()
	if _creature._awake and not _creature._neutralized and _active \
			and not _prowling and not _nav_reachable and baker_ok:
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
		# R16: ALWAYS snap to the closest reachable point (the old < 3 m gate
		# rejected the snap for far-off targets like the player holed up in the
		# spawn room — which left _nav_reachable stuck TRUE, no prowl, and the
		# creature body-checking the crawlspace mouth forever). Walking to the
		# best-effort point and prowling there is strictly better than ramming.
		if snap.is_finite():
			snapped_target = snap
	_nav_goal = snapped_target
	_nav_snapped = snapped_target.distance_squared_to(_target) > 0.01
	_nav.target_position = snapped_target
	_nav_reachable = not _nav_snapped

	# ── Prowl: unreachable goal AND standing at the closest reachable point ──
	# The orbit centre is the END OF THE PARTIAL PATH (the closest reachable
	# point), NOT _nav_goal: when the snap lands on a different navmesh island
	# (player holed up in the spawn room), _nav_goal can be 10 m away while the
	# body is already parked at the crawlspace mouth where the path ends.
	if not _nav_reachable:
		if _path_end_valid:
			_prowl_center = _path_end
	else:
		_prowl_center = _nav_goal
	var to_goal: Vector3 = _prowl_center - _creature.global_position
	to_goal.y = 0.0
	# R17 hysteresis: is_target_reachable() and the 1.7 m gate both flutter
	# frame-to-frame while chasing a moving player near mesh edges (player log:
	# 2228 PROWL lines in 7 min, jam/pinned detectors poisoning gait anims on
	# the off-frames). Enter immediately, but only LEAVE after the entry
	# condition has been false for 0.45 s straight.
	_prowl_log_cd = maxf(0.0, _prowl_log_cd - delta)
	var want_prowl: bool = not _nav_dead and not _nav_reachable \
			and _backoff_t <= 0.0 and to_goal.length() < 1.7
	if want_prowl:
		_prowling = true
		_prowl_off_t = 0.0
	elif _prowling:
		_prowl_off_t += delta
		if _prowl_off_t > 0.45 or _nav_dead:
			_prowling = false
			_prowl_off_t = 0.0
	if _prowling:
		_prowl_accum += delta
		_circle_t += delta
		if _circle_t > 2.8:
			_circle_t = 0.0
			_circle_sign = -_circle_sign
		if _prowl_log_cd <= 0.0:
			_prowl_log_cd = 3.0
			_creature._log("PROWL unreachable goal task=%s" % _creature._task_tag)
		var radial: Vector3 = to_goal.normalized() if to_goal.length_squared() > 0.01 \
				else -_creature.global_transform.basis.z
		var tang: Vector3 = Vector3(-radial.z, 0.0, radial.x) * _circle_sign
		# Keep a ~1.15 m orbit: gently pull in / push out.
		var corr: float = clampf(1.15 - to_goal.length(), -0.5, 0.5) * 1.6
		var cdir: Vector3 = (tang + radial * corr).normalized()
		move_dir = cdir
		_held_dir = cdir
		# Blocked orbit (crawlspace-mouth wall, stage side): keep pressing but
		# FACE the unreachable point instead of the tangent — it watches the
		# hole you vanished into rather than standing with its back to it.
		if real_hspd < 0.3:
			_creature._move_dir = radial
		else:
			_creature._move_dir = cdir
		_creature.velocity.x = cdir.x * _speed * 0.5
		_creature.velocity.z = cdir.z * _speed * 0.5
		_stamp += 1
		return
	if _prowl_accum > 0.0:
		_prowl_accum = maxf(0.0, _prowl_accum - delta * 2.0)

	# Steering priority (R18 ordering, R16 hardening):
	#  1. Nav path waypoint (corners, doorways)
	#  2. Straight line if lane is physically clear
	#  3. Held heading — ONLY if it is fresh (< 0.5 s) and still physically
	#     clear. The old un-gated held heading was a ratchet: one frame of
	#     wall-slide latched the slide direction, clear_path(to_target) kept
	#     failing from behind the wall, and the creature surfed the wall into
	#     the nearest corner forever (log: Door2 approach → 7 m east-slide to
	#     the hall east corner, then the same trick west to (-7.5,-6.65)).
	#  4. Push toward the goal ANYWAY: move_and_slide scrubs the blocked
	#     component and the body slides along the geometry toward the gap —
	#     for the closed-door case that means sliding into the panel, getting
	#     pinned, and letting the unstick ladder fire force_open().
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
		elif _held_age < 0.5 and _held_dir.length_squared() > 0.001 \
				and _clear_path(_held_dir, 0.8):
			dir = _held_dir
		else:
			dir = to_t.normalized()

	# Stuck telemetry: while the body is commanded but going nowhere, dump the
	# full steering decision once per second — wp, path size, chosen dir,
	# prowl centre, reachability. This is what diagnosed the empty-path /
	# map-binding disease; keep it for future stuck reports.
	_steer_dbg_t += delta
	if real_hspd < 0.3 and _steer_dbg_t > 1.0:
		_steer_dbg_t = 0.0
		var ppn: int = _nav.get_current_navigation_path().size()
		_creature._log("STEERDBG pos=(%.2f,%.2f) wp=(%.2f,%.2f) pp=%d dir=(%.2f,%.2f) center=(%.2f,%.2f) reach=%s fin=%s onwall=%s tgt=(%.2f,%.2f) bo=%.2f prow=%s" % [
			_creature.global_position.x, _creature.global_position.z,
			_nav_wp.x, _nav_wp.z, ppn, dir.x, dir.z,
			_prowl_center.x, _prowl_center.z,
			str(_nav_reachable), str(_nav_finished), str(_creature.is_on_wall()),
			_target.x, _target.z, _backoff_t, str(_prowling)])

	move_dir = dir
	if _held_dir.dot(dir) > 0.98:
		_held_age += delta
	else:
		_held_dir = dir
		_held_age = 0.0
	_creature._move_dir = dir   # creature uses this for facing
	_creature.velocity.x = dir.x * _speed
	_creature.velocity.z = dir.z * _speed
	_stamp += 1


## True when the creature has been commanded but isn't moving (plays battle_idle).
func is_pinned() -> bool:
	return _active and not _prowling and _pinned_t > 0.8


## True when the creature has been stuck for more than 1 s (used by ActPatrol).
func is_stuck() -> bool:
	return _active and not _prowling and _pinned_t > 1.0


## True while circling an unreachable goal (blocks lunges, counts as arrival).
func prowling() -> bool:
	return _prowling


# ── Internal ──────────────────────────────────────────────────────────────────

func _try_unstick() -> void:
	_unstick_fails += 1

	# Try door open first — but only if it is actually closed. R17: calling
	# force_open() on an OPEN door silently no-ops yet still consumed the whole
	# unstick attempt (and set the 4 s door cooldown), so a creature wedged
	# between the open panel and the post never got to the strafe ladder.
	if _door_cd <= 0.0:
		var hit: Node = _forward_collider(2.2)
		var node: Node = hit
		while node != null:
			if node.has_method("force_open"):
				var already_open: bool = node.has_method("is_open") and bool(node.call("is_open"))
				if not already_open:
					node.call("force_open")
					_door_cd = 4.0
					_creature._log("UNSTICK door open: %s" % node.name)
					return
				break
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
	# R16: knee height, not chest height — a 0.7 m ray flew OVER the 0.4 m
	# Stage and the steering fallback body-checked it forever.
	var from: Vector3 = _creature.global_position + Vector3(0.0, 0.3, 0.0)
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
	var from: Vector3 = _creature.global_position + Vector3(0.0, 0.3, 0.0)
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			from, from + fwd * dist)
	q.exclude = [_creature.get_rid()]
	q.collision_mask = 17
	var hit: Dictionary = world.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	return hit.get("collider") as Node
