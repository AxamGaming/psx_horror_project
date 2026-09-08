extends Control
class_name SurvivalHUD
## ============================================================================
## SURVIVAL HUD — contextual, genre-normal compromise (see design doc: the
## camera itself is the primary body-state indicator; these bars only SURFACE
## it when relevant, then get out of the way).
##
## Behavior: stamina bar fades in while draining OR recovering and fades out
## ~2 s after it settles; health bar fades in when injured and fades out
## ~4 s after the last damage. Persistent-HD-HUD fans can set
## `always_visible` in the inspector.
##
## Layout/styles live in survival_hud.tscn (ProgressBar + StyleBoxes).
## ============================================================================

@export var always_visible: bool = false
@export var stamina_hide_delay: float = 2.0
@export var health_hide_delay: float = 4.0

@onready var _stam_bar: ProgressBar = $StaminaBar
@onready var _health_bar: ProgressBar = $HealthBar

var _rig: CameraRig
var _stam_hold: float = 0.0
var _health_hold: float = 0.0
var _prev_stam: float = 1.0
var _prev_hp: float = 1.0


func _ready() -> void:
	_rig = Events.main_camera as CameraRig
	_stam_bar.modulate = Color(1, 1, 1, 0)
	_health_bar.modulate = Color(1, 1, 1, 0)
	Events.player_damaged.connect(_on_damaged)


func _on_damaged(_amount: float, _direction: Vector3) -> void:
	_health_hold = health_hide_delay


func _process(delta: float) -> void:
	if _rig == null:
		return
	# --- stamina: surface while it moves, hide once settled ---
	var stam: float = _rig.stamina
	_stam_bar.value = stam * 100.0
	if absf(stam - _prev_stam) > 0.0004:
		_stam_hold = stamina_hide_delay
	else:
		_stam_hold = maxf(0.0, _stam_hold - delta)
	_prev_stam = stam
	_fade(_stam_bar, _stam_hold > 0.0, delta)

	# --- health: surface on damage AND on healing (medkit use must be visible),
	#     fade out after the delay once the value settles ---
	var hp: float = _rig.health01
	_health_bar.value = hp * 100.0
	if absf(hp - _prev_hp) > 0.0004:
		_health_hold = health_hide_delay   # value moved either way: show the bar
	_prev_hp = hp
	_health_hold = maxf(0.0, _health_hold - delta)
	_fade(_health_bar, _health_hold > 0.0, delta)


func _fade(bar: ProgressBar, want: bool, delta: float) -> void:
	var target: float = 1.0 if (want or always_visible) else 0.0
	var k: float = 1.0 - exp(-6.0 * delta)
	bar.modulate = Color(1, 1, 1, lerpf(bar.modulate.a, target, k))
