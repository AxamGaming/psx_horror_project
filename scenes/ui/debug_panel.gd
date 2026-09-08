extends PanelContainer
class_name DebugPanel
## ============================================================================
## DEBUG PANEL — functionality only. ALL layout lives in debug_panel.tscn
## (labels, sliders, option button, StyleBox — inspector-tweakable).
## Dev control surface for the gameplay hooks; ships hidden, F2 toggles.
## Opening releases the mouse (Events.ui_wants_mouse blocks click-recapture).
## ============================================================================

const JOLT_TIME := 0.35

var _rig: CameraRig
var _player: PlayerMovement
var _jolt_t: float = 0.0
var _refresh_timer: float = 0.0

@onready var _line1: Label = $VBox/Line1
@onready var _line2: Label = $VBox/Line2
@onready var _line3: Label = $VBox/Line3
@onready var _line4: Label = $VBox/Line4
@onready var _line5: Label = $VBox/Line5


func _ready() -> void:
	_rig = Events.main_camera as CameraRig
	if _rig != null:
		# rig -> HeadPivot -> Player (the established chain; gait lives here)
		_player = _rig.get_parent().get_parent() as PlayerMovement
	visible = false


# Scene-connected slider/option callbacks --------------------------------------

func _on_carry(v: float) -> void:
	if _rig != null:
		_rig.set_carry_weight(v)


func _on_stam(v: float) -> void:
	if _rig != null:
		_rig.set_stamina(v)


func _on_health(v: float) -> void:
	if _rig != null:
		_rig.set_health(v)


func _on_focus(idx: int) -> void:
	if _rig == null:
		return
	match idx:
		0:
			_rig.set_focus_mode(CameraRig.FocusMode.EXPLORING)
		1:
			_rig.set_focus_mode(CameraRig.FocusMode.INVENTORY)
		2:
			_rig.set_focus_mode(CameraRig.FocusMode.AIMING)


# Toggle + jolt + readout -------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action("debug_panel") and event.is_action_pressed("debug_panel"):
		visible = not visible
		Events.ui_wants_mouse = visible
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	# Jolt on damage while open (same 4.7 offset_transform trick as inventory).
	if _jolt_t > 0.0:
		_jolt_t = maxf(0.0, _jolt_t - delta)
		var k: float = _jolt_t / JOLT_TIME
		offset_transform_enabled = true
		offset_transform_position = Vector2(randf_range(-6.0, 6.0), randf_range(-4.0, 4.0)) * k
		offset_transform_rotation = randf_range(-1.5, 1.5) * k
	elif offset_transform_enabled:
		offset_transform_enabled = false
		offset_transform_position = Vector2.ZERO
		offset_transform_rotation = 0.0

	if not visible or _rig == null:
		return
	_refresh_timer -= delta
	if _refresh_timer > 0.0:
		return
	_refresh_timer = 0.1
	_line1.text = "energy %.2f | gait %s | carry %.2f" % [_rig.energy, _rig_gait_name(), _rig.carry_weight]
	_line2.text = "stamina %.2f | health %.2f | mass~%.2f" % [_rig.stamina, _rig.health01, _rig_mass()]
	_line3.text = "focus %s | suppress %.2f | fov %.1f" % [_rig_focus_name(), _rig.noise_suppress, _rig.fov]
	_update_creature_lines()


## Round-5 telemetry readout. Line4 starts with the creature BUILD_TAG: if the
## tag shown is not the newest one, the copied files are stale — instant check.
func _update_creature_lines() -> void:
	var ppos: Vector3 = Vector3.ZERO
	var onfl: bool = false
	if _player != null:
		ppos = _player.global_position
		onfl = _player.is_on_floor()
	_line4.text = "PLY (%.1f, %.1f, %.1f) floor=%s" % [ppos.x, ppos.y, ppos.z, str(onfl)]
	var cre: NightmareCreature = get_tree().get_first_node_in_group("creature") as NightmareCreature
	if cre == null:
		_line5.text = "CRE none in tree"
		return
	var st: Dictionary = cre.debug_state()
	var sp: Vector3 = st["pos"]
	_line5.text = "CRE %s d=%.1f (%.1f, %.1f, %.1f) %s%s anim=%s" % [
		String(st["tag"]), float(st["dist"]), sp.x, sp.y, sp.z,
		"AWK" if bool(st["awake"]) else "slp",
		"/NEU" if bool(st["neutralized"]) else "",
		String(st["anim"])]


func _rig_gait_name() -> String:
	if _player == null:
		return "-"
	match _player.gait:
		PlayerMovement.Gait.SPRINT:
			return "SPRINT"
		PlayerMovement.Gait.CROUCH:
			return "CROUCH"
		PlayerMovement.Gait.WALK:
			return "WALK"
		_:
			return "IDLE"


func _rig_focus_name() -> String:
	match _rig.focus_mode:
		CameraRig.FocusMode.INVENTORY:
			return "INVENTORY"
		CameraRig.FocusMode.AIMING:
			return "AIMING"
		_:
			return "EXPLORING"


func _rig_mass() -> float:
	# Approximate displayed mass (carry multiplier over base; daze adds more).
	return 1.0 + _rig.carry_weight * 0.6
