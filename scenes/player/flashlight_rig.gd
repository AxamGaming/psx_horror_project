extends Node3D
## ============================================================================
## FLASHLIGHT RIG — Phase 8/9 (design doc: Flashlight & Lantern Sync).
##
## The light does NOT glue to the camera: this node lags behind the camera
## transform exponentially, so the beam sways and swims a beat behind head
## movement — shifting shadows in corridors, wandering beam while idle.
##
## NOTE (playtest decision): the electrical HUM was removed — real flashlights
## don't hum, and it added nothing. The mechanical CLICK stays. A future
## LANTERN item can reuse AudioMgr.play_world_sound() for a positioned buzz.
## The doc's "light synced to organic sway" lives in the lag below, not audio.
##
## F toggles. Light + click children are built in code (no .tscn churn).
## ============================================================================

@export var lag_rate: float = 14.0            # higher = lamp glued tighter to head
@export var hold_offset: Vector3 = Vector3(0.18, -0.14, -0.05)  # lamp held off the eye line
@export var light_energy: float = 5.0
@export var spot_angle_degrees: float = 28.0
@export var spot_range: float = 14.0

var _light: SpotLight3D
var _click: AudioStreamPlayer
var _cam: Camera3D
var _on: bool = false
var _dead: bool = false
var _gt: Transform3D   # OUR OWN smoothed global transform (see _process note)
var _gt_init: bool = false


func _ready() -> void:
	_cam = get_node("../HeadPivot/MainCamera") as Camera3D
	assert(_cam != null, "FlashlightRig: camera not found at ../HeadPivot/MainCamera.")
	Events.player_died.connect(_on_died)
	Events.player_respawned.connect(_on_respawned)

	_light = SpotLight3D.new()
	_light.light_energy = light_energy
	# Godot 4.7 name is plain `spot_angle` (degrees, ANGULAR RADIUS).
	_light.spot_angle = spot_angle_degrees
	_light.spot_range = spot_range
	_light.shadow_enabled = true
	_light.position = hold_offset
	_light.visible = false
	add_child(_light)

	_click = AudioStreamPlayer.new()
	_click.stream = load("res://audio/sfx/flashlight_click.wav") as AudioStream
	_click.bus = &"SFX"
	add_child(_click)


func _on_died() -> void:
	_dead = true


func _on_respawned() -> void:
	_dead = false


func _process(delta: float) -> void:
	if _cam == null or _dead:
		return
	if not _gt_init:
		_gt = _cam.global_transform
		_gt_init = true
	# IMPORTANT: we smooth OUR OWN stored transform, not this node's current
	# global_transform. Reading the node's transform re-injects the parent
	# body's yaw every frame (shared ancestor = instant yaw, no lag) — that
	# bug made the lamp lag vertically but snap horizontally. With private
	# state, the assignment counter-rotates the parent and EVERY axis lags.
	var k: float = 1.0 - exp(-lag_rate * delta)
	_gt = _gt.interpolate_with(_cam.global_transform, k)
	global_transform = _gt


func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action("flashlight") and event.is_action_pressed("flashlight"):
		_on = not _on
		_light.visible = _on
		_click.play()
