extends CharacterBody3D
class_name NightmareCreature
## BUILD_TAG: bump every fix round. Debug panel shows it live, so a playtest
## proves in one glance whether the newest files are actually running.
const BUILD_TAG := "R5"
const LOG_PATH := "user://creature_log.txt"
## ============================================================================
## NIGHTMARE CREATURE — LimboAI agent (Phase 12 rebuild).
##
## Decision-making lives in a LimboAI BehaviorTree (built in code below,
## executed by the BTPlayer node); this script is the AGENT: senses, movement,
## combat resolution, animation mapping, 2.5D audio, health/neutralize rules.
## Custom tasks live in scenes/enemies/tasks/*.gd and call these methods.
##
## Tree shape:
##   BTSelector
##   ├─ Seq [ CondNeutralized, ActRecover ]          (down -> wait -> rise amnesiac)
##   ├─ Seq [ CondSeesPlayer(confirmed), BTSelector[
##   │        Seq[CondInSwipeRange, ActSwipe],
##   │        Seq[CondCanLunge,  ActLunge],
##   │        ActChase ] ]
##   ├─ Seq [ CondHearsPlayer, ActSetAlert ]          (noise -> investigation target)
##   ├─ Seq [ CondHasAlert, ActInvestigate ]          (go sniff, dwell, forget)
##   └─ ActPatrol                                     (walk the ring/points)
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
@export var investigate_dwell: float = 6.0
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
			rationale: String, editor_notify: bool, error_type: int,
			script_backtraces: Array[ScriptBacktrace]) -> void:
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
	if _beacon != null:
		_beacon.visible = debug_beacon
	_logf = FileAccess.open(LOG_PATH, FileAccess.WRITE)   # truncate each run
	_log("=== spawn build=%s pos=%s patrol=%s" % [BUILD_TAG, str(global_position), str(patrol_points)])
	_err_logger = CreatureErrorLogger.new()
	OS.add_logger(_err_logger)


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

func _build_tree() -> BehaviorTree:
	var bt := BehaviorTree.new()
	var root := BTSelector.new()
	bt.set_root_task(root)   # LimboAI 1.8 API: no `root` property; use set_root_task()

	var seq_recover := BTSequence.new()
	seq_recover.add_child(CondNeutralized.new())
	seq_recover.add_child(ActRecover.new())
	root.add_child(seq_recover)

	var seq_combat := BTSequence.new()
	seq_combat.add_child(CondSeesPlayer.new())
	var combat_sel := BTSelector.new()
	var seq_swipe := BTSequence.new()
	seq_swipe.add_child(CondInSwipeRange.new())
	seq_swipe.add_child(ActSwipe.new())
	var seq_lunge := BTSequence.new()
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

	var seq_inv := BTSequence.new()
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
		set_alert(pos)


func _wake(pos: Vector3) -> void:
	_awake = true
	_roar.play()
	set_alert(pos)
	_bt_player.active = true
	_log("WAKE at %s (player %s)" % [str(global_position), str(pos)])


## Investigation-target API (used by tasks instead of a blackboard).
func has_alert() -> bool:
	return _has_alert


func get_alert_target() -> Vector3:
	return _alert_target


func set_alert(pos: Vector3) -> void:
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
		stop_move()
		play_anim(anim_death)
		_screech.play()
		_log("NEUTRALIZED for %.1fs" % neutralize_time)


func is_neutralized() -> bool:
	return _neutralized


func recover() -> void:
	_neutralized = false
	health = max_health
	_patrol_idx = 0
	clear_alert()
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


func sees_player() -> bool:
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
	if rad_to_deg(fwd.normalized().angle_to(flat.normalized())) > sight_fov_deg * 0.5:
		return false
	var world: World3D = get_world_3d()
	if world == null:
		return true
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	if space == null:
		return true
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0.0, 1.2, 0.0),
		_player.global_position + Vector3(0.0, 1.0, 0.0)
	)
	q.exclude = [get_rid(), _player.get_rid()]
	return space.intersect_ray(q).is_empty()


func hears_player() -> bool:
	if _player == null:
		return false
	var noise: float = _player.noise_level
	return noise > 0.05 and dist_to_player() < hear_radius * noise


# ------------------------------------------------------------------------------
# Movement helpers (used by actions)
# ------------------------------------------------------------------------------

## Returns true when arrived within 0.7 m.
func move_toward_point(target: Vector3, speed: float) -> bool:
	var dir: Vector3 = target - global_position
	dir.y = 0.0
	if dir.length() < 0.7:
		stop_move()
		return true
	dir = dir.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_want_move = true
	return false


func stop_move() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_want_move = false


## True when we've been commanded to move but barely moved for >1 s
## (patrol point inside a wall, cornered, etc.).
func is_stuck() -> bool:
	return _stuck_t > 1.0


## Called by ActPatrol when it skips a blocked point; without this the stuck
## flag stays hot and chain-skips every remaining point in consecutive ticks.
func clear_stuck() -> void:
	_stuck_t = 0.0


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
	}


func turn_slow(delta: float) -> void:
	rotation.y += delta * 2.5   # fast enough to actually face the alert during dwell


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
	play_anim(anim_attack)
	_growl.play()
	_log("WINDUP dist=%.2f" % dist_to_player())


func windup_done() -> bool:
	return _windup_t >= windup_time


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
	play_anim(anim_bite)
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
		play_anim(anim_idle)
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

	if not _neutralized:
		velocity.y = maxf(velocity.y - gravity * delta, -40.0)
		move_and_slide()
	_clamp_to_ground()
	var hspeed: float = Vector2(velocity.x, velocity.z).length()
	if _want_move and hspeed < 0.2:
		_stuck_t += delta
	else:
		_stuck_t = 0.0
	if not _neutralized and hspeed > 0.3:
		var desired: float = atan2(velocity.x, velocity.z)
		rotation.y = lerp_angle(rotation.y, desired, 1.0 - exp(-10.0 * delta))
	# Footsteps ONLY while commanded to walk, awake, on the floor and actually
	# moving (round-5 hardening: no steps while down, sliding, lunging or stuck).
	if not _neutralized and _awake and _want_move and is_on_floor() and hspeed > 0.3:
		_step_t -= delta
		if _step_t <= 0.0:
			_step.play()
			_step.pitch_scale = randf_range(0.9, 1.1)
			# Run cadence only when actually running; walk gets 0.6 s so the
			# clip (0.45 s) always finishes before the next step.
			_step_t = 0.38 if hspeed > walk_speed * 1.4 else 0.6
	_dbg_t -= delta
	if _dbg_t <= 0.0:
		_dbg_t = 1.0
		var aname: String = String(_anim.current_animation) if _anim != null else "-"
		_log("state awake=%s neu=%s pos=(%.2f,%.2f,%.2f) hspd=%.2f onfl=%s stuck=%.2f anim=%s dist=%.2f" % [
			str(_awake), str(_neutralized),
			global_position.x, global_position.y, global_position.z,
			hspeed, str(is_on_floor()), _stuck_t, aname, dist_to_player()])
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


func _resolve(name: String) -> String:
	if _anim == null or name == "":
		return ""
	var low: String = name.to_lower()
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


func play_anim(name: String) -> void:
	var resolved: String = _resolve(name)
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
