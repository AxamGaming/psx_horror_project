extends CharacterBody3D
class_name NightmareCreature
## ============================================================================
## NIGHTMARE CREATURE — LimboAI agent (REBUILD).
##
## Architecture:
##   CreatureAwareness   — all sensors (vision, hearing, proximity) + memory
##   CreatureNavigator   — all navigation and steering (single velocity writer)
##   LimboAI BT          — high-level decisions (patrol / investigate / combat)
##   This script         — combat resolution, animation, audio, health rules
##
## The agent does NOT contain perception logic or navigation patch state.
## That complexity lives in its own nodes with clean interfaces.
##
## BT shape (unchanged — it was correct; perception/nav were the problems):
##   BTDynamicSelector
##   ├─ DynSeq [ CondNeutralized, ActRecover ]
##   ├─ DynSeq [ CondSeesPlayer, BTDynamicSelector[
##   │        DynSeq[CondInSwipeRange, ActSwipe],
##   │        DynSeq[CondCanLunge,     ActLunge],
##   │        ActChase ] ]
##   ├─ Seq    [ CondHearsPlayer, ActSetAlert ]
##   ├─ DynSeq [ CondHasAlert, ActInvestigate ]
##   └─ ActPatrol
## ============================================================================
const BUILD_TAG := "REBUILD"
const LOG_PATH  := "user://creature_log.txt"

@export_group("AI")
@export var patrol_points: Array[Vector3] = []
@export var auto_patrol_radius: float = 4.0
@export var hear_radius: float = 16.0
@export var sight_range: float = 12.0
@export var sight_fov_deg: float = 75.0
@export var confirm_time: float = 0.4
@export var proximity_range: float = 2.5
@export var investigate_dwell: float = 4.0
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
@export var attack_standoff: float = 1.35
@export var neutralize_time: float = 25.0
@export var void_y: float = -0.5

@export_group("Debug")
@export var debug_beacon: bool = true

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

# ── Node refs ─────────────────────────────────────────────────────────────────
@onready var _bt_player: BTPlayer = $BTPlayer
@onready var _roar: AudioStreamPlayer = $Roar
@onready var _growl: AudioStreamPlayer = $Growl
@onready var _step: AudioStreamPlayer = $Step
@onready var _screech: AudioStreamPlayer = $Screech
@onready var _beacon: MeshInstance3D = $DebugBeacon

# ── Child controllers (added in _ready) ──────────────────────────────────────
var awareness: CreatureAwareness = null
var nav: CreatureNavigator = null

# ── Player reference ──────────────────────────────────────────────────────────
var _player: PlayerMovement = null

# ── State flags ───────────────────────────────────────────────────────────────
var _awake: bool = false
var _neutralized: bool = false

# ── Alert (investigation target) ─────────────────────────────────────────────
var _alert_target: Vector3 = Vector3.ZERO
var _has_alert: bool = false
var _alert_cd: float = 0.0

# ── Patrol ────────────────────────────────────────────────────────────────────
var _patrol_idx: int = 0
var _spawn_pos: Vector3 = Vector3.ZERO

# ── Combat timers ─────────────────────────────────────────────────────────────
var _attack_cd: float = 0.0
var _lunge_cd: float = 0.0
var _winding: bool = false
var _windup_t: float = 0.0
var _attack_anim_done: bool = true
var _lunging: bool = false
var _lunge_t: float = 0.0
var _lunge_dir: Vector3 = Vector3.ZERO
var _lunge_hit: bool = false

# ── Amnesia / react telegraph ─────────────────────────────────────────────────
var _amnesia_t: float = 0.0
var _react_t: float = 0.0
var _was_combat: bool = false
var _noncombat_t: float = 999.0

# ── Facing (written by navigator, read here) ──────────────────────────────────
var _move_dir: Vector3 = Vector3.ZERO

# ── Task tag (BT tasks stamp their name; used by navigator and log) ──────────
var _task_tag: String = "-"

# ── Animation helpers ─────────────────────────────────────────────────────────
var _anim: AnimationPlayer = null
var _anim_map: Dictionary = {}

# ── 2.5D audio ────────────────────────────────────────────────────────────────
var _voices: Array[AudioStreamPlayer] = []
var _pan_fx: Array[AudioEffectPanner] = []

# ── Dwell sweep (investigate) ─────────────────────────────────────────────────
var _sweep_t: float = 0.0
var _sweep_gap: float = 999.0
var _sweep_center: float = 0.0

# ── Footstep timer ────────────────────────────────────────────────────────────
var _step_t: float = 0.0

# ── Ground clamp cooldown ─────────────────────────────────────────────────────
var _clamp_cd: float = 0.0

# ── Log / debug ───────────────────────────────────────────────────────────────
var _logf: FileAccess = null
var _dbg_t: float = 0.0


# ── Engine error logger ───────────────────────────────────────────────────────
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

var _err_logger: CreatureErrorLogger = null


# ═══════════════════════════════════════════════════════════════════════════════
# Initialisation
# ═══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
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

	# ── Awareness controller ──────────────────────────────────────────────────
	awareness = CreatureAwareness.new()
	awareness.name = "Awareness"
	add_child(awareness)
	awareness.setup(self)

	# ── Navigation controller ─────────────────────────────────────────────────
	var nav_agent := NavigationAgent3D.new()
	nav_agent.name = "NavAgent"
	add_child(nav_agent)
	nav = CreatureNavigator.new()
	nav.name = "Navigator"
	add_child(nav)
	nav.setup(self, nav_agent)

	# ── LimboAI ───────────────────────────────────────────────────────────────
	_bt_player.behavior_tree = _build_tree()
	_bt_player.active = false

	if _anim != null:
		_anim.animation_finished.connect(_on_anim_finished)
	if _beacon != null:
		_beacon.visible = debug_beacon

	_logf = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	_log("=== spawn build=%s pos=%s" % [BUILD_TAG, str(global_position)])
	_err_logger = CreatureErrorLogger.new()
	OS.add_logger(_err_logger)
	print("REBUILD SELFTEST _log_message path")
	push_warning("REBUILD SELFTEST _log_error path")


func _exit_tree() -> void:
	_drain_engine_log()
	if _err_logger != null:
		if OS.has_method("remove_logger"):
			OS.remove_logger(_err_logger)
		_err_logger = null
	_log("=== exit tree")
	if _logf != null:
		_logf.flush()
		_logf.close()
		_logf = null


# ═══════════════════════════════════════════════════════════════════════════════
# Behavior tree construction
# ═══════════════════════════════════════════════════════════════════════════════

func _build_tree() -> BehaviorTree:
	var bt := BehaviorTree.new()
	var root := BTDynamicSelector.new()
	bt.set_root_task(root)

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


# ═══════════════════════════════════════════════════════════════════════════════
# Wake / damage / neutralize
# ═══════════════════════════════════════════════════════════════════════════════

var health: float = 100.0


func _on_gun_fired(pos: Vector3) -> void:
	if global_position.distance_to(pos) > gunshot_hear_range:
		return
	if _neutralized:
		return
	if not _awake:
		_wake(pos)
	else:
		set_alert(pos, true)
		awareness.stamp_position(pos)


func _wake(pos: Vector3) -> void:
	_awake = true
	_roar.play()
	set_alert(pos, true)
	awareness.stamp_position(pos)
	_bt_player.active = true
	_log("WAKE at %s (player %s)" % [str(global_position), str(pos)])


# ── Alert API (investigation target) ──────────────────────────────────────────

func has_alert() -> bool:
	return _has_alert


func get_alert_target() -> Vector3:
	return _alert_target


func set_alert(pos: Vector3, force: bool = false) -> void:
	if not force and _has_alert and _alert_cd > 0.0 \
			and pos.distance_to(_alert_target) < 4.0:
		return
	_alert_cd = 3.0
	_alert_target = pos
	_has_alert = true


func clear_alert() -> void:
	_has_alert = false


# ── Damage / neutralize ────────────────────────────────────────────────────────

func take_damage(amount: float, push_dir: Vector3) -> void:
	if _neutralized:
		return
	if not _awake:
		_wake(_player.global_position if _player != null else global_position)
	health -= amount
	_amnesia_t = 0.0
	_screech.play()
	_log("DAMAGE %.1f -> hp %.1f" % [amount, health])
	position += Vector3(push_dir.x, 0.0, push_dir.z).normalized() * 0.25
	if not _neutralized:
		_neutralized = true
		_winding = false
		_windup_t = 0.0
		_lunging = false
		_lunge_t = 0.0
		_task_tag = "-"
		nav.stop()
		_play_anim_raw(anim_death)
		_screech.play()
		_log("NEUTRALIZED for %.1fs" % neutralize_time)


func is_neutralized() -> bool:
	return _neutralized


func recover() -> void:
	_neutralized = false
	_winding = false
	_windup_t = 0.0
	_lunging = false
	_lunge_t = 0.0
	_lunge_hit = false
	_attack_cd = 0.0
	_lunge_cd = 0.0
	_task_tag = "-"
	health = max_health
	_patrol_idx = 0
	clear_alert()
	forget_player()
	_roar.play()
	_log("RECOVER at %s (amnesiac patrol)" % str(global_position))


# ═══════════════════════════════════════════════════════════════════════════════
# Senses (proxies to awareness — tasks should prefer awareness directly)
# ═══════════════════════════════════════════════════════════════════════════════

func player_pos() -> Vector3:
	if _player == null:
		return global_position
	return _player.global_position


func dist_to_player() -> float:
	var d: Vector3 = player_pos() - global_position
	d.y = 0.0
	return d.length()


## Legacy compat: tasks that call sees_player() directly still work.
## New tasks should call awareness.confirmed() instead.
func sees_player(check_fov: bool = true) -> bool:
	if awareness == null:
		return false
	if check_fov:
		return awareness.confirmed()
	return awareness.proximity()


func hears_player() -> bool:
	if awareness == null:
		return false
	return awareness.heard()


# ═══════════════════════════════════════════════════════════════════════════════
# Movement API (delegates to navigator)
# ═══════════════════════════════════════════════════════════════════════════════

## Returns true when arrived. BT tasks call this instead of writing velocity.
func move_toward_point(target: Vector3, speed: float, arrive: float = 0.7) -> bool:
	if nav == null:
		return true
	return nav.travel_to(target, speed, arrive)


func stop_move() -> void:
	if nav != null:
		nav.stop()


func is_stuck() -> bool:
	if nav == null:
		return false
	return nav.is_stuck()


func clear_stuck() -> void:
	pass   # navigator manages its own stuck state; patrol calls this on skip


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


## Walkable point near `around` for investigation search points.
func search_point_near(around: Vector3, radius: float) -> Vector3:
	var best: Vector3 = around
	for i in range(6):
		var a: float = randf() * TAU
		var r: float = radius * sqrt(randf())
		var p: Vector3 = around + Vector3(cos(a), 0.0, sin(a)) * r
		if nav != null:
			p = NavigationServer3D.map_get_closest_point(
					nav._nav.get_navigation_map(), p)
		best = p
		if p.distance_to(global_position) > 1.5:
			break
	return best


# ═══════════════════════════════════════════════════════════════════════════════
# Patrol
# ═══════════════════════════════════════════════════════════════════════════════

func current_patrol_point() -> Vector3:
	if patrol_points.is_empty():
		return _spawn_pos
	return patrol_points[_patrol_idx]


func next_patrol_point() -> void:
	_patrol_idx = (_patrol_idx + 1) % patrol_points.size()


# ═══════════════════════════════════════════════════════════════════════════════
# Combat resolution
# ═══════════════════════════════════════════════════════════════════════════════

func attack_ready() -> bool:
	return _attack_cd <= 0.0 and not _winding and not _lunging


func lunge_ready() -> bool:
	return _lunge_cd <= 0.0


func start_windup() -> void:
	_windup_t = 0.0
	_winding = true
	nav.stop()
	_play_anim_raw(anim_attack)
	_attack_anim_done = false
	_growl.play()
	_log("WINDUP dist=%.2f" % dist_to_player())


func windup_done() -> bool:
	return _attack_anim_done or _windup_t >= windup_time * 2.0


func do_swipe() -> void:
	_winding = false
	if _player != null and dist_to_player() < swipe_range * 1.25:
		var dir: Vector3 = (player_pos() - global_position).normalized()
		Events.player_damaged.emit(swipe_damage, dir)
		_player.apply_knockback(dir, knockback_force * 0.6)
		_growl.play()
		_log("SWIPE HIT dist=%.2f" % dist_to_player())
	_attack_cd = swipe_cooldown


func cancel_windup() -> void:
	_winding = false
	_windup_t = 0.0


func is_winding() -> bool:
	return _winding


func start_lunge() -> void:
	_lunge_dir = player_pos() - global_position
	_lunge_dir.y = 0.0
	if _lunge_dir.length_squared() > 0.001:
		_lunge_dir = _lunge_dir.normalized()
	_lunge_t = 0.0
	_lunge_hit = false
	_lunging = true
	_play_anim_raw(anim_bite)
	_roar.play()
	_log("LUNGE START dist=%.2f" % dist_to_player())


func lunge_done() -> bool:
	return not _lunging


func cancel_lunge() -> void:
	_lunging = false
	_lunge_t = 0.0
	_lunge_hit = false
	_lunge_cd = lunge_cooldown


# ═══════════════════════════════════════════════════════════════════════════════
# Task-tag / BT interface
# ═══════════════════════════════════════════════════════════════════════════════

func set_task_tag(t: String) -> void:
	_task_tag = t


func task_tag() -> String:
	return _task_tag


func note_combat_start() -> void:
	if not _was_combat:
		_react_t = 0.7
		_was_combat = true


func is_amnesiac() -> bool:
	return _amnesia_t > 0.0


func forget_player() -> void:
	_amnesia_t = 5.0
	_react_t = 0.0
	if awareness != null:
		awareness.reset()


# ═══════════════════════════════════════════════════════════════════════════════
# Frame update
# ═══════════════════════════════════════════════════════════════════════════════

func _physics_process(delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as PlayerMovement
	_drain_engine_log()

	# Void reset.
	if global_position.y < -5.0 or global_position.y < void_y:
		_log("VOID RESET from y=%.2f" % global_position.y)
		global_position = _spawn_pos
		velocity = Vector3.ZERO
		_neutralized = false
		_winding = false
		_lunging = false

	# Proximity wake.
	if not _awake and not _neutralized and _player != null \
			and dist_to_player() < proximity_range:
		_wake(player_pos())

	# ── Tick sub-controllers BEFORE move_and_slide ────────────────────────────
	if awareness != null:
		awareness.tick(delta)
	if nav != null:
		nav.tick(delta)          # writes velocity.x/z

	_attack_cd = maxf(0.0, _attack_cd - delta)
	_lunge_cd  = maxf(0.0, _lunge_cd - delta)

	if _neutralized:
		nav.stop()
		velocity = Vector3.ZERO
	elif not _awake:
		nav.stop()
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

	# ── Physics ───────────────────────────────────────────────────────────────
	if not _neutralized:
		velocity.y = maxf(velocity.y - gravity * delta, -40.0)
		move_and_slide()
	_clamp_to_ground()

	# ── Depenetration from player ─────────────────────────────────────────────
	if not _lunging and _player != null:
		var away: Vector3 = global_position - player_pos()
		away.y = 0.0
		var ov: float = away.length()
		if ov < 1.05:
			if ov < 0.0001:
				away = Vector3(1.0, 0.0, 0.0)
				ov = 0.0
			global_position += away.normalized() * (1.05 - ov)

	# ── Combat state tracking ─────────────────────────────────────────────────
	if _task_tag == "ActChase" or _task_tag == "ActSwipe" or _task_tag == "ActLunge":
		_noncombat_t = 0.0
	else:
		_noncombat_t += delta
	if _noncombat_t > 2.0:
		_was_combat = false

	_amnesia_t = maxf(0.0, _amnesia_t - delta)
	_react_t   = maxf(0.0, _react_t - delta)
	_alert_cd  = maxf(0.0, _alert_cd - delta)
	_sweep_gap += delta

	# ── Animation ─────────────────────────────────────────────────────────────
	var real_hspd: float = nav.real_hspd if nav != null else 0.0
	if _anim != null:
		var nominal: float = run_speed if _anim.current_animation == _resolve(anim_run) \
				else walk_speed
		if real_hspd > 0.05 and not (nav != null and nav.is_pinned()):
			_anim.speed_scale = clampf(real_hspd / maxf(nominal, 0.1), 0.55, 1.45)
		else:
			_anim.speed_scale = 1.0

	# Facing — commanded direction from navigator.
	if not _neutralized and _awake and _move_dir.length_squared() > 0.000001:
		var desired: float = atan2(_move_dir.x, _move_dir.z)
		rotation.y = lerp_angle(rotation.y, desired, 1.0 - exp(-10.0 * delta))

	# Footsteps.
	if not _neutralized and _awake and is_on_floor() and real_hspd > 0.3:
		_step_t -= delta
		if _step_t <= 0.0:
			_step.play()
			_step.pitch_scale = randf_range(0.9, 1.1)
			_step_t = (0.38 if real_hspd > walk_speed * 1.4 else 0.6) \
					/ maxf(_anim.speed_scale if _anim != null else 1.0, 0.55)

	# ── Debug log (1 Hz) ──────────────────────────────────────────────────────
	_dbg_t -= delta
	if _dbg_t <= 0.0:
		_dbg_t = 1.0
		var aname: String = String(_anim.current_animation) if _anim != null else "-"
		_log("state awake=%s neu=%s pos=(%.2f,%.2f,%.2f) vreal=%.2f task=%s anim=%s dist=%.2f conf=%s heard=%s mem=%s" % [
			str(_awake), str(_neutralized),
			global_position.x, global_position.y, global_position.z,
			real_hspd, _task_tag, aname, dist_to_player(),
			str(awareness.confirmed() if awareness else false),
			str(awareness.heard() if awareness else false),
			str(awareness.has_memory() if awareness else false)])

	_update_audio()


# ── Investigate dwell sweep ────────────────────────────────────────────────────

func turn_slow(delta: float) -> void:
	if _sweep_gap > 0.3:
		_sweep_center = rotation.y
		_sweep_t = 0.0
	_sweep_gap = 0.0
	_sweep_t += delta
	rotation.y = _sweep_center + sin(_sweep_t * 1.3) * 1.1


# ── Locomotion clip selector ───────────────────────────────────────────────────

func play_gait(speed: float) -> void:
	play_anim(anim_run if speed > walk_speed * 1.25 else anim_walk)


# ── Ground clamp ──────────────────────────────────────────────────────────────

func _clamp_to_ground() -> void:
	_clamp_cd = maxf(0.0, _clamp_cd - get_physics_process_delta_time())
	var world: World3D = get_world_3d()
	if world == null or world.direct_space_state == null:
		return
	var from: Vector3 = global_position + Vector3(0.0, 0.6, 0.0)
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			from, from + Vector3(0.0, -4.0, 0.0))
	q.exclude = [get_rid()]
	q.collision_mask = 1
	var hit: Dictionary = world.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var gp: Vector3 = hit["position"]
	if gp.y > global_position.y + 0.05:
		var was: float = global_position.y
		global_position.y = gp.y + 0.9
		velocity.y = 0.0
		if _clamp_cd <= 0.0:
			_log("GROUND CLAMP y %.2f -> %.2f" % [was, global_position.y])
			_clamp_cd = 2.0


# ── Debug state (for debug panel) ─────────────────────────────────────────────

func debug_state() -> Dictionary:
	var aname: String = String(_anim.current_animation) if _anim != null else "-"
	return {
		"tag":        BUILD_TAG,
		"pos":        global_position,
		"awake":      _awake,
		"neutralized":_neutralized,
		"dist":       dist_to_player(),
		"sees":       awareness.confirmed() if awareness else false,
		"hears":      awareness.heard() if awareness else false,
		"mem":        awareness.has_memory() if awareness else false,
		"anim":       aname,
		"hp":         health,
		"task":       _task_tag,
		"vreal":      nav.real_hspd if nav else 0.0,
	}


# ═══════════════════════════════════════════════════════════════════════════════
# Animation helpers
# ═══════════════════════════════════════════════════════════════════════════════

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


func play_anim(anim_name: String) -> void:
	if _neutralized or _winding or _lunging:
		return
	if nav != null and nav.is_pinned() and (anim_name == anim_walk or anim_name == anim_run):
		anim_name = anim_battle_idle
	if _react_t > 0.0 and anim_name == anim_run:
		anim_name = anim_battle_idle
	_play_anim_raw(anim_name)


func _play_anim_raw(anim_name: String) -> void:
	if _anim == null:
		return
	var resolved: String = _resolve(anim_name)
	if resolved == "":
		return
	if _anim.current_animation != resolved:
		_anim.play(resolved)


func _on_anim_finished(name: StringName) -> void:
	if _anim != null and name == _resolve(anim_attack):
		_attack_anim_done = true


# ═══════════════════════════════════════════════════════════════════════════════
# 2.5D audio
# ═══════════════════════════════════════════════════════════════════════════════

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
	if p == _roar:    return 45.0
	if p == _growl:   return 20.0
	if p == _screech: return 30.0
	return 25.0


# ═══════════════════════════════════════════════════════════════════════════════
# Telemetry
# ═══════════════════════════════════════════════════════════════════════════════

func _log(msg: String) -> void:
	if _logf == null:
		return
	_logf.store_line("%8d | %s" % [Time.get_ticks_msec(), msg])
	_logf.flush()


func _drain_engine_log() -> void:
	if _err_logger == null or _logf == null:
		return
	for l in _err_logger.take_lines():
		_log(l)
