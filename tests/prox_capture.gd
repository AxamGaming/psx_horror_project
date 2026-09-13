extends SceneTree
## ============================================================================
## PROXIMITY CAPTURE (dev tool — never runs in the shipped game).
## Renders the monitor strip in preview mode at the four band centres and saves
## cropped strips to user://prox_cap/ for art review.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --fixed-fps 60 \
##       --quit-after 200 -s res://tests/prox_capture.gd
## ============================================================================

const LEVELS := [0.05, 0.3, 0.65, 0.95]
const OUT_DIR := "user://prox_cap/"

var _started := false
var _mon: Control = null
var _idx := 0
var _stage := 0


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		DirAccess.make_dir_recursive_absolute(OUT_DIR)
		var bg := ColorRect.new()
		bg.color = Color(0.10, 0.10, 0.09)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		var bl := CanvasLayer.new()
		bl.layer = 1
		root.add_child(bl)
		bl.add_child(bg)
		var sc: PackedScene = load("res://scenes/ui/proximity_monitor.tscn")
		var l := CanvasLayer.new()
		l.layer = 10
		root.add_child(l)
		_mon = sc.instantiate()
		l.add_child(_mon)
		_mon.set_deferred("size", Vector2(1280, 720))
		_mon.preview_mode = true
		return false
	match _stage:
		0:
			_mon.preview_prox = LEVELS[_idx]
			# _prox is smoothed: settle it fully before grabbing, otherwise the
			# capture shows the previous band's colour/amplitude.
			for k in range(120):
				_mon.call("_update_source", 1.0 / 60.0)
			_stage = 1
		1:
			_stage = 2
		2:
			# let the trace scroll a few frames so the beat shape is mid-strip
			_stage = 3
		3:
			var img := root.get_viewport().get_texture().get_image()
			var tr: Control = _mon.get_node("Trace")
			var r: Rect2 = tr.get_global_rect()
			var m := 10
			img.get_region(Rect2i(int(r.position.x) - m, int(r.position.y) - m,
				int(r.size.x) + m * 2, int(r.size.y) + m * 2)) \
				.save_png(OUT_DIR + ("band%d.png" % _idx))
			print("CAPTURED band%d prox=%.2f" % [_idx, LEVELS[_idx]])
			_idx += 1
			_stage = 0
			if _idx >= LEVELS.size():
				quit()
	return false
