class_name MouseLook
extends Node3D
## ============================================================================
## MOUSE LOOK — Phase 2. Lives on HeadPivot, a child of the Player body.
##
## SINGLE-WRITER RULE (Rule 1):
##   - This script owns HeadPivot.rotation.x (PITCH) — nothing else touches it.
##   - This script owns the Player body's rotation.y (YAW) — movement.gd only
##     ever writes position/velocity, never rotation.
##   - Roll is intentionally NEVER written here; CameraRig (Phase 3) owns roll
##     and applies it on the Camera3D itself, so aiming stays pixel-precise.
##
## STYLE NOTE (learned the hard way in 4.7): GDScript does NOT narrow types
## through `is` checks in compound conditions, so every InputEvent subtype is
## obtained with an explicit `as` cast into an explicitly typed local. Never
## use `:=` on anything derived from a base-typed `event`.
## ============================================================================

@export_group("Look")
## Degrees of rotation per pixel of mouse movement.
@export var sensitivity: float = 0.12
@export_range(10.0, 89.0) var pitch_limit_deg: float = 88.0
@export var invert_y: bool = false
@export var capture_mouse_on_start: bool = true

var _body: Node3D
var _dead: bool = false


func _ready() -> void:
	_body = get_parent() as Node3D
	assert(_body != null, "MouseLook must be a direct child of the player body (Node3D).")
	if capture_mouse_on_start:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Events.player_died.connect(_on_died)
	Events.player_respawned.connect(_on_respawned)


func _on_died() -> void:
	_dead = true


func _on_respawned() -> void:
	_dead = false


func _unhandled_input(event: InputEvent) -> void:
	if _dead:
		return   # corpse cam: look locked until respawn
	if event.is_action_pressed("ui_cancel"):
		_toggle_capture()
		return

	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		var deg_x: float = motion.relative.x * sensitivity
		_body.rotate_y(deg_to_rad(-deg_x))

		var pitch_dir: float = -1.0 if invert_y else 1.0
		var deg_y: float = motion.relative.y * sensitivity * pitch_dir
		rotate_x(deg_to_rad(-deg_y))

		var lim: float = deg_to_rad(pitch_limit_deg)
		rotation.x = clampf(rotation.x, -lim, lim)
		return

	var click: InputEventMouseButton = event as InputEventMouseButton
	if (
		click != null
		and click.pressed
		and not Events.ui_wants_mouse
		and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	):
		# Dev convenience: click to re-capture after pressing Esc.
		# Gated by Events.ui_wants_mouse so clicking the debug panel
		# (or future inventory UI) never yanks the cursor back.
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _toggle_capture() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
