extends SceneTree
## ============================================================================
## LAG PROBE (dev tool — never runs in the shipped game).
##
## Measures per-frame CPU cost (headless, so rendering is excluded) with the
## creature teleport-held at a chosen spot. Built for R24: the "whole game lags
## near the hallway wall" hunt that turned out to be PropBarrel2's runtime
## trimesh collider vs the creature's 9-shape hull (8.1 ms/frame -> 0.6 ms after
## the fix).
##
## Run:
##   LAG_MODE=hold_zone godot --headless --path . --fixed-fps 60 \
##       --quit-after 1200 -s res://tests/lag_probe.gd
##
## LAG_MODE: hold_zone (-0.3,0,-2.2 the old stall spot) | hold_far (0,0,10) |
##           hold_onmesh_near (0,0,-4) | hold_onmesh_far (0,0,-10)
## LAG_VARIANT (applied at frame 30): none | freezecre | dormant | noplayer |
##           nobbarrel | nomodel | nonavnode | noaware | nodoors
## Prints: AB MODE=... frames=240 avg=Xms worst=Yms over frames 60-300.
## Interpretation: avg ~= 0.5-0.8 ms is the clean floor on this box; anything
## above ~2 ms means something at that spot is eating the simulation.
## ============================================================================
## A/B frame-cost probe. Modes:
##   hold_zone  : creature teleport-held at the stall spot (-0.3,0,-2.2), awake+running anim
##   hold_far   : same but held at (0,0,10) (corridor, away from stall zone)
##   hold_zone_noshadow : hold_zone + creature mesh cast_shadow OFF
##   hold_zone_lightoff : hold_zone + LightCorr1/2 shadow_enabled=false
## Env LAG_MODE picks one. Prints avg/worst frame ms over the measure window.
var _mode: String = OS.get_environment("LAG_MODE")


func _init() -> void:
	if _mode == "":
		_mode = "hold_zone"
var _started := false
var _cre: Node3D = null
var _player: Node3D = null
var _n := 0
var _prev := 0
var _sum := 0.0
var _worst := 0.0
var _cnt := 0
var _measure := false
func _process(_d: float) -> bool:
	var us: int = Time.get_ticks_usec()
	if _prev > 0:
		var ms: float = (us - _prev) / 1000.0
		if _measure:
			_sum += ms
			_worst = maxf(_worst, ms)
			_cnt += 1
	_prev = us
	if not _started:
		_started = true
		var lv: PackedScene = load("res://scenes/levels/corridor_level.tscn")
		root.add_child(lv.instantiate())
		return false
	if _cre == null:
		var cs: Array[Node] = get_nodes_in_group("creature")
		var ps: Array[Node] = get_nodes_in_group("player")
		if cs.size() > 0 and ps.size() > 0:
			_cre = cs[0]; _player = ps[0] as Node3D
		return false
	_n += 1
	# wake the creature so it plays run/idle anims like in-game
	if not is_instance_valid(_cre):
		if _n == 60: _measure = true
		if _n == 300:
			_measure = false
			print("AB MODE=%s frames=%d avg=%.1fms worst=%.1fms" % [_mode, _cnt, _sum / float(_cnt), _worst])
			quit()
		return false
	if OS.get_environment("LAG_VARIANT") != "dormant":
		_cre.set("_awake", true)
	match _mode:
		"hold_zone", "hold_zone_noshadow", "hold_zone_lightoff":
			_cre.global_position = Vector3(-0.3, 0.0, -2.2)
		"hold_far":
			_cre.global_position = Vector3(0.0, 0.0, 10.0)
		"hold_onmesh_far":
			_cre.global_position = Vector3(0.0, 0.0, -10.0)
		"hold_onmesh_near":
			_cre.global_position = Vector3(0.0, 0.0, -4.0)
	_cre.velocity = Vector3.ZERO
	var variant: String = OS.get_environment("LAG_VARIANT")
	if _n == 30:
		match variant:
			"nohull":
				_cre.set("hull_enabled", false)
				print("AB variant nohull")
			"nonav":
				var navn: Node = _cre.get("nav")
				if navn != null: navn.set_process(false)
				print("AB variant nonav")
			"noaware":
				var aw: Node = _cre.get("awareness")
				if aw != null: aw.free()
				_cre.set("awareness", null)
				print("AB variant noaware")
			"nodoors":
				for d in get_nodes_in_group("heavy_door"):
					d.queue_free()
				print("AB variant nodoors")
			"nob barrel":
				pass
			"nobbarrel":
				for pn in ["PropBarrel2", "PropBarrel", "PropBarrel1"]:
					var nd: Node = root.find_child(pn, true, false)
					if nd != null:
						nd.queue_free()
						print("AB variant nobbarrel freed ", pn)
			"probe_overlap":
				pass
			"freezecre":
				_cre.set_physics_process(false)
				print("AB variant freezecre")
			"dormant":
				_cre.set("_awake", false)
				print("AB variant dormant")
			"noplayer":
				var ps2: Array[Node] = get_nodes_in_group("player")
				for pl in ps2: pl.queue_free()
				print("AB variant noplayer")
			"nocreature":
				_cre.queue_free()
				print("AB variant nocreature")
			"nomodel":
				var mr: Node = _cre.get_node_or_null("ModelRoot")
				if mr != null: mr.queue_free()
				print("AB variant nomodel")
			"nohullshapes":
				var killed := 0
				for cs2 in _cre.find_children("*", "CollisionShape3D", true, true):
					if String(cs2.name).to_lower().begins_with("hull"):
						(cs2 as CollisionShape3D).disabled = true
						killed += 1
				print("AB variant nohullshapes killed=", killed)
			"nonavnode":
				var navn2: Node = _cre.get("nav")
				if navn2 != null:
					_cre.set("nav", null)
					navn2.queue_free()
				print("AB variant nonavnode")
			"nosteer":
				_cre.set("_bt_player_active_override", true)
				var btp: Node = _cre.get("_bt_player")
				if btp != null: btp.active = false
				print("AB variant nosteer (BT off, creature just held)")
		if _mode == "hold_zone_noshadow":
			var mr: Node = _cre.get_node_or_null("ModelRoot")
			if mr == null: mr = _cre
			for mi in mr.find_children("*", "MeshInstance3D", true, true):
				(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			print("AB noshadow applied to model meshes")
		if _mode == "hold_zone_lightoff":
			for ln in ["LightCorr1", "LightCorr2"]:
				var li: Node = root.find_child(ln, true, false)
				if li != null:
					(li as OmniLight3D).shadow_enabled = false
					print("AB lightoff applied to ", ln)
	if _n == 60:
		_measure = true
	if _n == 60 + 240:
		_measure = false
		print("AB MODE=%s frames=%d avg=%.1fms worst=%.1fms" % [_mode, _cnt, _sum / float(_cnt), _worst])
		quit()
	return false
