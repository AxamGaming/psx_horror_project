extends Node3D
## ============================================================================
## HEAVY DOOR — Phase 9 (design doc: environmental kinetic triggers).
##
## Stand in the trigger, press E: the door swings on its hinge with a slow,
## heavy ease (1.6 s sine in-out), the creak plays POSITIONALLY through
## AudioMgr.play_world_sound() (panned + attenuated by the 2.5D pool), and the
## camera gets a small spring NUDGE (not a combat impulse: no noise
## suppression, no FOV punch) — the doc's "interacting with a heavy iron door
## applies a low-frequency thud to the camera".
##
## Node contract (built in test_graybox.tscn):
##   DoorAssembly (this script)
##   ├─ PostA / PostB / Lintel   (StaticBody3D frame)
##   ├─ Hinge (Node3D) ─ Door (StaticBody3D panel)
##   └─ DoorTrigger (Area3D)
## ============================================================================

@export var open_angle_deg: float = -100.0
@export var swing_time: float = 1.6
@export var nudge_magnitude: float = 0.7
@export var creak_volume_db: float = -6.0

var _hinge: Node3D
var _trigger: Area3D
var _open: bool = false
var _busy: bool = false
var _player_inside: bool = false


func _ready() -> void:
	_hinge = get_node("Hinge") as Node3D
	_trigger = get_node("DoorTrigger") as Area3D
	assert(_hinge != null, "HeavyDoor: missing Hinge (Node3D) child.")
	assert(_trigger != null, "HeavyDoor: missing DoorTrigger (Area3D) child.")
	_trigger.body_entered.connect(_on_entered)
	_trigger.body_exited.connect(_on_exited)


func _on_entered(body: Node3D) -> void:
	if body is PlayerMovement:
		_player_inside = true


func _on_exited(body: Node3D) -> void:
	if body is PlayerMovement:
		_player_inside = false


func _unhandled_input(event: InputEvent) -> void:
	if _busy or not _player_inside:
		return
	if InputMap.has_action("interact") and event.is_action_pressed("interact"):
		_busy = true
		_open = not _open
		get_viewport().set_input_as_handled()   # E near door+item: one action per press
		# Positional creak from the door itself.
		AudioMgr.play_world_sound(AudioMgr.stream_door_creak, global_position, creak_volume_db)
		# Heavy mechanical feedback on the camera spring.
		var cam: Camera3D = Events.main_camera
		if cam != null and is_instance_valid(cam):
			var rig: CameraRig = cam as CameraRig
			if rig != null:
				rig.apply_nudge(global_position - rig.global_position, nudge_magnitude)
		var tw: Tween = create_tween()
		tw.set_trans(Tween.TRANS_SINE)
		tw.set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(_hinge, "rotation_degrees:y", open_angle_deg if _open else 0.0, swing_time)
		tw.tween_callback(_on_swing_done)


func _on_swing_done() -> void:
	_busy = false
