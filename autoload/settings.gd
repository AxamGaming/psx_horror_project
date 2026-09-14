extends Node
## ============================================================================
## SETTINGS — persisted player options (autoload, registered as "Settings").
##
## R30 added this for the kill-sequence accessibility dials: the director and
## the kill FX shader read these every frame instead of caching their own
## copies, so moving a slider mid-scare takes effect on the next frame and
## the value survives a restart (user://settings.cfg).
##
## Convention: every value here is a NORMALISED 0..1 "how much of this do I
## want" dial. Systems multiply their authored intensity by it — they never
## treat 0.0 as "use a default", 0.0 means OFF.
## ============================================================================

signal settings_changed

const CFG_PATH := "user://settings.cfg"
const CFG_SECTION := "settings"

## 0 = rock-steady kill cam, 1 = authored shake/whip/thrash strength.
@export_range(0.0, 1.0, 0.05) var camera_shake: float = 1.0
## 0 = no red flash / chromatic aberration / tear / smear on screen, 1 = full.
@export_range(0.0, 1.0, 0.05) var kill_fx: float = 1.0
## 0 = no blood particles or decals, 1 = full gore.
@export_range(0.0, 1.0, 0.05) var gore: float = 1.0
## Hard cap on full-screen flashes (photosensitivity safety). When ON the red
## flash is capped well below seizure-triggering levels regardless of kill_fx.
@export var reduce_flashes: bool = false

var _loaded: bool = false


func _ready() -> void:
	load_settings()
	_loaded = true


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) != OK:
		return   # first run: authored defaults stand
	camera_shake = clampf(float(cf.get_value(CFG_SECTION, "camera_shake", camera_shake)), 0.0, 1.0)
	kill_fx = clampf(float(cf.get_value(CFG_SECTION, "kill_fx", kill_fx)), 0.0, 1.0)
	gore = clampf(float(cf.get_value(CFG_SECTION, "gore", gore)), 0.0, 1.0)
	reduce_flashes = bool(cf.get_value(CFG_SECTION, "reduce_flashes", reduce_flashes))


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value(CFG_SECTION, "camera_shake", camera_shake)
	cf.set_value(CFG_SECTION, "kill_fx", kill_fx)
	cf.set_value(CFG_SECTION, "gore", gore)
	cf.set_value(CFG_SECTION, "reduce_flashes", reduce_flashes)
	cf.save(CFG_PATH)


func set_camera_shake(v: float) -> void:
	camera_shake = clampf(v, 0.0, 1.0)
	_emit_changed()


func set_kill_fx(v: float) -> void:
	kill_fx = clampf(v, 0.0, 1.0)
	_emit_changed()


func set_gore(v: float) -> void:
	gore = clampf(v, 0.0, 1.0)
	_emit_changed()


func set_reduce_flashes(v: bool) -> void:
	reduce_flashes = v
	_emit_changed()


## Photosensitivity clamp shared by every flashing system in the game.
func flash_cap() -> float:
	return 0.35 if reduce_flashes else 1.0


func _emit_changed() -> void:
	if _loaded:
		save_settings()
		settings_changed.emit()
