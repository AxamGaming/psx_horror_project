extends CanvasLayer
class_name KillFX
## ============================================================================
## KILL FX (R30) — the screen-side half of the creature kill.
##
## CanvasLayer 4 in main.tscn: above the VHS tape pass (2) and the HUD (1),
## below the crisp UI (10) so menus/inventory never get bloodied.
##
## Contract: the KillDirector pokes EVENTS (impact(), crash(), tear_hit()) and
## drives the NARRATIVE channels (set_vignette / set_smear / set_desat /
## set_fade) with its own curves. This node owns only the transient decay
## curves, so the director never has to think about exponential falloff.
##
## Accessibility: every EFFECT channel is multiplied by Settings.kill_fx and
## every FLASH is capped by Settings.flash_cap() (the photosensitivity dial).
## The narrative fade is never gated — the story has to land either way.
## ============================================================================

## Exponential decay half-lives (seconds). Short = snappy, horror wants snappy.
@export_group("Decay half-lives (s)")
@export var flash_decay: float = 0.11
@export var chroma_decay: float = 0.26
@export var tear_decay: float = 0.18
@export var jolt_decay: float = 0.09

@onready var _rect: ColorRect = get_node("Rect")
@onready var _mat: ShaderMaterial = get_node("Rect").material as ShaderMaterial

var _flash: float = 0.0
var _chroma: float = 0.0
var _tear: float = 0.0
var _jolt: float = 0.0
var _vign: float = 0.0
var _smear: float = 0.0
var _desat: float = 0.0
var _grain: float = 0.0
var _fade: float = 0.0
var _clock: float = 0.0


func _ready() -> void:
	add_to_group("kill_fx")
	# Visible-but-inert at rest: at zero uniforms the shader is a plain screen
	# copy, so there is no pop when the first scare starts.
	visible = true
	reset()


func reset() -> void:
	_flash = 0.0
	_chroma = 0.0
	_tear = 0.0
	_jolt = 0.0
	_vign = 0.0
	_smear = 0.0
	_desat = 0.0
	_grain = 0.0
	_fade = 0.0
	_push()


# ── Events (transient, self-decaying) ────────────────────────────────────────

## The blow: red bloom + aberration spike + sub-pixel jolt.
func impact(power: float = 1.0) -> void:
	var cap: float = Settings.flash_cap()
	_flash = maxf(_flash, minf(0.95 * power, cap))
	_chroma = maxf(_chroma, 0.9 * power)
	_jolt = maxf(_jolt, 14.0 * power)
	_tear = maxf(_tear, 0.5 * power)


## The bite: second, nastier hit — more tear, less bloom (it's inside you now).
func bite(power: float = 1.0) -> void:
	var cap: float = Settings.flash_cap()
	_flash = maxf(_flash, minf(0.7 * power, cap))
	_chroma = maxf(_chroma, 1.0 * power)
	_tear = maxf(_tear, 0.85 * power)
	_jolt = maxf(_jolt, 18.0 * power)


## The crash to the floor: lens gets dirty and the tape gives up.
func crash(power: float = 1.0) -> void:
	_smear = maxf(_smear, 0.9 * power)
	_grain = maxf(_grain, 0.9 * power)
	_jolt = maxf(_jolt, 10.0 * power)
	_tear = maxf(_tear, 0.6 * power)


## A single torn-band hit (thrash beats).
func tear_hit(power: float = 0.5) -> void:
	_tear = maxf(_tear, power)
	_jolt = maxf(_jolt, 6.0 * power)


# ── Narrative channels (director-curves, held until changed) ─────────────────

func set_vignette(v: float) -> void:
	_vign = clampf(v, 0.0, 1.0)


func set_smear(v: float) -> void:
	_smear = clampf(v, 0.0, 1.0)


func set_grain(v: float) -> void:
	_grain = clampf(v, 0.0, 1.0)


func set_desat(v: float) -> void:
	_desat = clampf(v, 0.0, 1.0)


func set_fade(v: float) -> void:
	_fade = clampf(v, 0.0, 1.0)


func _process(delta: float) -> void:
	_clock += delta
	_flash = _decay(_flash, flash_decay, delta)
	_chroma = _decay(_chroma, chroma_decay, delta)
	_tear = _decay(_tear, tear_decay, delta)
	_jolt = _decay(_jolt, jolt_decay, delta)
	_push()


func _decay(v: float, half: float, delta: float) -> float:
	if v <= 0.0005:
		return 0.0
	if half <= 0.001:
		return 0.0
	return v * pow(0.5, delta / half)


func _push() -> void:
	if _mat == null:
		return
	var fx: float = Settings.kill_fx
	_mat.set_shader_parameter("flash", _flash * fx)
	_mat.set_shader_parameter("chroma", _chroma * fx)
	_mat.set_shader_parameter("tear", _tear * fx)
	_mat.set_shader_parameter("jolt_px", _jolt * fx)
	_mat.set_shader_parameter("vignette", _vign * fx)
	_mat.set_shader_parameter("smear", _smear * fx)
	_mat.set_shader_parameter("grain", _grain * fx)
	_mat.set_shader_parameter("desat", _desat)
	_mat.set_shader_parameter("fade", _fade)
	_mat.set_shader_parameter("clock", fmod(_clock, 1000.0))
