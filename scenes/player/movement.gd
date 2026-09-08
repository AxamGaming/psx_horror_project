class_name PlayerMovement
extends CharacterBody3D
## ============================================================================
## PLAYER MOVEMENT — Phase 1 foundation.
##
## SINGLE-WRITER RULE (IMPLEMENTATION_PLAN.md, Rule 1):
##   - This script owns the body's POSITION / VELOCITY only.
##   - Body YAW + HeadPivot PITCH are owned by MouseLook.
##   - The Camera3D's LOCAL transform will be owned exclusively by CameraRig
##     (Phase 3). This script must never touch the camera.
##
## The public state variables below are READ-ONLY for other systems
## (camera rig, audio). Nobody writes them except this script.
## ============================================================================

enum Gait { IDLE, WALK, SPRINT, CROUCH }

@export_group("Speeds (m/s)")
@export var walk_speed: float = 2.2      # realism pass: 3.0 read as brisk mall-walk; real walk ~1.4, horror exploration ~2.0-2.4
@export var sprint_speed: float = 4.5    # panic sprint, still controllable (all-out human ~5.5)
@export var crouch_speed: float = 1.0
## Smoothing rates (higher = snappier). Applied frame-rate independently.
@export var acceleration: float = 10.0   # slightly heavier start/stop for weight
@export var deceleration: float = 12.0
@export_range(0.0, 1.0) var air_control: float = 0.35
@export var sprint_requires_forward: bool = true

@export_group("Gravity & Landing")
## Slightly heavier than real gravity (9.8) for horror "weight".
@export var gravity: float = 18.0
@export var max_fall_speed: float = 40.0
## Downward speed (m/s) at touchdown that counts as a HARD landing.
@export var hard_landing_speed: float = 7.0

@export_group("Jump (test aid)")
## Jump exists only so we can test landing reactions in the graybox.
## Disable it if the final game has no jumping.
@export var allow_jump: bool = true
@export var jump_speed: float = 4.2

@export_group("Crouch")
@export var stand_height: float = 1.8
@export var crouch_height: float = 1.1
@export_range(0.5, 1.0) var eye_height_ratio: float = 0.9
@export var crouch_lerp_rate: float = 10.0

# --- Public read-only state ---------------------------------------------------
var gait: Gait = Gait.IDLE
var planar_speed: float = 0.0
var fall_speed_at_impact: float = 0.0
var is_sprinting: bool = false
var is_crouched: bool = false
## True only while a movement key is actually held this physics frame.
## Footsteps/step-phase gate on this, so no footfall ever fires after release.
var input_active: bool = false
## How loud the player is right now (0..1) — creature hearing scales with it.
var noise_level: float = 0.0
## Set by environmental zones (crawlspace Area3Ds): forces crouch regardless
## of input, and blocks standing up while inside.
var external_crouch: bool = false
## Set by SurvivalSystem: stamina empty -> sprint refused.
var exhausted: bool = false
## Set by SurvivalSystem on death: input frozen, body settles.
var dead: bool = false

# --- Internals ----------------------------------------------------------------
# Explicit casts, no `:=` inference, no declaration-order dependencies
# (same lesson as mouse_look.gd: keep the analyzer 100% certain of every type).
@onready var _body_collision: CollisionShape3D = get_node("BodyCollision") as CollisionShape3D
@onready var _head_pivot: Node3D = get_node("HeadPivot") as Node3D
@onready var _capsule: CapsuleShape3D = (get_node("BodyCollision") as CollisionShape3D).shape as CapsuleShape3D

var _current_height: float = 1.8
var _was_on_floor: bool = false
var _wall_cd: float = 0.0


func _ready() -> void:
	add_to_group("player")
	_current_height = stand_height
	_apply_height(stand_height)


func _physics_process(delta: float) -> void:
	if dead:
		# Corpse: no input, gravity still applies so the body settles.
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y = maxf(velocity.y - gravity * delta, -max_fall_speed)
		move_and_slide()
		return
	_handle_crouch(delta)
	_apply_gravity(delta)
	_apply_horizontal_movement(delta)
	_handle_jump()

	# Capture fall speed BEFORE move_and_slide resolves the landing.
	var pre_move_fall := maxf(-velocity.y, 0.0)
	var pre_planar_v := Vector3(velocity.x, 0.0, velocity.z)
	move_and_slide()
	_detect_landing(pre_move_fall)
	_detect_wall_slam(pre_planar_v, delta)
	_update_gait_state()


## Design doc: "running full speed into a wall ... applies a continuous,
## low-frequency thudding". Emits a positional slam event (audio + camera
## nudge) when the body hits geometry while moving in fast enough.
func _detect_wall_slam(pre_planar_v: Vector3, delta: float) -> void:
	_wall_cd = maxf(0.0, _wall_cd - delta)
	if _wall_cd > 0.0:
		return
	var speed: float = pre_planar_v.length()
	if speed < 2.8 or get_slide_collision_count() == 0:
		return
	var collision: KinematicCollision3D = get_slide_collision(0)
	var normal: Vector3 = collision.get_normal()
	if normal.dot(pre_planar_v.normalized()) < -0.4:
		_wall_cd = 0.4
		Events.wall_hit.emit(collision.get_position(), clampf(speed / 6.0, 0.2, 1.0))


func _apply_gravity(delta: float) -> void:
	if is_on_floor() and velocity.y <= 0.0:
		# Tiny downward bias keeps the body glued to floors/slopes.
		velocity.y = -0.5
	else:
		velocity.y = maxf(velocity.y - gravity * delta, -max_fall_speed)


func _apply_horizontal_movement(delta: float) -> void:
	var input_dir := Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back"
	)
	var wants_move := input_dir.length_squared() > 0.01
	input_active = wants_move

	# get_vector returns y = back - forward, so forward input => local -Z,
	# which is exactly where the camera faces. (No sign bugs. Trust this.)
	var direction := Vector3.ZERO
	if wants_move:
		direction = (global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	is_sprinting = (
		wants_move
		and Input.is_action_pressed("sprint")
		and not is_crouched
		and not exhausted
	)
	if is_sprinting and sprint_requires_forward:
		is_sprinting = input_dir.y < -0.2

	var target_speed := walk_speed
	if is_crouched:
		target_speed = crouch_speed
	elif is_sprinting:
		target_speed = sprint_speed

	var target := direction * target_speed
	var rate := acceleration if wants_move else deceleration
	if not is_on_floor():
		rate *= air_control

	# Frame-rate independent exponential smoothing (Rule 3) — never lerp(a,b,delta*k).
	var t := 1.0 - exp(-rate * delta)
	velocity.x = lerpf(velocity.x, target.x, t)
	velocity.z = lerpf(velocity.z, target.z, t)
	planar_speed = Vector2(velocity.x, velocity.z).length()


func _handle_jump() -> void:
	if allow_jump and is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = jump_speed


## Horizontal shove from creature attacks etc.
func apply_knockback(dir: Vector3, force: float) -> void:
	velocity += Vector3(dir.x, 0.0, dir.z).normalized() * force


func _handle_crouch(delta: float) -> void:
	if Input.is_action_pressed("crouch") or external_crouch:
		is_crouched = true
	elif not external_crouch and _can_stand_up():
		is_crouched = false

	var target_h := crouch_height if is_crouched else stand_height
	_current_height = lerpf(_current_height, target_h, 1.0 - exp(-crouch_lerp_rate * delta))
	_apply_height(_current_height)


func _can_stand_up() -> bool:
	if not is_crouched:
		return true
	# Would the capsule hit a ceiling if we grew back to standing height?
	# (Simple graybox check — will be replaced by a proper ShapeCast in Phase 9.)
	return not test_move(global_transform, Vector3.UP * (stand_height - _current_height))


func _apply_height(h: float) -> void:
	h = maxf(h, _capsule.radius * 2.0 + 0.01)
	_capsule.height = h
	_body_collision.position.y = h * 0.5
	_head_pivot.position.y = h * eye_height_ratio


func _detect_landing(pre_move_fall: float) -> void:
	var grounded := is_on_floor()
	if grounded and not _was_on_floor:
		fall_speed_at_impact = pre_move_fall
		if pre_move_fall >= hard_landing_speed:
			# 0 at threshold, 1.0 at threshold+8 m/s (~2 m extra fall).
			var energy := clampf((pre_move_fall - hard_landing_speed) / 8.0, 0.0, 1.0)
			Events.hard_landed.emit(energy)
	_was_on_floor = grounded


func _update_gait_state() -> void:
	# Noise footprint for creature hearing (sprint > walk > crouch > still).
	if not input_active or planar_speed < 0.2:
		noise_level = 0.06
	elif is_crouched:
		noise_level = 0.15
	elif is_sprinting:
		noise_level = 1.0
	else:
		noise_level = 0.5
	# Note: flicker protection lives in the camera rig's smoothed "energy"
	# value (Phase 3), so these thresholds can stay simple.
	if is_crouched:
		gait = Gait.CROUCH
	elif planar_speed < 0.3:
		gait = Gait.IDLE
	elif is_sprinting:
		gait = Gait.SPRINT
	else:
		gait = Gait.WALK
