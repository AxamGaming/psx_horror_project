extends CharacterBody3D
class_name NightmareCreature
## BUILD_TAG: bump every fix round. Debug panel shows it live, so a playtest
## proves in one glance whether the newest files are actually running.
const BUILD_TAG := "R21"
const LOG_PATH := "user://creature_log.txt"
## ============================================================================
## NIGHTMARE CREATURE — LimboAI agent (Phase 12 rebuild).
##
## Decision-making lives in a LimboAI BehaviorTree (built in code below,
## executed by the BTPlayer node); this script is the AGENT: senses, movement,
## combat resolution, animation mapping, 2.5D audio, health/neutralize rules.
## Custom tasks live in scenes/enemies/tasks/*.gd and call these methods.
##
## Tree shape (ROUND 6: every composite that guards a long-running action is a
## DYNAMIC one -- see _build_tree() for why that single change is the whole fix):
##   BTDynamicSelector                                (root)
##   ├─ DynSeq [ CondNeutralized, ActRecover ]         (down -> wait -> rise amnesiac)
##   ├─ DynSeq [ CondSeesPlayer(confirmed), BTDynamicSelector[
##   │        DynSeq[CondInSwipeRange, ActSwipe],
##   │        DynSeq[CondCanLunge,  ActLunge],
##   │        ActChase ] ]
##   ├─ Seq [ CondHearsPlayer, ActSetAlert ]           (noise -> investigation target)
##   ├─ DynSeq [ CondHasAlert, ActInvestigate ]        (go sniff, dwell, forget)
##   └─ ActPatrol                                      (walk the ring/points)
##
## Rules unchanged from design: NOT killable (0 hp = neutralize_time collapse,
## then full health + amnesia), wakes on first gunshot or point-blank sight,
## hearing scales with player noise, sight = FOV cone + LOS with confirm time.
## ============================================================================

@export_group("AI")
@export var patrol_points: Array[Vector3] = []   # your walk points, per instance
@export var auto_patrol_radius: float = 4.0
@export var hear_radius: float = 16.0
@export var sight_range: float = 12.0
@export var sight_fov_deg: float = 75.0
@export var confirm_time: float = 0.4
@export var proximity_range: float = 2.5      # point-blank awareness, ignores facing
@export var investigate_dwell: float = 4.0   # R7: was 6 s; 77% of the R6 run was
## spent in ActInvestigate, which read as "not intelligent"
@export var gunshot_hear_range: float = 40.0

@export_group("Movement")
@export var walk_speed: float = 2.2
@export var run_speed: float = 4.6
@export var lunge_speed: float = 7.5
@export var gravity: float = 18.0

@export_group("Combat")
@export var max_health: float = 100.0
@export var swipe_range: float = 1.9
@export var swipe_damage: float = 25.0
@export var swipe_cooldown: float = 1.6
@export var windup_time: float = 0.55
@export var lunge_min: float = 2.2
@export var lunge_max: float = 6.5
@export var lunge_damage: float = 35.0
@export var lunge_cooldown: float = 4.0
@export var lunge_time: float = 0.55
@export var knockback_force: float = 7.0
## ROUND 6: ActChase stops here instead of grinding into the player capsule.
## Must be > 0.75 m (0.4 creature + 0.35 player capsule radii = contact distance,
## which is exactly the 0.76 m the R5 log was pinned at for 276 s) and
## < swipe_range (1.9) so a swing is always available once it arrives.
@export var attack_standoff: float = 1.35   # R19: head stays ~1 m off your camera
@export var neutralize_time: float = 25.0
@export var void_y: float = -0.5              # below floor level => reset to spawn

@export_group("Debug")
@export var debug_beacon: bool = true         # magenta orb at the BODY (not the
## mesh): if the orb floats where the creature should be but no model is seen,
## the problem is the mesh/animation; if the orb is under the floor, the body
## is buried. Either way the screenshot tells us which half to fix.

@export_group("Animations (from nightmare_creature_1.glb)")
@export var anim_idle: String = "Creature_armature|idle"
@export var anim_battle_idle: String = "Creature_armature|battle_idle"
@export var anim_walk: String = "Creature_armature|walk"
@export var anim_run: String = "Creature_armature|Run"
@export var anim_attack: String = "Creature_armature|attack_1"
@export var anim_bite: String = "Creature_armature|bite"
@export var anim_hit: String = "Creature_armature|hit_1"
@export var anim_roar: String = "Creature_armature|roar"
@export var anim_death: String = "Creature_armature|death_1"

@onready var _bt_player: BTPlayer = $BTPlayer
@onready var _roar: AudioStreamPlayer = $Roar
@onready var _growl: AudioStreamPlayer = $Growl
@onready var _step: AudioStreamPlayer = $Step
@onready var _screech: AudioStreamPlayer = $Screech
@onready var _beacon: MeshInstance3D = $DebugBeacon

var _anim: AnimationPlayer
var _anim_map: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _pan_fx: Array[AudioEffectPanner] = []

var _player: PlayerMovement
var _awake: bool = false
var _neutralized: bool = false
var _patrol_idx: int = 0
var _spawn_pos: Vector3 = Vector3.ZERO
var _alert_target: Vector3 = Vector3.ZERO   # investigation target (no blackboard)
var _has_alert: bool = false
var _want_move: bool = false
var _stuck_t: float = 0.0
# ROUND 6 movement/telemetry state:
#   _real_hspd = how far the body ACTUALLY travelled this physics step. R5 read
#                `velocity` AFTER move_and_slide(), which is the slide REMAINDER:
#                it is ~0 any time the body touches anything. That is why hspd
#                logged 0.00 in 307/307 samples while the body covered 10 m, why
#                `stuck` climbed to 273.47 s without ever resetting, and why
#                facing and footsteps (both gated on hspeed > 0.3) were dead.
#   _move_dir  = last COMMANDED horizontal direction, used for facing.
#   _task_tag  = which BT task owns us right now (the field R5 was missing).
var _real_hspd: float = 0.0
var _move_dir: Vector3 = Vector3.ZERO
var _task_tag: String = "-"
# ROUND 7 navigation / unstick / animation-sync state:
#   _nav         NavigationAgent3D, steers move_toward_point() along the baked path
#   _nav_target  last query target (re-query is throttled to ~5 Hz)
#   _pinned      commanded to move but not travelling -> substitute battle_idle
#                for walk/Run so the model never "walks into a wall"
#   _unstick_t   how long we have been pinned; > 0.6 s triggers _try_unstick()
#   _backoff_t   while > 0, move_toward_point() retreats instead of pushing in
var _nav: NavigationAgent3D
var _nav_target: Vector3 = Vector3.ZERO
var _nav_age: float = 999.0
var _pinned: bool = false
var _pinned_t: float = 0.0
var _unstick_t: float = 0.0
var _backoff_t: float = 0.0
var _backoff_dir: Vector3 = Vector3.ZERO
var _door_cd: float = 0.0
var _alert_cd: float = 0.0
# ROUND 8 state:
#   _nav_reachable  result of the last reachability query (drives give-up logic)
#   _nav_fail_t     how long the current target has been unreachable
#   _unstick_fails  consecutive unstick attempts without recovering; escalates
#                   backoff -> strafe -> abandon target, so a wedge can never
#                   become an infinite ping-pong (creature_log R7: 20+ UNSTICK
#                   lines at the same spot, alternating (-1.75,-15.68) and
#                   (-1.3,-15.1) forever)
#   _sweep_*        dwell "sniff" sweep instead of R7's continuous 2.5 rad/s spin
var _nav_reachable: bool = true
var _nav_fail_t: float = 0.0
var _unstick_fails: int = 0
var _unstick_clear_t: float = 0.0
var _sweep_t: float = 0.0
var _sweep_gap: float = 999.0
var _sweep_center: float = 0.0
# ROUND 9: fail-quiet navigation. _nav_dead latches once three give-ups happen
# with nav still unreachable, after which the creature stops querying nav and
# stops logging give-ups -- a dead mesh degrades to straight-line movement
# instead of an endless skip/churn loop (creature_log R8: 25 NAV GIVEUP lines
# in 136 s, which is what "a lot glitch" looked like in game).
var _nav_dead: bool = false
var _giveups: int = 0
var _giveup_cd: float = 0.0
# ROUND 11:
#   _amnesia_t  post-recover window in which sight AND hearing are ignored, so
#               "rises amnesiac and patrols" is actually true (creature_log R10:
#               it came up swinging the moment it stood). Being shot ends it.
#   _react_t    0.7 s stand-and-roar beat when combat first engages, so spotting
#               you is a telegraph instead of an instant sprint.
#   _was_combat / _noncombat_t  memory so the react beat fires only on a fresh
#               engagement, not on every chase<->swipe handoff.
var _amnesia_t: float = 0.0
var _react_t: float = 0.0
var _was_combat: bool = false
var _noncombat_t: float = 999.0
# ROUND 12:
#   _move_stamp/_move_stamp_prev  velocity watchdog (no command this frame -> stop)
#   _nav_dir/_nav_dir_t           last good path heading, held 0.4 s
var _move_stamp: int = 0
var _move_stamp_prev: int = -1
var _nav_dir: Vector3 = Vector3.ZERO
var _nav_dir_t: float = 999.0
# ROUND 13:
#   _nav_wp        waypoint polled once per PHYSICS frame (documented requirement;
#                  R12 only polled it on frames that ran a movement task)
#   _nav_goal/_nav_snapped  the query target after off-mesh snapping
#   _navs          diagnostic: 0 path ok, 1 waypoint ~ self, 2 snapped goal, 3 dead
#   _net_*/_jam_*  NET-PROGRESS jam detector: oscillating against a door frame or
#                  a pillar corner moves every frame (vreal ~= speed) but makes
#                  no progress; vreal-based detectors read that as "fine" forever
var _nav_wp: Vector3 = Vector3.ZERO
var _nav_goal: Vector3 = Vector3.ZERO
var _nav_snapped: bool = false
var _navs: int = 0
var _net_pos: Vector3 = Vector3.ZERO
var _net_t: float = 0.0
var _jam_t: float = 0.0
var _jammed: bool = false
var _map_bound: bool = false   # ROUND 14: agent attached to nav_baker's map yet?
var _baker: Node = null        # ROUND 15: cached nav_baker for is_ready()
var _nav_dead_probe_t: float = 0.0   # ROUND 15: re-probe cadence while latched
var _face_slow: float = 0.0    # ROUND 15: slow facing turn during backoff
# ROUND 16 (reference: bypell/horror-game-enemy-demo): one steering core.
#   _move_speed     speed requested by the current travel target
#   _travel_target  raw target (before nav snapping)
#   _nav_finished   is_navigation_finished() as of this physics frame
#   _eye_ray        physical line-of-sight ray (mask 17, player layer excluded)
#   _attack_anim_done  attack clip finished (windup completion signal)
var _move_speed: float = 0.0
var _travel_target: Vector3 = Vector3.ZERO
var _nav_finished: bool = false
var _eye_ray: RayCast3D = null
var _attack_anim_done: bool = true
var _coast_t: float = 0.0   # ROUND 17: seconds spent coasting through an async stall
var _diagmv_t: float = 0.0  # ROUND 21: cadence for the diagmove burst

var _windup_t: float = 0.0
var _winding: bool = false
var _attack_cd: float = 0.0
var _lunging: bool = false
var _lunge_t: float = 0.0
var _lunge_dir: Vector3 = Vector3.ZERO
var _lunge_hit: bool = false
var _lunge_cd: float = 0.0
var _step_t: float = 0.0
var health: float = 100.0

# Telemetry (fix round 5): file log survives crashes and gets pasted back to
# me verbatim; engine errors/warnings are captured into the same file.
var _logf: FileAccess
var _err_logger: CreatureErrorLogger
var _clamp_cd: float = 0.0
var _dbg_t: float = 0.0


## Engine error/warning capture (the debugger's mystery "Errors (2)" land in
## creature_log.txt). Godot 4.5+ API: subclass Logger, register via
## OS.add_logger(). Callbacks arrive on OTHER threads -> mutex + main-thread
## drain; never touch FileAccess from in here.
class CreatureErrorLogger extends Logger:
	var lines: Array[String] = []
	var mutex: Mutex = Mutex.new()

	func _log_message(message: String, error: bool) -> void:
		mutex.lock()
		lines.append(("ERR | " if error else "MSG | ") + message)
		mutex.unlock()

	func _log_error(fn: String, file: String, line: int, code: String,
			rationale: String, _editor_notify: bool, error_type: int,
			_script_backtraces: Array[ScriptBacktrace]) -> void:
		mutex.lock()
		lines.append("ENGINEERR[t%d] %s:%d in %s() %s %s" % [
			error_type, file, line, fn, code, rationale])
		mutex.unlock()

	func take_lines() -> Array[String]:
		mutex.lock()
		var out: Array[String] = lines.duplicate()
		lines.clear()
		mutex.unlock()
		return out


func _ready() -> void:
	# ROUND 16 (reference enemy.gd): do not move until the navigation map has
	# synchronised. Our startup window (deferred bake + retry) is exactly where
	# earlier rounds latched bogus nav-dead states.
	set_physics_process(false)
	await get_tree().physics_frame
	set_physics_process(true)
	health = max_health
	_spawn_pos = global_position
	add_to_group("creature")
	_anim = _find_anim(self)
	_build_anim_map()
	if patrol_points.is_empty():
		for i in range(4):
			var a: float = TAU * float(i) / 4.0
			patrol_points.append(_spawn_pos + Vector3(cos(a), 0.0, sin(a)) * auto_patrol_radius)
	_player = get_tree().get_first_node_in_group("player") as PlayerMovement
	Events.gun_fired.connect(_on_gun_fired)
	_voices = [_roar, _growl, _step, _screech]
	var bus_names: Array[String] = ["CreaRoar", "CreaGrowl", "CreaStep", "CreaScreech"]
	for i in range(_voices.size()):
		_voices[i].bus = StringName(bus_names[i])
		_pan_fx.append(AudioMgr.ensure_pan_bus(bus_names[i]))
	# LimboAI wiring: tree built in code; agent_node defaults to ".." (this node)
	# and must NOT be set after instantiation. Dormant until woken.
	_bt_player.behavior_tree = _build_tree()
	_bt_player.active = false
	# ROUND 7: pathfinding. The agent only needs to exist; the walkable mesh is
	# baked by scenes/level/nav_baker.gd in the level.
	_nav = NavigationAgent3D.new()
	_nav.name = "NavAgent"
	_net_pos = global_position
	_nav.path_desired_distance = 0.4
	_nav.target_desired_distance = 0.4
	_nav.path_max_distance = 6.0
	_nav.avoidance_enabled = false
	add_child(_nav)
	_try_bind_nav_map()
	# ROUND 16: physical eye ray for line of sight (reference EyeRayCast).
	# Mask 17 = world + doors; the player (layer 4) is NOT in the mask so the ray
	# passes through them and only geometry can block sight.
	_eye_ray = RayCast3D.new()
	_eye_ray.name = "EyeRay"
	_eye_ray.enabled = true
	_eye_ray.collision_mask = 17
	_eye_ray.position = Vector3(0.0, 1.5, 0.0)
	_eye_ray.target_position = Vector3(0.0, 0.0, 0.0)
	add_child(_eye_ray)
	if _anim != null:
		_anim.animation_finished.connect(_on_anim_finished)
	if _beacon != null:
		_beacon.visible = debug_beacon
	_logf = FileAccess.open(LOG_PATH, FileAccess.WRITE)   # truncate each run
	_log("=== spawn build=%s pos=%s patrol=%s" % [BUILD_TAG, str(global_position), str(patrol_points)])
	_err_logger = CreatureErrorLogger.new()
	OS.add_logger(_err_logger)
	# ROUND 6 self-test. R5 produced 0 ENGINE* lines in 309 s and there was no way
	# to tell whether that meant "no engine messages" or "the capture is not
	# wired" (_drain_engine_log() runs every physics frame, so the plumbing was
	# live -- the buffer was simply never filled). These two lines exercise BOTH
	# Logger virtuals: print() -> _log_message(), push_warning() -> _log_error().
	# Both must land in creature_log.txt within a second of launch. If either is
	# missing, engine errors are invisible to us and "no errors logged" must never
	# be read as "no errors".
	print("R6 SELFTEST _log_message path")
	push_warning("R6 SELFTEST _log_error path")


func _exit_tree() -> void:
	if _err_logger != null:
		_drain_engine_log()
		if OS.has_method("remove_logger"):
			OS.remove_logger(_err_logger)
		_err_logger = null
	_log("=== exit tree")
	if _logf != null:
		_logf.flush()
		_logf.close()
		_logf = null

func _try_bind_nav_map() -> void:
	if _map_bound:
		return
	_baker = get_tree().get_first_node_in_group("nav_baker")
	if _baker == null or not _baker.is_ready():
		return
	NavigationServer3D.agent_set_map(_nav.get_rid(), _baker.get_map_rid())
	_map_bound = true
	_log("NAV MAP BOUND to baker map")

## Telemetry line writer. Never crashes the game if the file is gone.
func _log(msg: String) -> void:
	if _logf == null:
		return
	_logf.store_line("%8d | %s" % [Time.get_ticks_msec(), msg])
	_logf.flush()


## Main-thread drain of the threaded engine-error buffer.
func _drain_engine_log() -> void:
	if _err_logger == null or _logf == null:
		return
	for l in _err_logger.take_lines():
		_log(l)


# ------------------------------------------------------------------------------
# Behavior tree construction (LimboAI classes, GDExtension)
# ------------------------------------------------------------------------------

## ============================================================================
## ROUND 6 -- THIS IS THE FIX.
##
## LimboAI's plain BTSelector/BTSequence REMEMBER the child that returned RUNNING
## and resume ONLY that child on subsequent ticks (documented behaviour -- see
## class_btselector / class_btsequence). ActChase returns RUNNING
## unconditionally, so the very first tick that reached it parked the whole tree
## there for the rest of the session:
##   * combat_sel never re-tested CondInSwipeRange / CondCanLunge -> never attacks.
##     (R5 log: dist pinned at 0.76 m, inside swipe_range 1.9 m, for 276 s;
##      anim=Run in 274/274 awake samples; zero WINDUP / SWIPE HIT / LUNGE lines.)
##   * seq_combat never re-tested CondSeesPlayer -> a chase could never end.
##   * root never re-tested CondNeutralized -> ActRecover could never run, so it
##     never rose again and never went back to patrol.
##   * the latched ActChase kept calling play_anim(anim_run) every tick, which
##     overwrote death_1 the instant you neutralized it -> "plays a sound then
##     gets stuck in the walking animation at the same place, does not respawn".
##
## BTDynamicSelector / BTDynamicSequence re-execute their PRECEDING children every
## tick and abort() the remembered RUNNING child when a higher-priority branch
## goes live. That is precisely the case they exist for.
## ============================================================================
func _build_tree() -> BehaviorTree:
	var bt := BehaviorTree.new()
	var root := BTDynamicSelector.new()
	bt.set_root_task(root)   # LimboAI 1.8 API: no `root` property; use set_root_task()

	var seq_recover := BTDynamicSequence.new()
	seq_recover.add_child(CondNeutralized.new())
	seq_recover.add_child(ActRecover.new())
	root.add_child(seq_recover)

	var seq_combat := BTDynamicSequence.new()
	seq_combat.add_child(CondSeesPlayer.new())
	var combat_sel := BTDynamicSelector.new()
	var seq_swipe := BTDynamicSequence.new()
	seq_swipe.add_child(CondInSwipeRange.new())
	seq_swipe.add_child(ActSwipe.new())
	var seq_lunge := BTDynamicSequence.new()
	seq_lunge.add_child(CondCanLunge.new())
	seq_lunge.add_child(ActLunge.new())
	combat_sel.add_child(seq_swipe)
	combat_sel.add_child(seq_lunge)
	combat_sel.add_child(ActChase.new())
	seq_combat.add_child(combat_sel)
	root.add_child(seq_combat)

	# seq_hear stays a PLAIN BTSequence on purpose: ActSetAlert returns SUCCESS in
	# the same tick, so nothing can latch here, and a dynamic composite would only
	# cost ticks.
	var seq_hear := BTSequence.new()
	seq_hear.add_child(CondHearsPlayer.new())
	seq_hear.add_child(ActSetAlert.new())
	root.add_child(seq_hear)

	var seq_inv := BTDynamicSequence.new()
	seq_inv.add_child(CondHasAlert.new())
	seq_inv.add_child(ActInvestigate.new())
	root.add_child(seq_inv)

	root.add_child(ActPatrol.new())
	return bt


# ------------------------------------------------------------------------------
# Wake / damage / neutralize (design rules)
# ------------------------------------------------------------------------------

func _on_gun_fired(pos: Vector3) -> void:
	if global_position.distance_to(pos) > gunshot_hear_range:
		return
	if _neutralized:
		return
	if not _awake:
		_wake(pos)
	else:
		set_alert(pos, true)


func _wake(pos: Vector3) -> void:
	_awake = true
	_roar.play()
	set_alert(pos, true)
	_bt_player.active = true
	_log("WAKE at %s (player %s)" % [str(global_position), str(pos)])


## Investigation-target API (used by tasks instead of a blackboard).
func has_alert() -> bool:
	return _has_alert


func get_alert_target() -> Vector3:
	return _alert_target


func set_alert(pos: Vector3, force: bool = false) -> void:
	# ROUND 7: hearing re-stamped a fresh target on every noisy tick, which kept
	# ActInvestigate alive for 77% of the R6 run (190/248 samples). Near-duplicate
	# re-stamps are now debounced; gunshots and the wake call pass force=true.
	if not force and _has_alert and _alert_cd > 0.0 \
			and pos.distance_to(_alert_target) < 4.0:
		return
	_alert_cd = 3.0   # ROUND 19: was 1.5 -- hearing re-stamped every 1.5 s while
					  # you moved, so investigate never completed (74 s runs)
	_alert_target = pos
	_has_alert = true


func clear_alert() -> void:
	_has_alert = false


func take_damage(amount: float, push_dir: Vector3) -> void:
	if _neutralized:
		return
	if not _awake:
		_wake(_player.global_position if _player != null else global_position)
	health -= amount
	_amnesia_t = 0.0          # ROUND 11: being shot ends the amnesia window
	_screech.play()
	_log("DAMAGE %.1f -> hp %.1f at %s" % [amount, health, str(global_position)])
	# Horizontal-only shove: pushing along the pellet direction (which often
	# points DOWN) drove the creature into the floor slab and stuck it there.
	position += Vector3(push_dir.x, 0.0, push_dir.z).normalized() * 0.25
	# DESIGN RULE (user): shooting NEUTRALIZES it for neutralize_time seconds
	# (escape window), then it rises at full health and patrols amnesiac.
	# It is never permanently killable.
	if not _neutralized:
		_neutralized = true
		# ROUND 6: kill any in-flight telegraph. A dynamic composite abort()s
		# ActSwipe/ActLunge the moment this fires; without these clears, _winding
		# stays true, the play_anim guard freezes the model on attack_1, and the
		# leftover _windup_t fires a phantom swipe after recover().
		_winding = false
		_windup_t = 0.0
		_lunging = false
		_lunge_t = 0.0
		_task_tag = "-"
		stop_move()
		_play_anim_raw(anim_death)   # must WIN over any task: bypasses the guard
		_screech.play()
		_log("NEUTRALIZED for %.1fs" % neutralize_time)


func is_neutralized() -> bool:
	return _neutralized


## ROUND 16 (reference state_searching): a walkable point near `around`, used
## for the search-point routine after reaching a last-known position.
func search_point_near(around: Vector3, radius: float) -> Vector3:
	if _nav == null:
		return around
	var map: RID = _nav.get_navigation_map()
	for i in range(8):   # more attempts, last resort is the alert target itself
		var a: float = randf() * TAU
		var r: float = radius * sqrt(randf())
		var candidate: Vector3 = around + Vector3(cos(a), 0.0, sin(a)) * r
		var snapped: Vector3 = NavigationServer3D.map_get_closest_point(map, candidate)
		# Reject if: snapped to origin (unbound map), or snap moved it >1.5m (inside wall)
		if snapped.length_squared() < 0.01:
			continue
		if snapped.distance_to(candidate) > 1.5:
			continue
		if snapped.distance_to(global_position) > 1.0:
			return snapped
	return around   # give up: stay at the alert target and dwell there


## ROUND 15: pick the locomotion clip by ACTUAL speed. The glide/moonwalk look
## came from a walk cycle playing at investigate speed (3.45 m/s) and from clips
## whose stride never matched ground speed; speed_scale below then matches stride.
func play_gait(speed: float) -> void:
	play_anim(anim_run if speed > walk_speed * 1.25 else anim_walk)


## ROUND 11: true for 5 s after recover(); CondSeesPlayer and CondHearsPlayer
## refuse to fire while this holds, so a risen creature genuinely re-patrols.
func is_amnesiac() -> bool:
	return _amnesia_t > 0.0


## Called by CondSeesPlayer the tick combat (re-)engages.
func note_combat_start() -> void:
	if not _was_combat:
		_react_t = 0.7
		_was_combat = true


func forget_player() -> void:
	_amnesia_t = 5.0
	_react_t = 0.0


func recover() -> void:
	_neutralized = false
	# ROUND 6: never carry combat state (or a stale stuck flag) into the next life.
	_winding = false
	_windup_t = 0.0
	_lunging = false
	_lunge_t = 0.0
	_lunge_hit = false
	_attack_cd = 0.0
	_lunge_cd = 0.0
	_stuck_t = 0.0
	_task_tag = "-"
	health = max_health
	_patrol_idx = 0
	clear_alert()
	forget_player()           # ROUND 11: 5 s of genuine amnesia
	_roar.play()
	_log("RECOVER at %s (amnesiac patrol)" % str(global_position))


# ------------------------------------------------------------------------------
# Senses (used by conditions)
# ------------------------------------------------------------------------------

func player_pos() -> Vector3:
	if _player == null:
		return global_position
	return _player.global_position


func dist_to_player() -> float:
	var d: Vector3 = player_pos() - global_position
	d.y = 0.0
	return d.length()


func sees_player(check_fov: bool = true) -> bool:
	if _player == null:
		return false
	var to_p: Vector3 = _player.global_position - global_position
	var dist: float = to_p.length()
	if dist > sight_range:
		return false
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	var flat: Vector3 = to_p.normalized()
	flat.y = 0.0
	if fwd.length_squared() < 0.001 or flat.length_squared() < 0.001:
		return false
	if check_fov and rad_to_deg(fwd.normalized().angle_to(flat.normalized())) > sight_fov_deg * 0.5:
		return false
	# ROUND 16: physical eye ray (reference EyeRayCast) replaces the inline
	# intersect_ray. Same rules as R12: mask 17 so CLOSED doors block sight and
	# other creatures do not; the player's own layer is excluded so the ray can
	# pass through them to the geometry behind.
	if _eye_ray == null:
		return true
	_eye_ray.target_position = _eye_ray.to_local(
			_player.global_position + Vector3(0.0, 1.0, 0.0))
	_eye_ray.force_raycast_update()
	return not _eye_ray.is_colliding()


func hears_player() -> bool:
	if _player == null:
		return false
	var noise: float = _player.noise_level
	return noise > 0.05 and dist_to_player() < hear_radius * noise


# ------------------------------------------------------------------------------
# Movement helpers (used by actions)
# ------------------------------------------------------------------------------

## Returns true when arrived within `arrive` metres.
## ROUND 6: `arrive` is a parameter. It was hardcoded to 0.7 m -- BELOW the 0.75 m
## capsule-contact distance -- so a chase targeting the player could literally
## never report "arrived": permanent deadlock, always commanded to move, never
## able to. Also records the commanded direction, because the post-slide
## `velocity` cannot be used for facing (atan2 of a zeroed vector is always 0,
## which is why the creature never turned to face you in R5).
func move_toward_point(target: Vector3, speed: float, arrive: float = 0.7) -> bool:
	# ROUND 16: tasks no longer write velocity. They declare a travel target and
	# a speed; the steering core in _physics_process owns velocity (reference
	# enemy.gd: one writer, from the current path waypoint, every frame).
	var to_t: Vector3 = target - global_position
	to_t.y = 0.0
	# ROUND 8 personal space: stop short of capsule contact when the destination
	# is the player (0.4 + 0.35 = 0.75).
	if _player != null and target.distance_to(player_pos()) < 1.0:
		arrive = maxf(arrive, 0.95)
	if to_t.length() < arrive:
		stop_move()
		return true
	if _react_t > 0.0:
		stop_move()
		return true
	# ROUND 16 arrival, reference test: the path being FINISHED near the (possibly
	# snapped) goal counts as arrived. This is what makes impossible targets
	# (inside solid geometry) degrade to "stop here" instead of a permanent grind.
	if _want_move and _nav_finished and (_nav_goal - global_position).length() < 1.0:
		stop_move()
		return true
	_want_move = true
	_move_speed = speed
	_travel_target = target
	_move_stamp += 1
	if _backoff_t > 0.0:
		# ROUND 18: backoff writes its own velocity now that tasks own velocity.
		var bd: Vector3 = _backoff_dir.normalized()
		_move_dir = bd
		_face_slow = 0.6
		velocity.x = bd.x * walk_speed
		velocity.z = bd.z * walk_speed
		return false
	if _nav_dead:
		# ROUND 15: a dead latch must not blind itself; re-probe once a second.
		_nav_reachable = false
		_navs = 3
		_nav_dead_probe_t += get_physics_process_delta_time()
		if _nav_dead_probe_t > 1.0:
			_nav_dead_probe_t = 0.0
			if _nav != null and _nav.is_target_reachable():
				_nav_dead = false
				_giveups = 0
				_nav_fail_t = 0.0
				_log("NAV RECOVERED at %s" % str(global_position))
		return false
	# ROUND 20: retarget EVERY call (once per physics frame), exactly like the
	# reference's update_path_delay = 0. The 10 Hz throttle left the path stale
	# for 1-3 frames after each retarget, and R19's follow-or-stop STOPPED on
	# those frames: vcmd=0 in 77% of awake samples (creature_log R19) -- the
	# R16/R17 crawl reintroduced by my own hand. One agent repathing per frame
	# is cheap; the throttle was a cost fear that never applied here.
	_nav_target = target
	var tgt: Vector3 = target
	if not _nav.is_target_reachable():
		var snap: Vector3 = NavigationServer3D.map_get_closest_point(
				_nav.get_navigation_map(), target)
		if snap.distance_squared_to(target) < 9.0:
			tgt = snap
	_nav_goal = tgt
	_nav_snapped = tgt.distance_squared_to(target) > 0.01
	_nav.target_position = tgt
	_nav_reachable = not _nav_snapped
	_navs = 2 if _nav_snapped else 0
	# ROUND 21: R18's proven mover, VERBATIM (vcmd=0 in 12% of awake samples,
	# the only healthy measurement in four rounds). Priority:
	#   1. the nav path waypoint (corners, doorways),
	#   2. straight line if the lane is physically clear (no world/door in 3 m),
	#   3. the held heading while a path settles,
	#   4. straight line.
	# Per-frame retarget (R20) stays above; no follow-or-stop, no coast.
	var dir: Vector3
	if _nav_dead:
		dir = to_t.normalized()
	else:
		var raw: Vector3 = _nav_wp - global_position
		raw.y = 0.0
		if raw.length_squared() > 0.0004:
			dir = raw.normalized()
		elif clear_path(to_t.normalized(), minf(to_t.length(), 3.0)):
			dir = to_t.normalized()
		elif _nav_dir.length_squared() > 0.001:
			dir = _nav_dir
		else:
			dir = to_t.normalized()
	_move_dir = dir
	_nav_dir = dir
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	return false


func clear_path(dir: Vector3, dist: float) -> bool:
	var world: World3D = get_world_3d()
	if world == null or world.direct_space_state == null:
		return true
	var from: Vector3 = global_position + Vector3(0.0, 0.7, 0.0)
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			from, from + dir * dist)
	q.exclude = [get_rid()]
	q.collision_mask = 17
	return world.direct_space_state.intersect_ray(q).is_empty()


## What is directly in front of us, within `dist` metres (world geometry only).
func _forward_collider(dist: float) -> Node:
	var world: World3D = get_world_3d()
	if world == null or world.direct_space_state == null:
		return null
	var fwd: Vector3 = _move_dir.normalized() \
			if _move_dir.length_squared() > 0.001 else -global_transform.basis.z
	var from: Vector3 = global_position + Vector3(0.0, 0.7, 0.0)
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			from, from + fwd * dist)
	q.exclude = [get_rid()]
	q.collision_mask = 17        # ROUND 12: doors count as blockers here too, or
								 # unstick can never find a door to force_open()
	var hit: Dictionary = world.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	return hit.get("collider") as Node


## ROUND 7 stuck recovery for EVERY task (R5 only had patrol's point-skip).
## If we are pinned, first try to open whatever door is in front of us; if it is
## not a door, back off for half a second and force a fresh path query.
func _try_unstick() -> void:
	_unstick_fails += 1
	if _door_cd <= 0.0:
		var hit: Node = _forward_collider(1.4)
		var door: Node = hit
		while door != null:
			if door.has_method("force_open"):
				door.call("force_open")
				_door_cd = 4.0
				_log("DOOR OPEN vs %s at %s" % [door.name, str(global_position)])
				return
			door = door.get_parent()
	_nav_age = 999.0                # force a fresh nav query on the next tick
	# Escalation ladder. R7 always backed straight off, then re-approached the
	# same wedge: an infinite ping-pong at one spot.
	if _unstick_fails >= 4:
		# Give up on the current target entirely.
		_unstick_fails = 0
		if _task_tag == "ActInvestigate" and _has_alert:
			clear_alert()
		elif _task_tag == "ActPatrol":
			next_patrol_point()
			clear_stuck()
		_log("UNSTICK GIVEUP at %s task=%s" % [str(global_position), _task_tag])
		return
	if _unstick_fails >= 2:
		# Strafe perpendicular instead of backing off.
		var md: Vector3 = _move_dir.normalized() if _move_dir.length_squared() > 0.001 \
				else Vector3(1.0, 0.0, 0.0)
		_backoff_dir = Vector3(-md.z, 0.0, md.x) if _unstick_fails == 2 \
				else Vector3(md.z, 0.0, -md.x)
		_log("UNSTICK strafe%d at %s task=%s" % [_unstick_fails, str(global_position), _task_tag])
	else:
		_backoff_dir = -_move_dir if _move_dir.length_squared() > 0.001 else Vector3(0.0, 0.0, 1.0)
		_log("UNSTICK backoff at %s task=%s" % [str(global_position), _task_tag])
	_backoff_t = 0.45


func stop_move() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_want_move = false
	_move_stamp += 1


## True when we've been commanded to move but barely moved for >1 s
## (patrol point inside a wall, cornered, etc.).
func is_stuck() -> bool:
	return _stuck_t > 1.0


## Called by ActPatrol when it skips a blocked point; without this the stuck
## flag stays hot and chain-skips every remaining point in consecutive ticks.
func clear_stuck() -> void:
	_stuck_t = 0.0


## ---------------------------------------------------------------------------
## ROUND 6 API used by the BT tasks
## ---------------------------------------------------------------------------

## Telemetry: every BTAction stamps its name here on tick. `task=` in the log and
## on the F2 panel is the field that would have exposed the ActChase latch in
## round 1 instead of round 6.
func set_task_tag(t: String) -> void:
	_task_tag = t


func task_tag() -> String:
	return _task_tag


func is_winding() -> bool:
	return _winding


## Swipe gate. R5 never checked _attack_cd anywhere, so once the tree latch is
## removed the creature would swing every windup_time (0.55 s) instead of every
## swipe_cooldown (1.6 s).
func attack_ready() -> bool:
	return _attack_cd <= 0.0 and not _winding and not _lunging


## Called from ActSwipe._exit() when a dynamic composite aborts the telegraph.
func cancel_windup() -> void:
	_winding = false
	_windup_t = 0.0


## Called from ActLunge._exit() when a dynamic composite aborts the dash.
func cancel_lunge() -> void:
	_lunging = false
	_lunge_t = 0.0
	_lunge_hit = false
	_lunge_cd = lunge_cooldown   # an interrupted lunge must not be free


## Anti-burial ground clamp (round 5). Down-ray from just above the capsule
## centre: if the first ground hit is ABOVE the centre, the body is inside a
## slab -> pop it back on top. Cures "creature haunts the floor from below"
## whatever pushed it in (depenetration, lunge off a lip, teleport edge case).
func _clamp_to_ground() -> void:
	_clamp_cd = maxf(0.0, _clamp_cd - get_physics_process_delta_time())
	var world: World3D = get_world_3d()
	if world == null or world.direct_space_state == null:
		return
	var from: Vector3 = global_position + Vector3(0.0, 0.6, 0.0)
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, from + Vector3(0.0, -4.0, 0.0))
	q.exclude = [get_rid()]
	# ROUND 6, MANDATORY: world geometry only. The default mask is ALL layers, and
	# now that the creature and the player can occupy the same space this down-ray
	# can hit the PLAYER capsule below y=0.6 -> gp.y > pos.y + 0.05 -> the clamp
	# teleports the creature to gp.y + 0.9 (~1.5 m in the air). The R5 anti-burial
	# clamp would have become a launch pad.
	q.collision_mask = 1
	var hit: Dictionary = world.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var gp: Vector3 = hit["position"]
	if gp.y > global_position.y + 0.05:          # centre below the surface
		var was: float = global_position.y
		global_position.y = gp.y + 0.9           # capsule half-height
		velocity.y = 0.0
		if _clamp_cd <= 0.0:
			_log("GROUND CLAMP y %.2f -> %.2f (ground %.2f)" % [was, global_position.y, gp.y])
			_clamp_cd = 2.0


## One-stop snapshot for the debug panel (F2). Never allocates heavy stuff.
func debug_state() -> Dictionary:
	var aname: String = String(_anim.current_animation) if _anim != null else "-"
	return {
		"tag": BUILD_TAG,
		"pos": global_position,
		"awake": _awake,
		"neutralized": _neutralized,
		"dist": dist_to_player(),
		"sees": sees_player(),
		"hears": hears_player(),
		"anim": aname,
		"stuck": _stuck_t,
		"hp": health,
		"task": _task_tag,     # ROUND 6: which BT task owns the creature
		"vreal": _real_hspd,   # ROUND 6: actual travel speed, m/s
	}


## ROUND 8: the dwell "sniff" is a +-63 degree SWEEP around the arrival facing.
## R7 added 2.5 rad/s continuously, i.e. a full 360 every 2.5 s for as long as
## the dwell lasted -- exactly the "going literal 360 during ActInvestigate" bug.
func turn_slow(delta: float) -> void:
	if _sweep_gap > 0.3:
		_sweep_center = rotation.y
		_sweep_t = 0.0
	_sweep_gap = 0.0
	_sweep_t += delta
	rotation.y = _sweep_center + sin(_sweep_t * 1.3) * 1.1


func current_patrol_point() -> Vector3:
	if patrol_points.is_empty():
		return _spawn_pos
	return patrol_points[_patrol_idx]


func next_patrol_point() -> void:
	_patrol_idx = (_patrol_idx + 1) % patrol_points.size()


# ------------------------------------------------------------------------------
# Combat resolution (used by swipe/lunge tasks)
# ------------------------------------------------------------------------------

func lunge_ready() -> bool:
	return _lunge_cd <= 0.0


func start_windup() -> void:
	_windup_t = 0.0
	_winding = true
	stop_move()
	_play_anim_raw(anim_attack)   # agent-owned pose: must bypass the play_anim guard
	_attack_anim_done = false    # ROUND 16: windup ends with the clip, not a guess
	_growl.play()
	_log("WINDUP dist=%.2f" % dist_to_player())


func windup_done() -> bool:
	# ROUND 16 (reference awaits animation_finished): the swipe lands when the
	# attack clip finishes, so anim and hit can never desync. The 2x timeout is
	# only a safety net if the clip is missing.
	return _attack_anim_done or _windup_t >= windup_time * 2.0


func _on_anim_finished(name: StringName) -> void:
	if _anim != null and name == _resolve(anim_attack):
		_attack_anim_done = true


func do_swipe() -> void:
	_winding = false
	if _player != null and dist_to_player() < swipe_range * 1.25:
		var dir: Vector3 = (player_pos() - global_position).normalized()
		Events.player_damaged.emit(swipe_damage, dir)
		_player.apply_knockback(dir, knockback_force * 0.6)
		_growl.play()
		_log("SWIPE HIT dist=%.2f" % dist_to_player())
	_attack_cd = swipe_cooldown


func start_lunge() -> void:
	_lunge_dir = player_pos() - global_position
	_lunge_dir.y = 0.0
	if _lunge_dir.length_squared() > 0.001:
		_lunge_dir = _lunge_dir.normalized()
	_lunge_t = 0.0
	_lunge_hit = false
	_lunging = true
	_play_anim_raw(anim_bite)     # agent-owned pose: must bypass the play_anim guard
	_roar.play()
	_log("LUNGE START dist=%.2f" % dist_to_player())


func lunge_done() -> bool:
	return not _lunging


# ------------------------------------------------------------------------------
# Frame update: physics, combat timers, facing, footsteps, audio, animation utils
# ------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as PlayerMovement
	_drain_engine_log()
	if global_position.y < -5.0 or global_position.y < void_y:
		# Sank into/through geometry (old knockback bug, lunge off a lip...):
		# pull back to spawn instead of haunting the floor slab forever.
		_log("VOID RESET from y=%.2f" % global_position.y)
		global_position = _spawn_pos
		velocity = Vector3.ZERO
		_neutralized = false
		_winding = false
		_lunging = false
	if not _awake and not _neutralized and _player != null \
			and dist_to_player() < proximity_range:
		_wake(player_pos())   # design rule: point-blank proximity wakes it
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_lunge_cd = maxf(0.0, _lunge_cd - delta)

	if _neutralized:
		stop_move()
		velocity = Vector3.ZERO     # frozen while down: no gravity, no sliding,
	elif not _awake:                # so the corpse can never sink into a slab
		stop_move()
		_play_anim_raw(anim_idle)
	else:
		if _winding:
			_windup_t += delta
		if _lunging:
			_lunge_t += delta
			velocity.x = _lunge_dir.x * lunge_speed
			velocity.z = _lunge_dir.z * lunge_speed
			if not _lunge_hit and _player != null and dist_to_player() < 1.7:
				_lunge_hit = true
				var dir: Vector3 = (player_pos() - global_position).normalized()
				Events.player_damaged.emit(lunge_damage, dir)
				_player.apply_knockback(dir, knockback_force)
				_growl.play()
				_log("LUNGE HIT dist=%.2f" % dist_to_player())
			if _lunge_t >= lunge_time:
				_lunging = false
				_lunge_cd = lunge_cooldown

	# ROUND 6: capture the COMMANDED speed before the slide, then measure how far
	# the body actually travelled. `velocity` after move_and_slide() is the slide
	# remainder and reads ~0 whenever the body touches anything.
	var vcmd: float = Vector2(velocity.x, velocity.z).length()
	var prev_pos: Vector3 = global_position
	if not _neutralized:
		velocity.y = maxf(velocity.y - gravity * delta, -40.0)
		move_and_slide()
	_clamp_to_ground()
	if _neutralized:
		_real_hspd = 0.0
	else:
		var disp: Vector3 = global_position - prev_pos
		_real_hspd = Vector2(disp.x, disp.z).length() / maxf(delta, 0.0001)
	# ROUND 21 diagnostic burst: commanded but not moving -> say exactly what the
	# movers see, once per second. Four rounds of guessing from 1 Hz positions
	# end here: this line names velocity, vcmd, nav_finished, snapped, goal,
	# waypoint, position and task in one place.
	if _want_move and not _neutralized and _real_hspd < 0.1:
		_diagmv_t += delta
		if _diagmv_t >= 1.0:
			_diagmv_t = 0.0
			_log("diagmove v=(%.2f,%.2f) vcmd=%.2f want=1 fin=%d snap=%d goal=(%.1f,%.1f) wp=(%.1f,%.1f) at=(%.2f,%.2f) task=%s" % [
				velocity.x, velocity.z, vcmd,
				1 if _nav_finished else 0, 1 if _nav_snapped else 0,
				_nav_goal.x, _nav_goal.z, _nav_wp.x, _nav_wp.z,
				global_position.x, global_position.z, _task_tag])
	else:
		_diagmv_t = 0.0
	# ROUND 12 velocity watchdog: if NO task touched movement this frame and we
	# are not lunging/winding, nothing owns `velocity` -- zero it. Earlier rounds
	# let the last heading survive forever whenever a frame ran no movement task
	# (the 50 s straight-line slide in creature_log R8/R10).
	if not _lunging and not _winding and not _neutralized:
		if _move_stamp == _move_stamp_prev:
			velocity.x = 0.0
			velocity.z = 0.0
		_move_stamp_prev = _move_stamp
	# ROUND 13: poll the navigation agent EVERY physics frame. Its docs require
	# get_next_path_position() once per frame or the internal path index stalls;
	# frames owned by swipe/lunge/set-alert never called it in R12, so the path
	# went stale and navr flickered 0 across whole chase episodes.
	# ROUND 14: put our agent on nav_baker's dedicated map (the region lives on
	# it; an agent left on the default map queries a different, coarser grid and
	# sees the doorway-strip problem even after the mesh is fine).
	if not _map_bound:
		_try_bind_nav_map()
	# ROUND 18: physics only POLLS the agent. The R16/R17 steering core that wrote
	# velocity from the waypoint stalled on asynchronous path answers for two
	# rounds (vcmd=0 in 61% then 72% of awake samples). Velocity is written at
	# task time again, in move_toward_point(), from the freshest heading.
	if _nav != null and not _nav_dead and _awake and not _neutralized:
		_nav_wp = _nav.get_next_path_position()
		_nav_finished = _nav.is_navigation_finished() \
				and (_nav_goal - global_position).length() < 1.0
	_nav_dir_t += delta
	# ROUND 17: 1.0 s cadence, and windows containing a backoff or a coast are
	# ignored. R13's 0.5 s window read every async stall AND every backoff retreat
	# as "no progress", so the ladder fired every ~1.07 s forever (171 UNSTICK
	# lines in creature_log R16, many while moving at 2.2 m/s): advance 1 m,
	# retreat 1 m, repeat. A jam now needs 1.5 s of genuine standstill.
	_net_t += delta
	if _net_t >= 1.0:
		var net: Vector3 = global_position - _net_pos
		net.y = 0.0
		var progress: float = net.length() / _net_t
		if _want_move and not _neutralized and _backoff_t <= 0.0 \
				and _coast_t <= 0.0 and progress < 0.2:
			_jam_t += _net_t
		else:
			_jam_t = 0.0
		_jammed = _jam_t > 1.5
		_net_pos = global_position
		_net_t = 0.0

	# ROUND 13: a JAM (oscillating in place) counts as stuck/pinned even though
	# per-frame speed looks healthy -- that blind spot is what let the creature
	# grind Door2's frame and Pillar1's corner for 30 s at a time.
	if _want_move and not _nav_finished and (_real_hspd < 0.2 or _jammed):
		_stuck_t += delta
	else:
		_stuck_t = 0.0
	# ROUND 7: pinned detection. Commanded but not travelling -> the model swaps
	# to battle_idle (see play_anim) and, after 0.6 s, we try to unstick.
	if _want_move and not _nav_finished and (_real_hspd < 0.1 or _jammed):
		_pinned_t += delta
	else:
		_pinned_t = 0.0
	# ROUND 10: 0.8 s instead of 0.5 s. Cornering along a nav path briefly drops
	# the real speed; at 0.5 s that flicked walk -> battle_idle -> walk every
	# couple of seconds (the "switching states" look).
	_pinned = _pinned_t > 0.8          # R8: 0.35 flickered anims during unstick cycles
	_unstick_t = _unstick_t + delta \
			if (_want_move and not _nav_finished and _backoff_t <= 0.0 and (_real_hspd < 0.2 or _jammed)) else 0.0
	if _unstick_t > 0.9:
		_unstick_t = 0.0
		_try_unstick()
	# R8: recover -> reset the escalation ladder.
	_unstick_clear_t = _unstick_clear_t + delta if not _pinned else 0.0
	if _unstick_clear_t > 1.5:
		_unstick_fails = 0
	# R8: a target nav calls unreachable for >2 s is abandoned instead of ground
	# at in a straight line. For investigate this is what ended the R7 loop of
	# "stays in one place bugging out without patrolling".
	# ROUND 15: only count nav failures once the baker has a baked mesh. R14's
	# ladder counted the startup window (degenerate first bake + retry) and
	# latched _nav_dead for the whole run -- 81 navs=3 diag lines and 60 unsticks
	# in creature_log R14 while the mesh was actually fine (NAVPROBE pts=9).
	var baker_ok: bool = _baker != null and _baker.is_ready()
	if _awake and not _neutralized and _want_move and not _nav_reachable and baker_ok:
		_nav_fail_t += delta
	else:
		_nav_fail_t = 0.0
		_giveups = 0                    # nav worked again: reset the ladder
	# ROUND 9 fail-quiet: at most one give-up per 6 s, and three give-ups with nav
	# still unreachable declares the mesh dead exactly once.
	if _awake and not _neutralized and not _nav_dead and _want_move \
			and _nav_fail_t > 2.0 and _giveup_cd <= 0.0:
		_nav_fail_t = 0.0
		_giveup_cd = 6.0
		_giveups += 1
		if _task_tag == "ActInvestigate" and _has_alert:
			clear_alert()
			_log("NAV GIVEUP investigate at %s" % str(global_position))
		elif _task_tag == "ActPatrol":
			next_patrol_point()
			clear_stuck()
			_log("NAV GIVEUP patrol point at %s" % str(global_position))
		if _giveups >= 3 and not _nav_reachable:
			_nav_dead = true
			_log("NAV MESH DEAD at %s -- straight-line fallback for this session"
					% str(global_position))
	_giveup_cd = maxf(0.0, _giveup_cd - delta)
	_amnesia_t = maxf(0.0, _amnesia_t - delta)
	_react_t = maxf(0.0, _react_t - delta)
	if _task_tag == "ActChase" or _task_tag == "ActSwipe" or _task_tag == "ActLunge":
		_noncombat_t = 0.0
	else:
		_noncombat_t += delta
	if _noncombat_t > 2.0:
		_was_combat = false
	_sweep_gap += delta
	# ROUND 8 depenetration: resolve any overlap with the player the frame after
	# it happens (mostly post-lunge). Without this the creature could sit inside
	# your capsule, since its mask deliberately ignores the player layer.
	if not _lunging and _player != null:
		var away: Vector3 = global_position - player_pos()
		away.y = 0.0
		var ov: float = away.length()
		if ov < 1.05:      # ROUND 19: was 0.78 -- the head (forward ~0.35) still
			if ov < 0.0001:  # reached your camera. 1.05 keeps it ~1 m off you.
				away = Vector3(1.0, 0.0, 0.0)
				ov = 0.0
			global_position += away.normalized() * (1.05 - ov)
	_backoff_t = maxf(0.0, _backoff_t - delta)
	_door_cd = maxf(0.0, _door_cd - delta)
	_alert_cd = maxf(0.0, _alert_cd - delta)
	# ROUND 7 animation sync: scale the locomotion loop to the measured ground
	# speed so the feet match the movement (and the footstep cadence below
	# follows the same scale).
	if _anim != null:
		var nominal: float = run_speed if _anim.current_animation == _resolve(anim_run) \
				else walk_speed
		if _real_hspd > 0.05 and not _pinned:
			_anim.speed_scale = clampf(_real_hspd / maxf(nominal, 0.1), 0.55, 1.45)
		else:
			_anim.speed_scale = 1.0
	# Facing uses the COMMANDED direction. R5 used atan2() of the post-slide
	# velocity, which is (0,0) while blocked -> atan2(0,0) == 0 -> the creature
	# never turned to face anything.
	if not _neutralized and _awake and _want_move \
			and _move_dir.length_squared() > 0.000001:
		var desired: float = atan2(_move_dir.x, _move_dir.z)
		_face_slow = maxf(0.0, _face_slow - delta)
		var rate: float = 4.0 if _face_slow > 0.0 else 10.0
		rotation.y = lerp_angle(rotation.y, desired, 1.0 - exp(-rate * delta))
	# Footsteps ONLY while commanded to walk, awake, on the floor and actually
	# travelling (R5 gated this on the broken hspeed, so the chase went silent).
	if not _neutralized and _awake and _want_move and is_on_floor() and _real_hspd > 0.3:
		_step_t -= delta
		if _step_t <= 0.0:
			_step.play()
			_step.pitch_scale = randf_range(0.9, 1.1)
			# Run cadence only when actually running; walk gets 0.6 s so the
			# clip (0.45 s) always finishes before the next step.
			_step_t = (0.38 if _real_hspd > walk_speed * 1.4 else 0.6) / maxf(_anim.speed_scale, 0.55)
	_dbg_t -= delta
	if _dbg_t <= 0.0:
		_dbg_t = 1.0
		var aname: String = String(_anim.current_animation) if _anim != null else "-"
		_log("state awake=%s neu=%s pos=(%.2f,%.2f,%.2f) vcmd=%.2f vreal=%.2f onfl=%s stuck=%.2f task=%s anim=%s dist=%.2f ppos=(%.1f,%.1f) pin=%d navr=%d" % [
			str(_awake), str(_neutralized),
			global_position.x, global_position.y, global_position.z,
			vcmd, _real_hspd, str(is_on_floor()), _stuck_t, _task_tag, aname,
			dist_to_player(), player_pos().x, player_pos().z,
			1 if _pinned else 0,
			1 if _nav_reachable else 0])
		# ROUND 13: extra line only when something is wrong, so a jam explains
		# itself in one line instead of flooding the log. (Also drops the
		# redundant once-per-second is_target_reachable() query R11 left here.)
		if _jammed or _navs != 0:
			_log("diag jam=%d navs=%d snapped=%d goal=(%.1f,%.1f) wp=(%.1f,%.1f) at %s task=%s" % [
				1 if _jammed else 0, _navs, 1 if _nav_snapped else 0,
				_nav_goal.x, _nav_goal.z, _nav_wp.x, _nav_wp.z,
				str(global_position), _task_tag])
	_update_audio()
# ------------------------------------------------------------------------------
# Animation mapping (resolver + loop forcing, importer-quirk proof)
# ------------------------------------------------------------------------------

func _find_anim(n: Node) -> AnimationPlayer:
	for c in n.get_children():
		var a: AnimationPlayer = c as AnimationPlayer
		if a != null:
			return a
		var r: AnimationPlayer = _find_anim(c)
		if r != null:
			return r
	return null


func _build_anim_map() -> void:
	if _anim == null:
		return
	for a in _anim.get_animation_list():
		var s: String = String(a)
		var low: String = s.to_lower()
		_anim_map[low] = s
		var parts: PackedStringArray = low.split("|")
		_anim_map[parts[parts.size() - 1]] = s
	for n in [anim_idle, anim_walk, anim_run, "Creature_armature|battle_idle"]:
		var r: String = _resolve(n)
		if r != "":
			_anim.get_animation(r).loop_mode = Animation.LOOP_LINEAR


func _resolve(anim_name: String) -> String:
	if _anim == null or anim_name == "":
		return ""
	var low: String = anim_name.to_lower()
	if _anim_map.has(low):
		return _anim_map[low]
	var parts: PackedStringArray = low.split("|")
	var key: String = parts[parts.size() - 1]
	if _anim_map.has(key):
		return _anim_map[key]
	for k in _anim_map:
		if String(k).contains(key):
			return _anim_map[k]
	return ""


## Task-facing animation request. ROUND 6 authority guard: while the agent owns
## the pose (down / telegraphing / lunging), task requests are refused. Without
## this a running ActChase calls play_anim(anim_run) every tick and overwrites
## death_1 instantly -- literally the "plays a sound then gets stuck in the
## walking animation at the same place" symptom from rounds 3 and 4.
func play_anim(anim_name: String) -> void:
	if _neutralized or _winding or _lunging:
		return
	# ROUND 7: never play a locomotion loop we are not actually performing.
	# Standing against a pillar playing `walk` for 142 s is exactly the
	# "stuck in the wall" look; battle_idle reads as the creature hesitating.
	if _pinned and (anim_name == anim_walk or anim_name == anim_run):
		anim_name = anim_battle_idle
	if _react_t > 0.0 and anim_name == anim_run:
		anim_name = anim_battle_idle   # standing and roaring, not sprinting
	_play_anim_raw(anim_name)


## Agent-internal: always applies. Used by take_damage / start_windup /
## start_lunge / the asleep branch -- exactly the calls that must win.
func _play_anim_raw(anim_name: String) -> void:
	if _anim == null:
		return
	var resolved: String = _resolve(anim_name)
	if resolved == "":
		return
	if _anim.current_animation != resolved:
		_anim.play(resolved)


# ------------------------------------------------------------------------------
# 2.5D audio (pan buses + distance volume)
# ------------------------------------------------------------------------------

func _update_audio() -> void:
	var cam: Camera3D = Events.main_camera
	if cam == null:
		return
	var rel: Vector3 = global_position - cam.global_position
	var dist: float = rel.length()
	var right: float = 0.0
	if dist > 0.01:
		right = cam.global_transform.basis.x.dot(rel.normalized())
	var panv: float = clampf(right, -1.0, 1.0) * 0.85
	for i in range(_voices.size()):
		var p: AudioStreamPlayer = _voices[i]
		if p == null or not p.playing:
			continue
		var maxd: float = _max_dist(p)
		var vol: float = clampf(1.0 - dist / maxd, 0.0, 1.0)
		p.volume_db = linear_to_db(maxf(vol, 0.001)) if vol > 0.02 else -80.0
		if i < _pan_fx.size() and _pan_fx[i] != null:
			_pan_fx[i].pan = panv


func _max_dist(p: AudioStreamPlayer) -> float:
	if p == _roar:
		return 45.0
	if p == _growl:
		return 20.0
	if p == _screech:
		return 30.0
	return 25.0
