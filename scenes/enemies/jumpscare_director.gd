extends Node3D
class_name JumpscareDirector
## ============================================================================
## JUMPSCARE DIRECTOR — R26. Owns the creature-kill cutscene.
##
## Flow (see docs/JUMPSCARE_SYSTEM.md):
##   creature swipe/lunge tags survival.last_damage_source = "creature"
##   → survival emits player_killed_by_creature (before player_died)
##   → _on_creature_kill(): suppress death overlay, transfer camera authority
##     to CreatureKillCamera, lock input, freeze creature in a roar pose
##     (creature.jumpscare_hold), play stinger + JumpscareAnim
##   → animation_finished (or respawn_timeout_sec) → _end_sequence():
##     restore cameras/input, release the hold, emit respawn_requested.
##
## Everything timing-shaped lives in the JumpscareAnim AnimationPlayer so the
## sequence is designer-editable without code. If the library has no animation
## named `anim_name`, a functional 2 s default is BUILT HERE at ready (fov slam,
## camera shake, light flash, roar trigger) so the system scares out of the
## box; a designer-authored animation of the same name in the .tscn always wins.
##
## Deliberate deviations from the original design doc (field decisions):
##   - input lock uses Events.ui_wants_mouse (the gate MouseLook AND
##     WeaponSystem already respect) plus a body process freeze, instead of
##     process-flag-only locking which would leave mouse/weapon live.
##   - head bone name is an export (this rig's bone is "Head_015", not "Head").
##   - feeding is skipped on creature kills (creature.jumpscare_hold), because
##     the per-frame feeding/gait selector would otherwise overwrite the scare
##     pose and film the eat animation into the kill cam.
## ============================================================================

# ── Designer tuning ──────────────────────────────────────────────────────────
@export_group("Void-out")
## R26d: how hard the world visually disappears during the scare.
## 0.0 = the corridor stays visible behind the face (original look).
## 1.0 = pure black void: only the scare light on the creature's face remains —
## the "empty dark room" shot, achieved IN PLACE (no teleports: the death stays
## attached to the place it happened, which is what makes that place scary on
## the next run). Ramps ambient/background/sun down and back up smoothly.
@export_range(0.0, 1.0) var void_darkness: float = 0.7
@export var void_ramp_speed: float = 6.0

@export_group("Camera & Light")
## R26c: NO transform/colour exports any more. The CreatureKillCamera and
## JumpscareLight nodes are authored directly in nightmare_creature.tscn —
## move/rotate/fov/colour/energy them in the editor and the sequence uses
## exactly what you placed. The director only toggles `current`/`visible` and
## plays the animation (whose default tracks capture the authored values at
## build time, so even the fov slam and light flash respect your numbers).
@export var use_jumpscare_light: bool = true

@export_group("Lunge at lens")
## R27: on kill, the creature first plays an attack anim and charges this far
## toward the lens (face rushes the camera), then holds the roar pose.
@export var charge_distance: float = 0.8
@export var charge_speed: float = 2.5
## Which creature animation export to use for the lunge beat.
@export var lunge_anim_prop: String = "anim_attack_3"
## Head bone the kill cam stays welded to (this rig: "Head_015").
@export var head_bone_name: String = "Head_015"

@export_group("Sequence")
@export var anim_name: String = "jumpscare"
@export var auto_respawn_on_finish: bool = true
## Softlock guard: respawn anyway after this many seconds. 0 disables.
@export var respawn_timeout_sec: float = 8.0

@export_group("Audio")
## Guaranteed-loud one-shot at sequence start, layered over anim audio tracks.
@export var stinger: AudioStream = preload("res://audio/sfx/jumpscare_stinger.wav")
@export var stinger_volume_db: float = 0.0

# ── Nodes ────────────────────────────────────────────────────────────────────
@onready var _kill_cam: Camera3D = $CreatureKillCamera
@onready var _anim: AnimationPlayer = $JumpscareAnim
@onready var _light: Light3D = $JumpscareLight
@onready var _stinger_player: AudioStreamPlayer = $StingerPlayer

# ── State ────────────────────────────────────────────────────────────────────
var _active: bool = false
var _timeout_t: float = 0.0
var _skeleton: Skeleton3D = null
var _head_bone_idx: int = -1
var _prev_ui_wants_mouse: bool = false
var _player_locked: bool = false
# R26d void-out state (world light ramp).
var _env: Environment = null
var _sun: DirectionalLight3D = null
var _base_bg_energy: float = 1.0
var _base_amb_energy: float = 1.0
var _base_sun_energy: float = 1.0
var _base_fog_density: float = 0.0
var _void_k: float = 0.0
# R27 head-weld: transforms captured at ready so the camera/light stay glued to
# the creature no matter what the scene tree looks like (survives mis-parented
# rigs, plain-Node directors, merged tscn edits).
var _creature: Node3D = null
var _cam_head_offset: Transform3D = Transform3D()
var _has_head_weld: bool = false
var _cam_local: Transform3D = Transform3D()
var _light_local: Transform3D = Transform3D()
var _charging: bool = false
var _charge_left: float = 0.0
## Actual animation name to play after name resolution (R28e): survives
## renames in the animation panel (anim_name export vs library key mismatch).
var _play_name: StringName = &""


func _ready() -> void:
	Events.player_killed_by_creature.connect(_on_creature_kill)
	Events.player_respawned.connect(_on_respawned)
	_kill_cam.current = false
	if _light != null:
		_light.visible = false
	_anim.animation_finished.connect(_on_anim_finished)
	_capture_welds()
	_resolve_world_lighting()
	if _anim.has_animation(anim_name):
		# Scene-wired library (the shared editable .tres, or a scene-local copy):
		# animation-panel edits are in effect.
		_play_name = anim_name
		push_warning("JumpscareDirector: '%s' from scene-wired library - panel edits ACTIVE." % anim_name)
	else:
		_load_or_build_anim()


func _process(delta: float) -> void:
	_apply_void_ramp(delta)
	if not _active:
		return
	_drive_rig(delta)
	if respawn_timeout_sec > 0.0:
		_timeout_t += delta
		if _timeout_t >= respawn_timeout_sec:
			push_warning("JumpscareDirector: respawn_timeout reached — ending sequence.")
			_end_sequence()


# ── Sequence ─────────────────────────────────────────────────────────────────

func _on_creature_kill() -> void:
	if _active:
		return   # first kill wins (design doc §8)
	_active = true
	_timeout_t = 0.0

	# Suppress the death overlay BEFORE player_died propagates (it is emitted
	# right after this signal, synchronously, so the flag is in time).
	var overlay: Node = get_tree().get_first_node_in_group("death_overlay")
	if overlay != null and overlay.has_method("suppress_next"):
		overlay.call("suppress_next")

	# Freeze the creature in the scare pose; skip feeding entirely.
	var creature: Node = get_parent()
	if creature != null and "jumpscare_hold" in creature:
		creature.set("jumpscare_hold", true)

	# Camera authority transfer (authored transform/fov untouched).
	if Events.main_camera != null:
		Events.main_camera.current = false
	_kill_cam.current = true

	# Input lock: ui_wants_mouse gates MouseLook + WeaponSystem project-wide;
	# the body freeze stops locomotion/corpse drift during the scare.
	_prev_ui_wants_mouse = Events.ui_wants_mouse
	Events.ui_wants_mouse = true
	_lock_player(true)

	# Light: authored colour/energy stay; we only switch it on.
	if use_jumpscare_light and _light != null:
		_light.visible = true

	if stinger != null:
		_stinger_player.stream = stinger
		_stinger_player.volume_db = stinger_volume_db
		_stinger_player.play()

	if _play_name == &"":
		_play_name = anim_name
	if _anim.has_animation(_play_name):
		_anim.play(_play_name)
	else:
		push_warning("JumpscareDirector: animation '%s' missing — respawning now." % String(_play_name))
		_end_sequence()


func _on_anim_finished(_name: String) -> void:
	if not _active:
		return
	if auto_respawn_on_finish:
		_end_sequence()


func _end_sequence() -> void:
	if not _active:
		return
	_active = false
	_charging = false
	_anim.stop()
	_kill_cam.current = false
	if Events.main_camera != null:
		Events.main_camera.current = true
	if _light != null:
		_light.visible = false
	_lock_player(false)
	Events.ui_wants_mouse = _prev_ui_wants_mouse
	var creature: Node = get_parent()
	if creature != null and "jumpscare_hold" in creature:
		creature.set("jumpscare_hold", false)
		_release_bt(creature)
	Events.respawn_requested.emit()


func _on_respawned() -> void:
	# Debug respawn mid-scare: tear everything down without re-requesting.
	if not _active:
		return
	_active = false
	_anim.stop()
	_kill_cam.current = false
	if Events.main_camera != null:
		Events.main_camera.current = true
	if _light != null:
		_light.visible = false
	_lock_player(false)
	Events.ui_wants_mouse = _prev_ui_wants_mouse
	var creature: Node = get_parent()
	if creature != null:
		_release_bt(creature)


## R26d: find the level's Environment + sun and remember their authored
## energies so the void-out ramp can scale and restore them exactly.
func _resolve_world_lighting() -> void:
	var level: Node = get_parent()
	while level != null and not (level.get_parent() is SubViewport):
		level = level.get_parent()
	if level == null:
		return
	var we: WorldEnvironment = level.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if we != null and we.environment != null:
		_env = we.environment
		_base_bg_energy = _env.background_energy_multiplier
		_base_amb_energy = _env.ambient_light_energy
		_base_fog_density = _env.fog_density
	for c in level.find_children("*", "DirectionalLight3D", true, true):
		_sun = c as DirectionalLight3D
		_base_sun_energy = _sun.light_energy
		break


## R26d: smooth world-disappearance ramp. Runs while active (ramp in) AND after
## the sequence (ramp back out), so there is never a light pop on either end.
func _apply_void_ramp(delta: float) -> void:
	var target: float = void_darkness if _active else 0.0
	if _env == null and _sun == null:
		return
	_void_k = lerpf(_void_k, target, 1.0 - exp(-maxf(void_ramp_speed, 0.001) * delta))
	if absf(_void_k - target) < 0.002:
		_void_k = target
	var eff: float = _void_k
	if _env != null:
		_env.background_energy_multiplier = _base_bg_energy * (1.0 - 0.95 * eff)
		_env.ambient_light_energy = _base_amb_energy * (1.0 - 0.95 * eff)
	if _sun != null:
		_sun.light_energy = _base_sun_energy * (1.0 - 0.95 * eff)
	if _env != null and _base_fog_density > 0.0:
		# This level's fog (density ~1.0) eats ALL light beyond ~1.5 m; without
		# lifting it the scare light cannot reach the face at any usable framing.
		_env.fog_density = _base_fog_density * (1.0 - 0.85 * eff)


## R28b: the editable animation resource is the single source of truth at
## runtime TOO. If this scene's AnimationPlayer has no library wired (e.g. a
## hand-edited creature tscn that lost the `libraries =` line), load the shared
## jumpscare_anim.tres library here so edits made in the animation panel ALWAYS
## take effect in-game. Code-built fallback only if the .tres is missing.
const JUMPSCARE_LIB_PATH := "res://scenes/enemies/jumpscare_anim.tres"


func _load_or_build_anim() -> void:
	var lib: AnimationLibrary = load(JUMPSCARE_LIB_PATH) as AnimationLibrary
	if lib == null:
		# Missing OR corrupt .tres (load failed): code-build keeps the scare
		# alive, but panel edits cannot apply until the file is restored.
		var msg := ("JumpscareDirector: library %s failed to load (missing or CORRUPT). " \
			+ "'%s' CODE-BUILT - panel edits NOT in effect. Re-apply the zip or restore the .tres.") % [JUMPSCARE_LIB_PATH, anim_name]
		push_warning(msg)
		_build_default_anim()
		_play_name = anim_name
		return
	_attach_library(lib)
	if lib.has_animation(anim_name):
		_play_name = anim_name
		push_warning("JumpscareDirector: '%s' loaded from %s - panel edits ACTIVE." % [anim_name, JUMPSCARE_LIB_PATH])
		return
	# Name mismatch (e.g. you renamed the animation in the panel but the
	# anim_name export still points at the old key, or vice versa). If the
	# library holds exactly one animation, use it instead of code-building:
	# your edits stay in effect and the warning tells you what happened.
	var list: Array[StringName] = lib.get_animation_list()
	if list.size() == 1:
		_play_name = list[0]
		var msg2 := ("JumpscareDirector: anim_name '%s' not in library; using its only " \
			+ "animation '%s' - panel edits ACTIVE. (Set anim_name='%s' to silence this.)") % [anim_name, String(_play_name), String(_play_name)]
		push_warning(msg2)
	else:
		var msg3 := ("JumpscareDirector: anim_name '%s' not in library (has: %s) and no single " \
			+ "fallback - CODE-BUILT, panel edits NOT in effect.") % [anim_name, str(list)]
		push_warning(msg3)
		_build_default_anim()
		_play_name = anim_name


func _attach_library(lib: AnimationLibrary) -> void:
	if _anim.get_animation_library_list().is_empty():
		_anim.add_animation_library("", lib)
	else:
		var first: StringName = _anim.get_animation_library_list()[0]
		var mine: AnimationLibrary = _anim.get_animation_library(first)
		for aname in lib.get_animation_list():
			if not mine.has_animation(aname):
				mine.add_animation(aname, lib.get_animation(aname))


## R27: capture where the camera/light sit relative to the creature (and to
## the head bone) AT EDIT-TIME, so runtime can weld them to the creature no
## matter how the scene tree is parented. Editor placement stays authoritative:
## whatever you posed in the editor becomes the head-relative offset.
func _capture_welds() -> void:
	_creature = get_parent() as Node3D
	if _creature == null:
		return
	var cre_inv: Transform3D = _creature.global_transform.affine_inverse()
	_cam_local = cre_inv * _kill_cam.global_transform
	if _light != null:
		_light_local = cre_inv * _light.global_transform
	var skel: Skeleton3D = null
	for c in _creature.find_children("*", "Skeleton3D", true, true):
		skel = c as Skeleton3D
		break
	if skel != null:
		var idx: int = skel.find_bone(head_bone_name)
		if idx < 0:
			for i in range(skel.get_bone_count()):
				if skel.get_bone_name(i).contains("Head"):
					idx = i
					break
		if idx >= 0:
			_skeleton = skel
			_head_bone_idx = idx
			var head_now: Transform3D = skel.global_transform * skel.get_bone_global_pose(idx)
			_cam_head_offset = head_now.affine_inverse() * _kill_cam.global_transform
			_has_head_weld = true


## R27: per-frame rig drive. Camera stays welded to the head bone (so the face
## is ALWAYS in frame wherever the kill happens and whatever pose it is in),
## light rides the body, and the charge beat rushes the face at the lens.
func _drive_rig(delta: float) -> void:
	if _creature == null:
		return
	if _charging:
		var fwd: Vector3 = -_creature.global_transform.basis.z
		fwd.y = 0.0
		if fwd.length_squared() > 0.001:
			var step: float = minf(charge_speed * delta, _charge_left)
			_creature.global_position += fwd.normalized() * step
			_charge_left -= step
		if _charge_left <= 0.0:
			_charging = false
	var shake: Vector3 = Vector3.ZERO
	if _anim.is_playing():
		var t: float = _anim.current_animation_position
		if 0.2 <= t and t <= 0.5:
			shake = Vector3(randf_range(-0.02, 0.02), randf_range(-0.015, 0.015), 0.0)
	if _has_head_weld and _skeleton != null and is_instance_valid(_skeleton):
		var head_now: Transform3D = _skeleton.global_transform * _skeleton.get_bone_global_pose(_head_bone_idx)
		var wanted: Transform3D = head_now * _cam_head_offset
		wanted.origin += wanted.basis * shake
		_kill_cam.global_transform = wanted
	else:
		var wanted2: Transform3D = _creature.global_transform * _cam_local
		wanted2.origin += wanted2.basis * shake
		_kill_cam.global_transform = wanted2
	if _light != null:
		_light.global_transform = _creature.global_transform * _light_local


## Method-track target at t=0.02: attack anim + charge toward the lens.
func request_lunge() -> void:
	var creature: Node = get_parent()
	if creature == null:
		return
	var ap: AnimationPlayer = creature.get("_anim") as AnimationPlayer
	var lunge_anim: String = String(creature.get(lunge_anim_prop))
	if ap != null and lunge_anim != "":
		ap.play(lunge_anim)
	_charging = true
	_charge_left = charge_distance


## Method-track target at t=0.6: hold the roar pose for the face slam.
func request_roar() -> void:
	_charging = false
	var creature: Node = get_parent()
	if creature == null:
		return
	var ap: AnimationPlayer = creature.get("_anim") as AnimationPlayer
	var roar: String = String(creature.get("anim_roar"))
	if ap != null and roar != "":
		ap.play(roar)


## R26b: the hold block sets _bt_player.active = false every frame. The
## creature's own re-enables only run on feeding-respawn or void reset, so a
## jumpscare death (feeding skipped) left the behavior tree dead forever —
## the creature stood frozen after respawn ("creature got stuck" report).
func _release_bt(creature: Node) -> void:
	var btp: Node = creature.get("_bt_player") as Node
	if btp != null:
		btp.set("active", bool(creature.get("_awake")))


func _lock_player(locked: bool) -> void:
	var body: Node = get_tree().get_first_node_in_group("player")
	if body == null:
		return
	body.set_process(not locked)
	body.set_physics_process(not locked)
	_player_locked = locked


# ── Skeleton / default animation ─────────────────────────────────────────────

## Functional 2 s default: fov slam, handheld shake, light flash curve and a
## roar trigger. Designer-authored `anim_name` in the .tscn library replaces it.
func _build_default_anim() -> void:
	var a := Animation.new()
	a.length = 2.0
	a.loop_mode = Animation.LOOP_NONE

	# NOTE: AnimationMixer.root_node defaults to the mixer's PARENT — here the
	# director — so track paths are relative to the DIRECTOR: the camera/light
	# are its children (plain names) and the director itself is ".".
	# (R26b: the original "../" paths resolved one level too high and every
	# track warned "couldn't resolve"; the method track landed on the creature.)
	# FOV slam: wide → the FOV YOU authored on the camera node.
	var authored_fov: float = _kill_cam.fov
	var tf := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(tf, "CreatureKillCamera:fov")
	a.track_insert_key(tf, 0.0, minf(authored_fov * 1.45, 120.0))
	a.track_insert_key(tf, 0.22, authored_fov)

	# Handheld shake: small offsets AROUND YOUR AUTHORED CAMERA POSITION.
	# (R26c: keying absolute offsets around zero teleported the camera off
	# its placed spot — one of the two "weird place" causes.)
	var base_pos: Vector3 = _kill_cam.position
	var tp := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(tp, "CreatureKillCamera:position")
	var shake_keys := [
		[0.20, Vector3(0.0, 0.0, 0.0)],
		[0.24, Vector3(0.025, 0.018, 0.0)],
		[0.28, Vector3(-0.022, -0.015, 0.0)],
		[0.32, Vector3(0.018, 0.012, 0.0)],
		[0.36, Vector3(-0.014, -0.010, 0.0)],
		[0.42, Vector3(0.008, 0.006, 0.0)],
		[0.50, Vector3(0.0, 0.0, 0.0)],
	]
	for k in shake_keys:
		a.track_insert_key(tp, k[0], base_pos + k[1])

	# Light flash: 0 → peak → decay → out.
	# Light flash curve around YOUR authored energy (0 → yours → decay → 0).
	if _light != null:
		var authored_energy: float = _light.light_energy
		var tl := a.add_track(Animation.TYPE_VALUE)
		a.track_set_path(tl, "JumpscareLight:light_energy")
		a.track_insert_key(tl, 0.0, 0.0)
		a.track_insert_key(tl, 0.20, authored_energy)
		a.track_insert_key(tl, 0.50, authored_energy * 0.25)
		a.track_insert_key(tl, 1.50, 0.0)

	# Lunge-at-lens at the cut, then held roar for the face slam.
	# Method tracks target the DIRECTOR (= mixer root node, ".").
	var tm := a.add_track(Animation.TYPE_METHOD)
	a.track_set_path(tm, ".")
	a.track_insert_key(tm, 0.02, {"method": "request_lunge", "args": []})
	a.track_insert_key(tm, 0.60, {"method": "request_roar", "args": []})

	# AnimationPlayer stores animations in libraries; ensure the default one.
	var lib: AnimationLibrary
	if _anim.has_animation_library(""):
		lib = _anim.get_animation_library("")
	else:
		lib = AnimationLibrary.new()
		_anim.add_animation_library("", lib)
	lib.add_animation(anim_name, a)
