extends SceneTree
var hits: Array[String] = []
var _f := 0
func _process(_d: float) -> bool:
	_f += 1
	if _f < 2:
		return false
	var host := Node.new()
	root.add_child(host)
	var ap := AnimationPlayer.new()
	host.add_child(ap)
	var a := Animation.new()
	a.length = 2.0
	var tm := a.add_track(Animation.TYPE_METHOD)
	a.track_set_path(tm, NodePath("."))
	a.track_insert_key(tm, 0.3, {"method": "m_a", "args": []})
	a.track_insert_key(tm, 0.9, {"method": "m_b", "args": [7]})
	var lib := AnimationLibrary.new()
	lib.add_animation("t", a)
	ap.add_animation_library("", lib)
	# not playing: seek across keys
	ap.seek(0.5, true)
	print("after seek 0.5: ", hits)
	ap.seek(1.2, true)
	print("after seek 1.2: ", hits)
	# backwards seek should not fire
	ap.seek(0.4, true)
	print("after back-seek 0.4: ", hits)
	quit(0)
	return true
func m_a() -> void:
	hits.append("m_a")
func m_b(v: int) -> void:
	hits.append("m_b%d" % v)
