extends SceneTree
## ============================================================================
## PROXIMITY MONITOR SELF-TEST (dev tool — never runs in the shipped game).
##
## Run headless:
##   godot --headless --path . --fixed-fps 60 --quit-after 4000 \
##         -s res://tests/proximity_selftest.gd
##
## Part A — preview mode (no level): bands, colours, amplitudes, alphas.
## Part B — live level: asleep = hidden, awake = shown, menu hides, heartbeat
##          one-shots fire only when awake+close+visible, shader influence
##          follows the fade (no ghosting).
## ============================================================================

const SCENE_PATH := "res://scenes/ui/proximity_monitor.tscn"

var _results: Array[String] = []
var _fails: int = 0
var _phase := 0
var _frames := 0
var _mon: Control = null
var _level: Node = null
var _cre: Node3D = null
var _player: Node3D = null
var _beats_mark := 0
var _events: Node = null


func _process(_d: float) -> bool:
	_frames += 1
	match _phase:
		0:
			_boot_preview()
		1:  # part A checks run immediately, then move on
			_part_a()
			_phase = 2
			_frames = 0
		2:
			if _frames == 1:
				_boot_level()
			if _boot_level_done():
				_phase = 3
				_frames = 0
		3:  # asleep -> hidden
			if _frames == 1:
				_cre.set("_awake", false)
				_mon.preview_mode = false
			if _frames > 90:
				_check("B1 asleep -> faded out", _mon._fade < 0.02, "fade=%.3f" % _mon._fade)
				_check("B1b trace hidden while asleep", not _mon.get_node("Trace").visible)
				_phase = 4
				_frames = 0
		4:  # awake + close -> shown + beats
			if _frames == 1:
				_cre.set("_awake", true)
			_place_cre(3.0)   # every frame: the BT would otherwise close/open
			if _frames > 90:
				_check("B2 awake+close -> faded in", _mon._fade > 0.98, "fade=%.3f" % _mon._fade)
				_check("B2b high prox at 3 m", _mon.current_prox() > 0.7,
					"prox=%.2f" % _mon.current_prox())
				_beats_mark = _mon.beats_played
				_phase = 5
				_frames = 0
		5:  # beats accumulate while close
			if _frames > 150:
				var gained: int = _mon.beats_played - _beats_mark
				_check("B3 heartbeat one-shots fire when close", gained >= 2,
					"beats+=%d in 150 frames" % gained)
				_beats_mark = _mon.beats_played
				_phase = 6
				_frames = 0
		6:  # far -> flatline, no beats
			_place_cre(30.0)   # pinned: an unpinned chase closes 30 m in ~6 s
			# One trailing beat during the ~0.25 s smoothing tail is correct
			# behaviour; start counting only once the swell has settled.
			if _frames == 45:
				_beats_mark = _mon.beats_played
			if _frames > 150:
				var gained: int = _mon.beats_played - _beats_mark
				_check("B4 far -> no heartbeat audio", gained == 0, "beats+=%d" % gained)
				_check("B4b far reads as band 0", _mon.band_index() == 0,
					"band=%d" % _mon.band_index())
				_check("B4c still visible while awake+far", _mon._fade > 0.98,
					"fade=%.3f" % _mon._fade)
				_phase = 7
				_frames = 0
		7:  # menu hides even while awake+close
			_place_cre(3.0)
			if _frames == 1:
				_events.call_deferred("emit_signal", "inventory_toggled", true)
			if _frames > 90:
				_check("B5 menu open -> hidden", _mon._fade < 0.02, "fade=%.3f" % _mon._fade)
				var ov: ColorRect = _mon.get_node("Trace/BleedOverlay")
				var mat: ShaderMaterial = ov.material
				_check("B5b shader influence faded (no ghosting)",
					float(mat.get_shader_parameter("influence")) < 0.01,
					"inf=%.3f" % float(mat.get_shader_parameter("influence")))
				_beats_mark = _mon.beats_played
				_phase = 8
				_frames = 0
		8:  # no beats while hidden; closing restores
			if _frames > 120:
				var gained: int = _mon.beats_played - _beats_mark
				_check("B6 no beats while hidden", gained == 0, "beats+=%d" % gained)
				_phase = 9
				_frames = 0
		9:
			if _frames == 1:
				_events.call_deferred("emit_signal", "inventory_toggled", false)
			if _frames > 90:
				_check("B7 menu closed -> shown again", _mon._fade > 0.98,
					"fade=%.3f" % _mon._fade)
				_phase = 10
				_report()
				quit()
	return false


# ── boot helpers ─────────────────────────────────────────────────────────────

func _boot_preview() -> void:
	var sc: PackedScene = load(SCENE_PATH)
	var l := CanvasLayer.new()
	l.layer = 10
	root.add_child(l)
	_mon = sc.instantiate()
	l.add_child(_mon)
	_mon.set_deferred("size", Vector2(1280, 720))
	_mon.preview_mode = true
	_phase = 1


func _part_a() -> void:
	var bands := [0.05, 0.3, 0.65, 0.95]
	var want_band := [0, 1, 2, 3]
	var amps: Array[float] = []
	var alphas: Array[float] = []
	var doms: Array[float] = []
	for i in range(4):
		_mon.preview_prox = bands[i]
		# _prox is smoothed (8/s exp lerp): pump ~1.5 s of updates so the
		# accessors reflect the target, exactly like gameplay would settle.
		for k in range(90):
			_mon.call("_update_source", 1.0 / 60.0)
		_check("A1 band[%d] at prox %.2f" % [want_band[i], bands[i]],
			_mon.band_index() == want_band[i], "got %d" % _mon.band_index())
		amps.append(_mon.trace_amp())
		alphas.append(_mon.trace_alpha())
		var c: Color = _mon.trace_color()
		doms.append(c.r - maxf(c.g, c.b))
	_check("A2 amplitude rises with proximity",
		amps[0] < amps[1] and amps[1] < amps[2] and amps[2] < amps[3],
		"amps=%.3f,%.3f,%.3f,%.3f" % [amps[0], amps[1], amps[2], amps[3]])
	_check("A3 alpha rises per band",
		alphas[0] <= alphas[1] and alphas[1] <= alphas[2] and alphas[2] <= alphas[3],
		"alphas=%.2f,%.2f,%.2f,%.2f" % [alphas[0], alphas[1], alphas[2], alphas[3]])
	_check("A4 colour trends toward red",
		doms[3] > doms[2] and doms[2] > doms[1],
		"red-dominance=%.2f,%.2f,%.2f,%.2f" % [doms[0], doms[1], doms[2], doms[3]])
	_check("A5 label off by default (art direction)", _mon.show_label == false)
	_check("A6 awake-gate on by default", _mon.require_awake == true)
	var hp: AudioStreamPlayer = _mon.get_node_or_null("Heartbeat")
	_check("A7 heartbeat player exists with stream",
		hp != null and hp.stream != null)
	if hp != null and hp.stream != null:
		var dur: float = hp.stream.get_length()
		_check("A8 heartbeat stream ~0.75 s lub-dub", dur > 0.5 and dur < 1.2,
			"dur=%.2f" % dur)


func _boot_level() -> void:
	if _level == null:
		_level = (load("res://scenes/levels/corridor_level.tscn") as PackedScene).instantiate()
		root.add_child(_level)


func _boot_level_done() -> bool:
	if _events == null:
		_events = root.get_node_or_null("/root/Events")
	if _cre == null:
		var cs: Array[Node] = get_nodes_in_group("creature")
		if cs.size() > 0:
			_cre = cs[0] as Node3D
	if _player == null:
		var ps: Array[Node] = get_nodes_in_group("player")
		if ps.size() > 0:
			_player = ps[0] as Node3D
	return _cre != null and _player != null and _events != null and _frames > 40


func _place_cre(dist: float) -> void:
	# Put the creature `dist` metres +X of the player, flat on the floor.
	var p: Vector3 = _player.global_position
	_cre.global_position = Vector3(p.x + dist, 0.0, p.z)
	_cre.velocity = Vector3.ZERO


# ── reporting ────────────────────────────────────────────────────────────────

func _check(name: String, ok: bool, detail: String = "") -> void:
	_results.append("%s %s%s" % ["PASS" if ok else "FAIL", name,
		("" if detail == "" else " — " + detail)])
	if not ok:
		_fails += 1


func _report() -> void:
	print("")
	for line in _results:
		print("  " + line)
	print("")
	print("════ %d checks, %d failed ════" % [_results.size(), _fails])
	print("PROXIMITY SELF-TEST: %s" % ["PASS" if _fails == 0 else "FAIL"])
