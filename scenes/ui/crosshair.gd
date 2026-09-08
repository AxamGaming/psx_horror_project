extends Control
class_name Crosshair
## ============================================================================
## CROSSHAIR — downloaded CC0 marks (LoneCoder's 64-crosshairs pack, split).
## normal_tex = bare dust dot; aim_tex = ring+dot when a weapon is aiming.
## Grayscale source: tint via `tint` (scene-editable). Fades out when the
## mouse is released to UI or on death. Two instances live in main.tscn
## (HUD layer = fully VHS-degraded, UI layer at 70% alpha = crisp) so the
## perceived result is ~30% shader-affected, per design feedback.
## ============================================================================

@export var normal_tex: Texture2D
@export var aim_tex: Texture2D
@export var tint: Color = Color(0.92, 0.87, 0.74, 1)
@export var idle_alpha: float = 0.55
@export var aim_alpha: float = 0.9
@export var alpha_mix: float = 1.0   # 0.7 on the crisp-layer instance = 70/30 crisp/degraded blend

@onready var _mark: TextureRect = $Mark

var _dead: bool = false


func _ready() -> void:
	_mark.texture = normal_tex
	_mark.modulate = tint
	Events.player_died.connect(_on_died)
	Events.player_respawned.connect(_on_respawned)


func _on_died() -> void:
	_dead = true


func _on_respawned() -> void:
	_dead = false


func _process(_delta: float) -> void:
	var target: float = idle_alpha
	var aiming: bool = false
	if _dead or Events.ui_wants_mouse:
		target = 0.0
	else:
		var rig: CameraRig = Events.main_camera as CameraRig
		if rig != null and rig.focus_mode == CameraRig.FocusMode.AIMING:
			aiming = true
			target = aim_alpha
	_mark.texture = aim_tex if aiming else normal_tex
	modulate = Color(1, 1, 1, lerpf(modulate.a, target, 0.15) * alpha_mix)
