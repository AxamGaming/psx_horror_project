extends Node3D
class_name KillDirector
## ============================================================================
## KILL DIRECTOR — R30 rewrite of the creature-kill cutscene.
##
## WHY THE OLD ONE WASN'T GOOD ENOUGH (user verdict, R30):
##   it was a 2 s face-slam on rails — one lunge, one roar, one fixed camera.
##   No weight in the hit, no authored creature performance, no aftermath.
##
## WHAT THIS ONE DOES INSTEAD — a ~3.7 s cinematic in seven beats:
##   IMPACT  the blow lands: hard whip of the camera TOWARD the hit direction
##           with roll, on a real damped spring (impulse + stiffness/damping),
##           then it settles — that overshoot-then-settle IS the "got hit" read.
##   HANG    camera welds to the creature's head bone and pushes in slowly on
##           the jaws while the creature performance runs in SLOW-MO (warped
##           clock). The creature moves at 12 fps stepped poses; the camera is
##           perfectly smooth. That mismatch is the 1998 PSX read.
##   THRASH  the kill bite: screech, gore, handheld kicks.
##   CRASH   the creature THROWS you down (R31): hard gravity, horizon
##           tumble, a bounce chain with restitution falloff, and a landing
##           jolt on the whip spring — a heavy object, not a feather. The
##           SETTLE beat only ARMS the hand-off; the physics enters it once
##           the body has actually landed (a staged 0.5 s window used to cut
##           the fall mid-air and teleport the lens to the floor).
##   SETTLE  on the floor: breathing jitter, tilted horizon, the creature's
##           legs/shadow cross the frame, the pool creeps out.
##   FADE    slow desaturating fade -> death overlay (no auto-respawn: the
##           player gets a moment on the floor before R).
##
## ARCHITECTURE NOTES (the expensive lessons):
##  * ONE warped clock (_wt) drives BOTH AnimationPlayers via seek(t, true), so
##    slow-mo desyncs nothing: audio beats, light flashes and creature poses
##    all sit on the same authored timeline. seek() does NOT fire method
##    tracks (verified in tests/_seek_test.gd), so the director READS the
##    staging animation's method keys as a beat table and fires them itself —
##    designers still move beats in the animation panel and it just works.
##  * The creature's own GLB AnimationPlayer is deactivated for the duration;
##    two mixers writing one Skeleton3D is a fistfight with no winner.
##  * Camera shake obeys Settings.camera_shake; screen FX obey Settings.kill_fx
##    (see kill_fx.gd / settings.gd). 0 means OFF, never "default".
##
## R31 ADDENDA (playtest fixes):
##  * The kill starts FROM THE PLAYER'S VIEW (transform + FOV). It used to
##    re-read the authored scare-cam pose after capturing the player's, so
##    every kill hard-cut 1.8 m up the creature's face — read as the camera
##    "rising out of the floor". The only intentional rise left is the HANG
##    weld hoisting you toward the jaws.
##  * Footsteps can no longer follow you into the death menu: the player lock
##    calls PlayerMovement.freeze_corpse() (stale input_active/planar_speed
##    were keeping the rig's gait engine — and its footstep audio — alive).
## ============================================================================

const BODY_LIB_PATH := "res://scenes/enemies/kill_anim.tres"
const STAGE_LIB_PATH := "res://scenes/enemies/kill_staging.tres"

enum State { IDLE, IMPACT, HANG, THRASH, CRASH, SETTLE, FADE, HOLD }

# ── Designer dials ───────────────────────────────────────────────────────────
@export_group("Variants")
## "" = pick from the hit direction + dice. Set to force one in tests/shots.
@export_enum("auto", "kill_grab", "kill_swipe", "kill_slam") var force_variant: String = "auto"
@export var weight_grab: float = 1.0
@export var weight_swipe: float = 1.0
@export var weight_slam: float = 0.7

@export_group("Whip spring (impact)")
## Impulse handed to the spring at the blow (rad/s). The hard whip.
@export var whip_strength: float = 6.5
@export var whip_stiffness: float = 95.0
@export var whip_damping: float = 10.5
## How much of the sideways whip converts into head-roll (the neck snap).
@export_range(0.0, 2.0) var roll_coupling: float = 0.85
@export var roll_max_deg: float = 34.0

@export_group("Hang (slow-mo weld)")
@export_range(0.1, 1.0) var slowmo_speed: float = 0.55
## Authored-time window the warp applies to (the gape->bite anticipation).
@export var slowmo_from: float = 0.62
@export var slowmo_to: float = 1.55
## How fast the camera leaves the spring and takes the head weld (1/s).
@export var hang_rate: float = 9.0
## Slow dolly toward the jaws during HANG (metres over the whole hang).
@export var push_in: float = 0.22

@export_group("Crash & settle")
## R31 "heavy object" pass: harder gravity, a real bounce chain, a release
## THROW, airborne tumble, and a physics-driven SETTLE hand-off (the staged
## beat only arms it — the body must actually land first).
@export var fall_gravity: float = 14.5
@export_range(0.0, 0.6) var floor_restitution: float = 0.34
## Each bounce keeps this fraction of the previous restitution (0.5 = halves).
@export_range(0.0, 1.0) var restitution_falloff: float = 0.5
## Hard cap on bounces; a contact slower than bounce_stop_speed just lands.
@export_range(0, 5) var max_bounces: int = 2
@export var bounce_stop_speed: float = 0.55
## The release is a throw, not a placement: outward speed away from the
## creature + initial downward speed at the drop beat.
@export var crash_throw_out: float = 0.7
@export var crash_drop_v: float = 1.2
## Horizon tumble while airborne (deg/s) and how fast it dies after contact.
@export var crash_tumble_speed: float = 26.0
@export var crash_spin_damping: float = 5.5
## Rotation alignment toward the floor framing: lazy while airborne (heavy
## things don't steer mid-fall), snappy after first contact.
@export var crash_align_air: float = 1.6
@export var crash_align_ground: float = 6.5
## Tiny random sideways scatter per bounce (bodies don't bounce straight up).
@export var crash_scatter: float = 0.3
## Safety: if the ballistic sim somehow never lands, force SETTLE after this.
@export var crash_timeout: float = 1.6
## SETTLE must breathe at least this long before the fade may start.
@export var settle_before_fade: float = 0.5
@export var settle_tilt_deg: float = 71.0
@export var breath_hz: float = 0.42
@export var breath_amp: float = 0.021
## Creature walks this far across the lens during SETTLE (the legs/shadow).
@export var cross_distance: float = 1.5
@export var cross_speed: float = 1.15

@export_group("Sequence")
@export var fade_time: float = 1.1
## Softlock guard while parked on the death overlay. 0 disables.
@export var respawn_timeout_sec: float = 20.0
@export var use_jumpscare_light: bool = true

@export_group("Bones")
@export var head_bone_name: String = "Head_015"
@export var jaw_bone_name: String = "Jaw_016"

@export_group("Audio layers (dB)")
@export var db_impact_hit: float = 0.0
@export var db_sub_boom: float = -2.0
@export var db_metal_pierce: float = -6.0
@export var db_swing_whoosh: float = -8.0
@export var db_grab_cloth: float = -9.0
@export var db_screech_long: float = -8.0
@export var db_breath_close: float = -5.0
@export var db_riser: float = -8.0
@export var db_jaw_chomp: float = -2.0
@export var db_bone_crack: float = -3.0
@export var db_gore_slash: float = -6.0
@export var db_screech_bite: float = -4.0
@export var db_body_fall: float = -3.0
@export var db_sub_drop: float = -4.0
@export var db_tinnitus: float = -12.0
@export var db_stinger: float = -4.0

# ── Streams (the R30 library mix) ────────────────────────────────────────────
@export_group("Audio streams")
@export var sfx_impact_hit: AudioStream = preload("res://audio/sfx/jumpscare/js_impact_hit.wav")
@export var sfx_sub_boom: AudioStream = preload("res://audio/sfx/jumpscare/js_sub_boom.wav")
@export var sfx_metal_pierce: AudioStream = preload("res://audio/sfx/jumpscare/js_metal_pierce.wav")
@export var sfx_swing_whoosh: AudioStream = preload("res://audio/sfx/jumpscare/js_swing_whoosh.wav")
@export var sfx_grab_cloth: AudioStream = preload("res://audio/sfx/jumpscare/js_grab_cloth.wav")
@export var sfx_screech_long: AudioStream = preload("res://audio/sfx/jumpscare/js_screech_long.wav")
@export var sfx_breath_close: AudioStream = preload("res://audio/sfx/jumpscare/js_breath_close.wav")
@export var sfx_riser: AudioStream = preload("res://audio/sfx/jumpscare/js_riser.wav")
@export var sfx_jaw_chomp: AudioStream = preload("res://audio/sfx/jumpscare/js_jaw_chomp.wav")
@export var sfx_bone_crack: AudioStream = preload("res://audio/sfx/jumpscare/js_bone_crack.wav")
@export var sfx_gore_slash: AudioStream = preload("res://audio/sfx/jumpscare/js_gore_slash.wav")
@export var sfx_screech_bite: AudioStream = preload("res://audio/sfx/jumpscare/js_screech_bite.wav")
@export var sfx_body_fall: AudioStream = preload("res://audio/sfx/jumpscare/js_body_fall.wav")
@export var sfx_sub_drop: AudioStream = preload("res://audio/sfx/jumpscare/js_sub_drop.wav")
@export var sfx_tinnitus: AudioStream = preload("res://audio/sfx/jumpscare/js_tinnitus.wav")
@export var sfx_stinger: AudioStream = preload("res://audio/sfx/jumpscare/js_stinger_main.wav")

# ── Nodes ────────────────────────────────────────────────────────────────────
@onready var _kill_cam: Camera3D = get_node("CreatureKillCamera")
@onready var _light: Light3D = get_node_or_null("JumpscareLight")
@onready var _stage: AnimationPlayer = get_node("Staging")
@onready var _blood: BloodBurst = get_node_or_null("BloodBurst")

var _body: AnimationPlayer = null
var _fx: KillFX = null
var _skeleton: Skeleton3D = null
var _head_idx: int = -1
var _jaw_idx: int = -1
var _creature: Node3D = null
var _creature_anim: AnimationPlayer = null

# ── Sequence state ───────────────────────────────────────────────────────────
var _active: bool = false
var _state: int = State.IDLE
var _wt: float = 0.0
var _real_t: float = 0.0
var _variant: StringName = &"kill_grab"
var _beats: Array = []          # [[time, method], ...] read from staging
var _beat_idx: int = 0
var _hit_dir: Vector3 = Vector3(0, 0, 1)
var _side_sign: float = 1.0
var _base_xf: Transform3D = Transform3D()
var _cam_xf: Transform3D = Transform3D()
var _hang_k: float = 0.0
var _push_k: float = 0.0
var _fall_v: Vector3 = Vector3.ZERO
var _floor_y: float = 0.0
var _bounce_n: int = 0
var _crashed: bool = false
var _crash_t: float = 0.0
var _crash_spin: float = 0.0
var _spin_sign: float = 1.0
var _settle_pending: bool = false
var _fade_pending: bool = false
var _floor_xf: Transform3D = Transform3D()
var _settle_t: float = 0.0
var _fade_t: float = 0.0
var _cross_left: float = 0.0
var _cross_dir: Vector3 = Vector3.ZERO
var _hold_t: float = 0.0
var _prev_ui_wants_mouse: bool = false
var _players: Array[AudioStreamPlayer] = []
var _player_body: Node = null

# whip spring state (offsets in the pre-hit camera frame)
var _yaw: float = 0.0
var _yaw_v: float = 0.0
var _pitch: float = 0.0
var _pitch_v: float = 0.0
var _roll: float = 0.0
var _roll_v: float = 0.0
var _pos: Vector3 = Vector3.ZERO
var _pos_v: Vector3 = Vector3.ZERO
var _fov: float = 0.0
var _fov_v: float = 0.0
var _base_fov: float = 75.0


func _ready() -> void:
	# Exactly one director per creature (merged-scene guard, R28f).
	var parent: Node = get_parent()
	if parent != null:
		for c in parent.get_children():
			if c is KillDirector and c != self:
				if c.get_index() < get_index():
					push_warning("KillDirector: duplicate under %s - disabling %s." % [parent.name, name])
					set_process(false)
					return
	Events.player_killed_by_creature.connect(_on_creature_kill)
	Events.player_respawned.connect(_teardown)
	Events.respawn_requested.connect(_on_respawn_requested)
	_kill_cam.current = false
	if _light != null:
		_light.visible = false
	_creature = get_parent() as Node3D
	_resolve_skeleton()
	_build_body_player()
	_reload_beats_for_variant()
	_build_audio_pool()
	_fx = get_tree().get_first_node_in_group("kill_fx") as KillFX


func _process(delta: float) -> void:
	if _fx == null:
		_fx = get_tree().get_first_node_in_group("kill_fx") as KillFX
	if not _active:
		return
	_real_t += delta
	_advance_clock(delta)
	_sample_light(_wt)
	_fire_due_beats()
	_match_state()
	_step_spring(delta)
	match _state:
		State.IMPACT:
			_cam_impact_spring()
		State.HANG, State.THRASH:
			_cam_weld(delta)
		State.CRASH:
			_cam_crash(delta)
		State.SETTLE, State.FADE, State.HOLD:
			_cam_settle(delta)
	_kill_cam.global_transform = _cam_xf
	_kill_cam.fov = clampf(_base_fov + _fov, 40.0, 125.0)
	if _blood != null:
		_blood.grow_pool(delta)
	if respawn_timeout_sec > 0.0 and _state == State.HOLD:
		_hold_t += delta
		if _hold_t >= respawn_timeout_sec:
			push_warning("KillDirector: respawn_timeout on the death overlay — forcing respawn.")
			Events.respawn_requested.emit()


# ════════════════════════════════════════════════════════════════════════════
# SEQUENCE
# ════════════════════════════════════════════════════════════════════════════

func _on_creature_kill() -> void:
	if _active:
		return
	_active = true
	add_to_group("kill_active")
	_real_t = 0.0
	_wt = 0.0
	_beat_idx = 0
	_hold_t = 0.0
	_state = State.IMPACT

	# Who hit us, and from which side? (survival stamps both on damage.)
	_player_body = get_tree().get_first_node_in_group("player")
	var dir: Vector3 = Vector3.ZERO
	if _player_body != null:
		var sv: Node = _player_body.find_child("Survival", true, false)
		if sv != null and "last_damage_direction" in sv:
			dir = sv.get("last_damage_direction")
	if dir.length_squared() < 0.0001 and _creature != null and _player_body != null:
		dir = _player_body.global_position - _creature.global_position
	_hit_dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3(0, 0, 1)
	# The whip must start from where the PLAYER was looking, not from the
	# authored scare-cam pose (that pose is dead weight now: we drive the cam).
	# R31: the FOV base comes from the player lens too — snapping the wide
	# scare-cam FOV onto the player's view popped the lens on frame one.
	if Events.main_camera != null:
		_base_xf = Events.main_camera.global_transform
		_base_fov = Events.main_camera.fov
	else:
		_base_xf = _kill_cam.global_transform
		_base_fov = _kill_cam.fov
	_pick_variant()
	_reload_beats_for_variant()

	# Death overlay waits for the FADE beat, not for player_died.
	var overlay: Node = get_tree().get_first_node_in_group("death_overlay")
	if overlay != null and overlay.has_method("suppress_next"):
		overlay.call("suppress_next")

	# Freeze the creature AI + its gait mixer (two mixers, one skeleton = war).
	if _creature != null and "jumpscare_hold" in _creature:
		_creature.set("jumpscare_hold", true)
	_creature_anim = _find_creature_anim()
	if _creature_anim != null:
		_creature_anim.active = false
		_creature_anim.stop()

	# Camera authority + input lock.
	# R31 FIX (the "camera rises from the ground" report): this used to
	# re-read `_base_xf = _kill_cam.global_transform` HERE, throwing away the
	# player-view capture above — every kill hard-cut to the authored scare-cam
	# pose (1.8 m up, 2.25 m out along the creature's face) and then climbed
	# into the head weld. Now the kill cam SNAPS to the player's exact view
	# before taking over, so frame one of the kill is frame zero of the whip.
	_kill_cam.global_transform = _base_xf
	_kill_cam.fov = _base_fov
	if Events.main_camera != null:
		Events.main_camera.current = false
	_kill_cam.current = true
	_prev_ui_wants_mouse = Events.ui_wants_mouse
	Events.ui_wants_mouse = true
	_lock_player(true)

	# Reset the cinematic rig.
	_hang_k = 0.0
	_push_k = 0.0
	_bounce_n = 0
	_crashed = false
	_crash_t = 0.0
	_crash_spin = 0.0
	_spin_sign = 1.0 if randf() < 0.5 else -1.0
	_settle_pending = false
	_fade_pending = false
	_settle_t = 0.0
	_fade_t = 0.0
	_cross_left = 0.0
	_yaw = 0.0
	_yaw_v = 0.0
	_pitch = 0.0
	_pitch_v = 0.0
	_roll = 0.0
	_roll_v = 0.0
	_pos = Vector3.ZERO
	_pos_v = Vector3.ZERO
	_fov = 0.0
	_fov_v = 0.0
	_kill_cam.fov = _base_fov
	_cam_xf = _base_xf
	_floor_xf = _base_xf
	_floor_y = (_player_body.global_position.y + 0.16) if _player_body != null else _base_xf.origin.y - 1.6
	if _fx != null:
		_fx.reset()

	if use_jumpscare_light and _light != null:
		_light.visible = true
	# seek(update) only applies tracks while a current animation is set, so
	# play-then-pause once; the warped clock drives position from then on.
	# NOTE: the STAGING player is never played/seeked: a paused player re-fires
	# method-track callbacks on every seek(update), which made the last crossed
	# beat re-trigger every frame. Its method keys are read as a beat table and
	# its light curve is sampled by hand (_sample_light).
	if _body != null and _body.has_animation(_variant):
		_body.play(_variant)
		_body.pause()
	_seek_all(0.0)
	_sample_light(0.0)


func _pick_variant() -> void:
	if force_variant != "auto" and force_variant != "":
		_variant = StringName(force_variant)
	else:
		# Side of the blow: a hit from far off-axis reads as a swipe; dead-on
		# as a grab; and the dice occasionally drop the whole-body slam.
		var local: Vector3 = _base_xf.basis.inverse() * _hit_dir
		_side_sign = 1.0 if local.x >= 0.0 else -1.0
		var w_grab: float = weight_grab * (1.0 - minf(absf(local.x), 1.0) * 0.7)
		var w_swipe: float = weight_swipe * minf(absf(local.x) * 1.6, 1.0)
		var w_slam: float = weight_slam * 0.5
		var roll: float = randf() * (w_grab + w_swipe + w_slam)
		if roll < w_grab:
			_variant = &"kill_grab"
		elif roll < w_grab + w_swipe:
			_variant = &"kill_swipe"
		else:
			_variant = &"kill_slam"
	if _body != null and not _body.has_animation(_variant):
		push_warning("KillDirector: variant '%s' missing from %s — falling back." % [String(_variant), BODY_LIB_PATH])
		_variant = &"kill_grab"


func _on_respawn_requested() -> void:
	# The death overlay's R (or the softlock guard) while we're holding.
	if _active and _state == State.HOLD:
		# SurvivalSystem performs the reset; player_respawned tears us down.
		return
	if _active:
		_teardown()


# ════════════════════════════════════════════════════════════════════════════
# CLOCK / BEATS
# ════════════════════════════════════════════════════════════════════════════

## Re-read the table when the variant changes (each has its own staging clip).
func _reload_beats_for_variant() -> void:
	if _stage == null:
		return
	_beats.clear()
	if not _stage.has_animation(_variant):
		return
	var a: Animation = _stage.get_animation(_variant)
	for ti in range(a.get_track_count()):
		if a.track_get_type(ti) != Animation.TYPE_METHOD:
			continue
		for ki in range(a.track_get_key_count(ti)):
			var d: Dictionary = a.track_get_key_value(ti, ki)
			_beats.append([float(a.track_get_key_time(ti, ki)), String(d["method"])])
	_beats.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))


func _advance_clock(delta: float) -> void:
	var warp: float = 1.0
	if slowmo_from <= _wt and _wt < slowmo_to:
		warp = slowmo_speed
	_wt += delta * warp
	_seek_all(_wt)


func _seek_all(t: float) -> void:
	if _body != null and _body.has_animation(_variant):
		_body.seek(minf(t, _body.get_animation(_variant).length), true)


## Hand-rolled linear sample of the staging clip's scare-light curve, so the
## light flash stays on the warped clock without touching the staging player.
func _sample_light(t: float) -> void:
	if _light == null or not use_jumpscare_light:
		return
	if _stage == null or not _stage.has_animation(_variant):
		return
	var a: Animation = _stage.get_animation(_variant)
	for ti in range(a.get_track_count()):
		if a.track_get_type(ti) != Animation.TYPE_VALUE:
			continue
		if not String(a.track_get_path(ti)).ends_with("light_energy"):
			continue
		var n: int = a.track_get_key_count(ti)
		if n == 0:
			return
		if t <= a.track_get_key_time(ti, 0):
			_light.light_energy = float(a.track_get_key_value(ti, 0))
			return
		for ki in range(1, n):
			var t1: float = a.track_get_key_time(ti, ki)
			if t <= t1:
				var t0: float = a.track_get_key_time(ti, ki - 1)
				var v0: float = float(a.track_get_key_value(ti, ki - 1))
				var v1: float = float(a.track_get_key_value(ti, ki))
				var k: float = (t - t0) / maxf(t1 - t0, 0.0001)
				_light.light_energy = lerpf(v0, v1, k)
				return
		_light.light_energy = float(a.track_get_key_value(ti, n - 1))
		return


func _fire_due_beats() -> void:
	while _beat_idx < _beats.size() and float(_beats[_beat_idx][0]) <= _wt:
		var mname: String = String(_beats[_beat_idx][1])
		_beat_idx += 1
		if has_method(mname):
			call(mname)


func _match_state() -> void:
	var s: int = _state
	if s == State.IMPACT and _wt >= slowmo_from:
		_state = State.HANG
	elif s == State.HANG and _wt >= 1.95:
		_state = State.THRASH
	# THRASH/CRASH/SETTLE/FADE transitions happen inside their beat handlers.


# ════════════════════════════════════════════════════════════════════════════
# BEAT HANDLERS (names come from kill_staging.tres — do not rename lightly)
# ════════════════════════════════════════════════════════════════════════════

func beat_impact() -> void:
	var shake: float = Settings.camera_shake
	# Impulse INTO the spring: the camera whips toward the blow and rolls.
	var local: Vector3 = _base_xf.basis.inverse() * _hit_dir
	_yaw_v -= whip_strength * local.x * shake
	_pitch_v += whip_strength * 0.75 * local.y * shake
	_roll_v += whip_strength * roll_coupling * local.x * shake
	_pos_v -= local * (whip_strength * 0.06) * shake
	_fov_v += 130.0 * shake
	if _fx != null:
		_fx.impact(1.0)
	_play(sfx_impact_hit, db_impact_hit)
	_play(sfx_sub_boom, db_sub_boom)
	_play(sfx_metal_pierce, db_metal_pierce)
	_play(sfx_swing_whoosh, db_swing_whoosh - 3.0)
	if _blood != null and _player_body != null:
		_blood.burst(_player_body.global_position + Vector3(0, 1.35, 0), _hit_dir, 1.0)


func beat_grab() -> void:
	_play(sfx_grab_cloth, db_grab_cloth)
	_play(sfx_screech_long, db_screech_long)


func beat_gape() -> void:
	_play(sfx_riser, db_riser)
	_play(sfx_breath_close, db_breath_close)


func beat_lift() -> void:
	# Slam variant's anticipation beat (body hoists you).
	_play(sfx_riser, db_riser)
	_play(sfx_grab_cloth, db_grab_cloth - 2.0)


func beat_bite() -> void:
	if _fx != null:
		_fx.bite(1.0)
	_play(sfx_jaw_chomp, db_jaw_chomp)
	_play(sfx_bone_crack, db_bone_crack)
	_play(sfx_gore_slash, db_gore_slash)
	_play(sfx_screech_bite, db_screech_bite)
	_fov_v += 90.0 * Settings.camera_shake
	if _blood != null and _player_body != null:
		_blood.burst(_player_body.global_position + Vector3(0, 1.3, 0), _hit_dir, 0.7)


func beat_slowmo_end() -> void:
	# The warp ends here by clock design (slowmo_to); this beat is the hook for
	# anything that wants the exact frame the world speeds back up.
	pass


func beat_thrash() -> void:
	if _fx != null:
		_fx.tear_hit(0.6)
	_play(sfx_gore_slash, db_gore_slash - 3.0)


func beat_drop() -> void:
	_state = State.CRASH
	_crash_t = 0.0
	# R31: the release is a THROW — the body leaves the jaws with outward speed
	# and downward weight, so the fall reads as "dropped", never "lowered".
	# (At the weld the lens looks AT the jaws, so +z of its basis is "away".)
	var away: Vector3 = _cam_xf.basis.z
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = -_hit_dir
		away.y = 0.0
	if away.length_squared() < 0.0001:
		away = Vector3(0, 0, 1)
	_fall_v = away.normalized() * crash_throw_out \
			+ Vector3(randf_range(-0.2, 0.2), -crash_drop_v, randf_range(-0.2, 0.2))
	_play(sfx_swing_whoosh, db_swing_whoosh)
	if _fx != null:
		_fx.tear_hit(0.4)


func beat_settle() -> void:
	# R31: SETTLE is PHYSICS-driven — the staged beat only ARMS it. The body
	# must actually finish its bounce chain on the floor before the breathing
	# shot, the pool and the audio bed start. (The old hard cut fired 0.5 s
	# after the drop beat, mid-air: the lens teleported to the floor and the
	# bounce never happened.)
	_settle_pending = true
	if _crashed:
		_enter_settle()


func _enter_settle() -> void:
	_settle_pending = false
	_state = State.SETTLE
	_settle_t = 0.0
	_play(sfx_sub_drop, db_sub_drop)
	_play(sfx_tinnitus, db_tinnitus)
	if _blood != null and _player_body != null:
		_blood.pool_under(_player_body.global_position)
	if _creature != null:
		_cross_dir = _creature.global_transform.basis.x.normalized()
		_cross_left = cross_distance


func beat_fade() -> void:
	# Armed by the beat sheet, ENTERED by _cam_settle once the floor shot has
	# breathed for settle_before_fade — a late landing can't skip the fade.
	_fade_pending = true
	if _state == State.SETTLE and _settle_t >= settle_before_fade:
		_fade_pending = false
		_state = State.FADE
		_fade_t = 0.0


# ════════════════════════════════════════════════════════════════════════════
# CAMERA — spring, weld, crash, settle
# ════════════════════════════════════════════════════════════════════════════

func _step_spring(delta: float) -> void:
	# Semi-implicit Euler, substepped: stiff springs explode at 20 fps.
	var steps: int = 4
	var h: float = delta / float(steps)
	for _i in range(steps):
		_yaw_v += (-whip_stiffness * _yaw - whip_damping * _yaw_v) * h
		_yaw += _yaw_v * h
		_pitch_v += (-whip_stiffness * _pitch - whip_damping * _pitch_v) * h
		_pitch += _pitch_v * h
		_roll_v += (-whip_stiffness * _roll - whip_damping * _roll_v) * h
		_roll += _roll_v * h
		var pa: Vector3 = -_pos * whip_stiffness - _pos_v * whip_damping
		_pos_v += pa * h
		_pos += _pos_v * h
		_fov_v += (-whip_stiffness * 0.6 * _fov - whip_damping * _fov_v) * h
		_fov += _fov_v * h
	var rl: float = deg_to_rad(roll_max_deg)
	_roll = clampf(_roll, -rl, rl)


func _cam_impact_spring() -> void:
	var basis: Basis = _base_xf.basis * Basis.from_euler(Vector3(_pitch, _yaw, _roll), EULER_ORDER_YXZ)
	var origin: Vector3 = _base_xf.origin + _base_xf.basis * _pos
	_cam_xf = Transform3D(basis, origin)


func _head_xf() -> Transform3D:
	if _skeleton == null or _head_idx < 0:
		return _creature.global_transform if _creature != null else Transform3D()
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(_head_idx)


func _jaw_pos() -> Vector3:
	if _skeleton == null or _jaw_idx < 0:
		return _head_xf().origin
	return (_skeleton.global_transform * _skeleton.get_bone_global_pose(_jaw_idx)).origin


## Framing per variant: offset in creature space + what the lens looks at.
func _weld_target() -> Transform3D:
	var head: Transform3D = _head_xf()
	var cre_basis: Basis = _creature.global_transform.basis if _creature != null else Basis()
	var off: Vector3
	match _variant:
		&"kill_swipe":
			off = Vector3(-_side_sign * 0.62, -0.12, -0.82)
		&"kill_slam":
			off = Vector3(0.0, 0.42, -0.92)
		_:
			off = Vector3(0.0, -0.16, -1.02)
	var push: float = push_in * _push_k
	var origin: Vector3 = head.origin + cre_basis * (off * (1.0 - push * 0.55))
	var look: Vector3 = _jaw_pos() + Vector3(0, 0.06, 0)
	var dir: Vector3 = look - origin
	if dir.length_squared() < 0.0001:
		dir = -cre_basis.z
	var basis: Basis = Basis().looking_at(dir.normalized(), Vector3(0, 1, 0))
	return Transform3D(basis, origin)


func _cam_weld(delta: float) -> void:
	# First-order damped follow toward the weld (smooth cam, stepped creature).
	_hang_k = minf(1.0, _hang_k + delta * hang_rate * 0.35)
	_push_k = minf(1.0, _push_k + delta * 0.5)
	var target: Transform3D = _weld_target()
	var k: float = 1.0 - exp(-hang_rate * delta * minf(_hang_k * 3.0, 1.0))
	_cam_xf = _cam_xf.interpolate_with(target, k)
	# Spring leftovers + handheld noise ride on top so the weld never feels
	# robotic; the noise is the only "human" in an otherwise locked frame.
	var shake: float = Settings.camera_shake
	var n: Vector3 = _handheld(_real_t) * shake
	var rot: Basis = Basis.from_euler(Vector3(_pitch * 0.35 + n.x * 0.02, _yaw * 0.35 + n.y * 0.02, _roll * 0.5), EULER_ORDER_YXZ)
	_cam_xf = Transform3D(_cam_xf.basis * rot, _cam_xf.origin + _cam_xf.basis * (n * 0.03 + _pos * 0.25))
	if _state == State.THRASH and randf() < 0.06 * shake and _fx != null:
		_fx.tear_hit(0.35)


func _cam_crash(delta: float) -> void:
	_crash_t += delta
	if not _crashed:
		_fall_v.y -= fall_gravity * delta
		_cam_xf.origin += _fall_v * delta
		# Airborne tumble: the horizon slowly rolls while the body falls.
		_crash_spin += deg_to_rad(crash_tumble_speed) * delta * _spin_sign
		if _cam_xf.origin.y <= _floor_y:
			_cam_xf.origin.y = _floor_y
			var impact_v: float = absf(_fall_v.y)
			var rest: float = floor_restitution * pow(restitution_falloff, float(_bounce_n))
			if _bounce_n < max_bounces and impact_v * rest > bounce_stop_speed:
				# Still a bounce: heavy objects hit, kick back, hit again.
				_on_ground_hit(impact_v, _bounce_n == 0)
				_bounce_n += 1
				var sc: float = crash_scatter * (1.0 if _bounce_n == 1 else 0.35)
				_fall_v = Vector3(
					_fall_v.x * 0.45 + randf_range(-sc, sc),
					impact_v * rest,
					_fall_v.z * 0.45 + randf_range(-sc, sc))
			else:
				# Too slow to bounce: this contact is THE landing.
				_crashed = true
				_on_ground_hit(impact_v, false)
				_fall_v = Vector3.ZERO
				if _settle_pending:
					_enter_settle()
	# Safety net: a stuck sim must never hold the sequence (or the player)
	# hostage — force the landing and hand off.
	if not _crashed and _crash_t > crash_timeout:
		_cam_xf.origin.y = _floor_y
		_fall_v = Vector3.ZERO
		_crashed = true
		_play(sfx_body_fall, db_body_fall - 4.0)
		if _settle_pending:
			_enter_settle()
	# The tumble dies out once the body has met the floor.
	if _bounce_n > 0 or _crashed:
		_crash_spin *= exp(-crash_spin_damping * delta)
	# Rotation drifts to the floor framing (tilted horizon, looking up the
	# corridor at where the creature stands) — lazy while airborne, snappy
	# after first contact.
	var look: Vector3 = _creature.global_position if _creature != null else _cam_xf.origin - _cam_xf.basis.z
	look.y = _cam_xf.origin.y + 0.55
	var dir: Vector3 = look - _cam_xf.origin
	if dir.length_squared() < 0.0001:
		dir = Vector3(0, 0, -1)
	var up: Vector3 = Vector3(_side_sign * sin(deg_to_rad(settle_tilt_deg)), cos(deg_to_rad(settle_tilt_deg)), 0).normalized()
	var target_basis: Basis = Basis().looking_at(dir.normalized(), up)
	if absf(_crash_spin) > 0.0005:
		target_basis = target_basis * Basis.from_euler(Vector3(0, 0, _crash_spin))
	_floor_xf = Transform3D(target_basis, _cam_xf.origin)
	var rate: float = crash_align_ground if (_bounce_n > 0 or _crashed) else crash_align_air
	var k: float = 1.0 - exp(-rate * delta)
	_cam_xf = _cam_xf.interpolate_with(_floor_xf, k)
	# R31: the landing jolt lives on the whip spring — apply its leftovers
	# here, or _on_ground_hit kicks a spring nobody reads during CRASH
	# (that is why the old landing had no visible weight).
	var shake: float = Settings.camera_shake
	var jolt: Basis = Basis.from_euler(Vector3(_pitch * 0.5, _yaw * 0.25, _roll * 0.6), EULER_ORDER_YXZ)
	_cam_xf = Transform3D(_cam_xf.basis * jolt,
		_cam_xf.origin + _cam_xf.basis * (_pos * 0.2) + _handheld(_real_t) * shake * 0.004)


func _on_ground_hit(impact_v: float, first: bool) -> void:
	var shake: float = Settings.camera_shake
	# Thud loudness follows impact speed: the first slam is the mix peak,
	# every later contact is a fraction of it.
	var loud: float = linear_to_db(clampf(impact_v / 7.0, 0.3, 1.0))
	_play(sfx_body_fall, db_body_fall + loud + (2.0 if first else -5.0))
	if first:
		if _fx != null:
			_fx.crash(clampf(impact_v / 6.0, 0.45, 1.0))
		_play(sfx_sub_boom, db_sub_boom - 6.0)   # chest weight under the slam
		_roll_v += (2.2 + impact_v * 0.25) * shake * _spin_sign
		_pitch_v += (1.4 + impact_v * 0.2) * shake
		_fov_v += impact_v * 5.0 * shake
	else:
		_roll_v += 0.7 * shake * _spin_sign
		_pitch_v += 0.45 * shake
		_fov_v += impact_v * 2.0 * shake


func _cam_settle(delta: float) -> void:
	_settle_t += delta
	var shake: float = Settings.camera_shake
	# Breathing: slow sine + a hair of noise, scaled by the accessibility dial.
	var br: float = sin(_settle_t * TAU * breath_hz) * breath_amp * shake
	var br2: float = sin(_settle_t * TAU * breath_hz * 2.7 + 1.3) * breath_amp * 0.3 * shake
	var origin: Vector3 = _floor_xf.origin + Vector3(0, br + br2, 0)
	var tilt: Basis = Basis.from_euler(Vector3(br2 * 0.6, br * 0.4, 0.0), EULER_ORDER_YXZ)
	# R31: landing-jolt leftovers ride out on the whip spring (it decays to
	# zero in ~0.4 s) so the slam isn't visually cut the instant SETTLE starts.
	var jolt: Basis = Basis.from_euler(Vector3(_pitch * 0.5, _yaw * 0.25, _roll * 0.6), EULER_ORDER_YXZ)
	_cam_xf = Transform3D(_floor_xf.basis * tilt * jolt, origin + _floor_xf.basis * (_pos * 0.15))
	# The creature's legs/shadow cross the lens.
	if _cross_left > 0.0 and _creature != null:
		var step: float = minf(cross_speed * delta, _cross_left)
		_creature.global_position += _cross_dir * step
		_cross_left -= step
	# R31: the fade is armed by its beat but only ENTERS once the floor shot
	# has breathed for settle_before_fade — the crash owns its own ending.
	if _state == State.SETTLE and _fade_pending and _settle_t >= settle_before_fade:
		_fade_pending = false
		_state = State.FADE
		_fade_t = 0.0
	if _state == State.FADE:
		_fade_t += delta
		var k: float = clampf(_fade_t / maxf(fade_time, 0.05), 0.0, 1.0)
		if _fx != null:
			_fx.set_desat(k * 0.9)
			_fx.set_vignette(0.55 + 0.45 * k)
			_fx.set_fade(k * k)
		if k >= 1.0:
			_present_death()
	elif _state == State.SETTLE and _settle_t > 0.55:
		if _fx != null:
			_fx.set_vignette(minf(0.55, (_settle_t - 0.55) * 1.4))
			_fx.set_desat(minf(0.25, (_settle_t - 0.55) * 0.45))


func _present_death() -> void:
	_state = State.HOLD
	_hold_t = 0.0
	var overlay: Node = get_tree().get_first_node_in_group("death_overlay")
	if overlay != null and overlay.has_method("present"):
		overlay.call("present")


func _handheld(t: float) -> Vector3:
	return Vector3(
		sin(t * 7.3) * 0.5 + sin(t * 13.7 + 1.1) * 0.3,
		sin(t * 6.1 + 0.4) * 0.5 + sin(t * 11.3 + 2.2) * 0.3,
		sin(t * 5.2 + 1.7) * 0.4
	)


# ════════════════════════════════════════════════════════════════════════════
# TEARDOWN
# ════════════════════════════════════════════════════════════════════════════

func _teardown() -> void:
	if not _active:
		return
	_active = false
	remove_from_group("kill_active")
	_state = State.IDLE
	_settle_pending = false
	_fade_pending = false
	if _body != null:
		_body.stop()
	if _fx != null:
		_fx.reset()
	_kill_cam.current = false
	if Events.main_camera != null:
		Events.main_camera.current = true
	if _light != null:
		_light.visible = false
	_lock_player(false)
	Events.ui_wants_mouse = _prev_ui_wants_mouse
	for p in _players:
		p.stop()
	if _fx != null:
		_fx.reset()
	if _creature != null:
		if "jumpscare_hold" in _creature:
			_creature.set("jumpscare_hold", false)
		_release_bt(_creature)
	if _creature_anim != null:
		_creature_anim.active = true


func _release_bt(creature: Node) -> void:
	var btp: Node = creature.get("_bt_player") as Node
	if btp != null:
		btp.set("active", bool(creature.get("_awake")))


func _lock_player(locked: bool) -> void:
	var body: Node = get_tree().get_first_node_in_group("player")
	if body == null:
		return
	if locked and body.has_method("freeze_corpse"):
		# R31: republish a dead-still movement state BEFORE processing freezes —
		# stale input_active/planar_speed under the freeze kept the camera rig's
		# gait engine (and its footstep audio) running through the death menu.
		body.call("freeze_corpse")
	body.set_process(not locked)
	body.set_physics_process(not locked)


# ════════════════════════════════════════════════════════════════════════════
# WIRING
# ════════════════════════════════════════════════════════════════════════════

## find_children(..., owned=true) skips imported-instance children on some
## paths, and owned=false drags in unrelated subtrees; a plain recursion is
## both exact and cheap (runs once, in _ready).
func _find_first(n: Node, klass: StringName) -> Node:
	for c in n.get_children():
		if ClassDB.is_parent_class(c.get_class(), klass):
			return c
		var r: Node = _find_first(c, klass)
		if r != null:
			return r
	return null


func _resolve_skeleton() -> void:
	if _creature == null:
		return
	_skeleton = _find_first(_creature, "Skeleton3D") as Skeleton3D
	if _skeleton == null:
		return
	_head_idx = _skeleton.find_bone(head_bone_name)
	_jaw_idx = _skeleton.find_bone(jaw_bone_name)
	if _head_idx < 0:
		for i in range(_skeleton.get_bone_count()):
			if _skeleton.get_bone_name(i).contains("Head"):
				_head_idx = i
				break


## The body performance player has to hang off the Skeleton3D's PARENT (the
## track paths are "Skeleton3D:Bone"), and that node lives deep inside the
## imported GLB — so it is built at runtime, never authored in the .tscn.
func _build_body_player() -> void:
	var lib: AnimationLibrary = load(BODY_LIB_PATH) as AnimationLibrary
	if lib == null:
		push_error("KillDirector: %s failed to load — no creature performance." % BODY_LIB_PATH)
		return
	if _skeleton == null:
		push_error("KillDirector: no Skeleton3D under creature — kill anims unusable.")
		return
	var host: Node = _skeleton.get_parent()
	_body = AnimationPlayer.new()
	_body.name = "KillBodyAnim"
	host.add_child(_body)
	_body.root_node = NodePath("..")   # == host (NodePath is player-relative)
	_body.add_animation_library("", lib)
	_body.stop()


func _find_creature_anim() -> AnimationPlayer:
	if _creature == null:
		return null
	var n: Node = _find_first(_creature, "AnimationPlayer")
	while n != null and (n == _body or n == _stage):
		n = _find_next(n, "AnimationPlayer")
	return n as AnimationPlayer


func _find_next(after: Node, klass: StringName) -> Node:
	var n: Node = after.get_parent()
	var skip: Node = after
	while n != null and n != _creature:
		var idx: int = skip.get_index() + 1
		var kids: Array[Node] = n.get_children()
		for i in range(idx, kids.size()):
			if ClassDB.is_parent_class(kids[i].get_class(), klass):
				return kids[i]
			var r: Node = _find_first(kids[i], klass)
			if r != null:
				return r
		skip = n
		n = n.get_parent()
	return null


func _build_audio_pool() -> void:
	for i in range(16):
		var p := AudioStreamPlayer.new()
		p.name = "KillLayer%d" % i
		p.bus = &"SFX"
		add_child(p)
		_players.append(p)


func _play(stream: AudioStream, db: float) -> void:
	if stream == null:
		return
	for p in _players:
		if not p.playing:
			p.stream = stream
			p.volume_db = db
			p.pitch_scale = randf_range(0.97, 1.03)
			p.play()
			return
	_players[0].stream = stream
	_players[0].volume_db = db
	_players[0].play()
