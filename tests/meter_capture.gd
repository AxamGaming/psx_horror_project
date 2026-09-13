extends SceneTree
## ============================================================================
## METER CAPTURE (dev tool — never runs in the shipped game).
##
## Renders the noise meter at a sweep of loudness values and saves cropped
## strip images to user://meter_cap/, for art review of the gradient, ticks,
## rounded corners and bleed treatment without playing the game.
##
## Run (needs a framebuffer, so Xvfb on a headless box):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --fixed-fps 60 \
##       --quit-after 200 -s res://tests/meter_capture.gd
##
## Output: user://meter_cap/strip_v<NNN>.png  (globalized path is printed)
##
## Stages per level: 0 = set value, 1 = let the bar redraw + overlay resample,
## 2 = grab the framebuffer region and advance. Grabbing on the same frame the
## value is set would capture the previous level's pixels.
## ============================================================================

const LEVELS := [0.0, 0.15, 0.5, 0.72, 0.9, 1.0]
const OUT_DIR := "user://meter_cap/"
const MARGIN := 14

var _started := false
var _meter: Control = null
var _idx := 0
var _stage := 0


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		DirAccess.make_dir_recursive_absolute(OUT_DIR)

		var bg := ColorRect.new()
		bg.color = Color(0.13, 0.12, 0.11)   # horror-dark backdrop to sample
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		var bl := CanvasLayer.new()
		bl.layer = 1
		root.add_child(bl)
		bl.add_child(bg)

		var scene: PackedScene = load("res://scenes/ui/noise_meter.tscn")
		var layer := CanvasLayer.new()
		layer.layer = 10
		root.add_child(layer)
		_meter = scene.instantiate()
		layer.add_child(_meter)
		_meter.set_deferred("size", Vector2(1280, 720))
		var bar: Control = _meter.get_node("Bar")
		bar.set_deferred("size", Vector2(240, 16))
		# Pin the value: zero the lerp rates so _update_noise() cannot drag the
		# previewed value back toward a baseline between capture frames.
		_meter.rise_speed = 0.0
		_meter.fall_speed = 0.0
		return false

	if _idx >= LEVELS.size():
		quit()
		return true

	match _stage:
		0:
			_meter.preview_noise(LEVELS[_idx])
			_meter.set("_fade", 1.0)
			_stage = 1
		1:
			_stage = 2
		2:
			_save_strip(LEVELS[_idx])
			_idx += 1
			_stage = 0
	return false


func _save_strip(v: float) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var bar: Control = _meter.get_node("Bar")
	var r: Rect2 = bar.get_global_rect()
	var crop := Rect2i(
		int(r.position.x) - MARGIN, int(r.position.y) - MARGIN,
		int(r.size.x) + MARGIN * 2, int(r.size.y) + MARGIN * 2)
	var path := OUT_DIR + ("strip_v%03d.png" % int(v * 100.0))
	img.get_region(crop).save_png(path)
	print("CAPTURED %s -> %s" % [path, ProjectSettings.globalize_path(path)])
