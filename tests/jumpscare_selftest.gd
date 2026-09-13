extends SceneTree
## ============================================================================
## JUMPSCARE SYSTEM SELF-TEST (dev tool — never runs in the shipped game).
##
## Run headless:
##   godot --headless --path . --fixed-fps 60 --quit-after 3000 \
##         -s res://tests/jumpscare_selftest.gd
##
## Covers the design doc §10 checklist:
##   J1 environmental death  -> death overlay shows, director stays idle
##   J2 creature-tagged kill -> overlay suppressed, kill cam current, input
##      locked, creature held (no feeding), stinger present
##   J3 anim finishes (~2 s) -> auto-respawn, cameras/input/hold restored,
##      overlay still hidden
##   J4 missing animation    -> respawn_timeout path, no softlock
##   J5 feeding skipped on creature kill (feed phase stays NONE)
## ============================================================================

var _results: Array[String] = []
var _fails: int = 0
var _phase := 0
var _frames := 0
var _main: Node = null
var _player: Node3D = null
var _cre: Node3D = null
var _rig: Node = null
var _surv: Node = null
var _dir: Node = null
var _overlay: Node = null
var _events: Node = null
var _cam_before: Transform3D = Transform3D()
var _cam_before_weld: Vector3 = Vector3()
var _light_color_before: Color = Color()


func _process(_d: float) -> bool:
	_frames += 1
	match _phase:
		0:
			if _frames == 1:
				_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
				root.add_child(_main)
			if _frames > 30 and _boot_done():
				_phase = 1
				_frames = 0
		1:  # J1: environmental death
			if _frames == 1:
				_rig.call("set_health", 1.0)
				_events.call("emit_signal", "player_damaged", 999.0, Vector3(1.0, 0.0, 0.0))
			if _frames > 20:
				_check("J1 environmental death shows overlay",
					bool(_overlay.visible), "visible=%s" % _overlay.visible)
				_check("J1b director idle on environmental death",
					bool(_dir._active) == false)
				_events.call("emit_signal", "respawn_requested")
				_phase = 2
				_frames = 0
		2:  # settle respawn + snapshot authored cam/light state
			if _frames > 20:
				_cam_before = _dir.get_node("CreatureKillCamera").global_transform
				_light_color_before = _dir.get_node("JumpscareLight").light_color
				_phase = 3
				_frames = 0
		3:  # J2/J5: creature-tagged kill
			if _frames == 1:
				_rig.call("set_health", 1.0)
				# A real killing blow implies an awake creature; wake it so the
				# scenario matches gameplay (dormant creatures legitimately run
				# with an inactive behavior tree).
				_cre.call("_wake", _cre.global_position)
				_cre.call("_tag_damage_source")
				_events.call("emit_signal", "player_damaged", 999.0, Vector3(1.0, 0.0, 0.0))
			if _frames > 20:
				_check("J2 overlay suppressed on creature kill",
					bool(_overlay.visible) == false, "visible=%s" % _overlay.visible)
				_check("J2b director active", bool(_dir._active))
				var cam: Camera3D = _dir.get_node("CreatureKillCamera")
				_check("J2c kill cam current", cam.current)
				_check("J2d input locked via ui_wants_mouse",
					bool(_events.ui_wants_mouse))
				_check("J2e creature held", bool(_cre.get("jumpscare_hold")))
				_check("J5 feeding skipped on creature kill",
					int(_cre.get("_feed_phase")) == 0,
					"feed_phase=%s" % str(_cre.get("_feed_phase")))
				_check("J2f stinger assigned", _dir.get("stinger") != null)
				# R27: at ~0.33 s the lunge beat (attack anim) must be playing.
				var cap: AnimationPlayer = _cre.get("_anim") as AnimationPlayer
				_check("J2g lunge anim playing at cut",
					cap != null and String(cap.current_animation) == String(_cre.get("anim_attack_3")),
					"current=%s" % (String(cap.current_animation) if cap else "null"))
				# R27 head-weld follow: teleport the creature mid-scare; the kill
				# cam must ride with it (the old "fixed position" bug).
				var camn: Camera3D = _dir.get_node("CreatureKillCamera")
				_cam_before_weld = camn.global_transform.origin
				_cre.global_position += Vector3(1.5, 0.0, 0.0)
				# R27: the cam is welded to the creature (head bone), so the
				# meaningful assertion is proximity to the creature, not a
				# static position (the lunge charge moves both by design).
				var cam_now: Transform3D = cam.global_transform
				_check("J7 kill cam rides with the creature",
					cam_now.origin.distance_to(_cre.global_position) < 4.0,
					"dist_to_creature=%.3f" % cam_now.origin.distance_to(_cre.global_position))
				var li: Light3D = _dir.get_node("JumpscareLight")
				_check("J8 light colour is authored (not overridden)",
					li.light_color == _light_color_before)
				_check("J9 no cam_offset export left on director",
					not ("cam_offset" in _dir))
				# R26d: void-out ramp must be pulling the world dark mid-scare.
				var env: Environment = _dir.get("_env") as Environment
				if env != null:
					var base_bg: float = float(_dir.get("_base_bg_energy"))
					_check("J10 void-out darkens world during scare",
						env.background_energy_multiplier < base_bg * 0.6,
						"bg=%.2f base=%.2f" % [env.background_energy_multiplier, base_bg])
				else:
					_check("J10 void-out darkens world during scare", false, "env null")
				_phase = 4
				_frames = 0
		4:  # J3: auto-respawn after the 2 s default anim
			# Mid-sequence (~1 s after the kill): charge spent, weld following.
			if _frames == 60:
				# R29b: the author intentionally removed the request_roar@0.6
				# key from the scene library — the lunge pose holds the slam.
				# request_roar() used to stop the charge too, so guard that the
				# charge still expires on its own (_charge_left runs out ~0.32 s
				# at the default distance/speed) and the creature can't drift.
				_check("J2h lunge charge expired (no runaway drift)",
					bool(_dir.get("_charging")) == false and float(_dir.get("_charge_left")) <= 0.0,
					"charging=%s left=%.3f" % [bool(_dir.get("_charging")), float(_dir.get("_charge_left"))])
				var camn2: Camera3D = _dir.get_node("CreatureKillCamera")
				var dx: float = camn2.global_transform.origin.x - _cam_before_weld.x
				_check("J12 kill cam welded to creature (follows teleport)",
					absf(dx - 1.5) < 0.15, "dx=%.3f" % dx)
			if _frames > 200:
				_check("J3 director inactive after anim", bool(_dir._active) == false)
				var cam2: Camera3D = _dir.get_node("CreatureKillCamera")
				_check("J3b kill cam released", cam2.current == false)
				_check("J3c main cam restored",
					_events.main_camera != null and bool(_events.main_camera.current))
				_check("J3d ui_wants_mouse restored",
					bool(_events.ui_wants_mouse) == false)
				_check("J3e creature hold released",
					bool(_cre.get("jumpscare_hold")) == false)
				_check("J3f overlay still hidden after jumpscare respawn",
					bool(_overlay.visible) == false)
				_check("J3g player respawned (not dead)",
					bool(_surv.get("_dead")) == false)
				# R26b: the behavior tree must be live again after the hold,
				# otherwise the creature stands frozen forever ("got stuck").
				# R26d: after the sequence the world light must be fully restored.
				var env2: Environment = _dir.get("_env") as Environment
				if env2 != null:
					var base2: float = float(_dir.get("_base_bg_energy"))
					_check("J11 world light restored after scare",
						absf(env2.background_energy_multiplier - base2) < 0.02,
						"bg=%.3f base=%.3f" % [env2.background_energy_multiplier, base2])
				var btp: Node = _cre.get("_bt_player") as Node
				_check("J6 behavior tree re-activated after jumpscare",
					btp != null and bool(btp.get("active")),
					"active=%s" % (str(btp.get("active")) if btp else "null"))
				_phase = 5
				_frames = 0
		5:  # J4: missing animation -> timeout path
			if _frames == 1:
				_dir.anim_name = "definitely_not_an_animation"
				_dir.respawn_timeout_sec = 1.0
				_rig.call("set_health", 1.0)
				_cre.call("_tag_damage_source")
				_events.call("emit_signal", "player_damaged", 999.0, Vector3(1.0, 0.0, 0.0))
			if _frames > 120:
				_check("J4 timeout path respawns (no softlock)",
					bool(_dir._active) == false and bool(_surv.get("_dead")) == false,
					"active=%s dead=%s" % [_dir._active, _surv.get("_dead")])
				_phase = 6
				_report()
				quit()
	return false


func _boot_done() -> bool:
	if _events == null:
		_events = root.get_node_or_null("/root/Events")
	if _player == null:
		var ps: Array[Node] = get_nodes_in_group("player")
		if ps.size() > 0:
			_player = ps[0] as Node3D
	if _cre == null:
		var cs: Array[Node] = get_nodes_in_group("creature")
		if cs.size() > 0:
			_cre = cs[0] as Node3D
	if _player != null and _surv == null:
		_surv = _player.find_child("Survival", true, false)
	if _cre != null and _dir == null:
		_dir = _cre.get_node_or_null("JumpscareDirector")
	if _overlay == null:
		_overlay = get_first_node_in_group("death_overlay")
	if _rig == null and _events != null:
		_rig = _events.main_camera
	return _player != null and _cre != null and _surv != null \
		and _dir != null and _overlay != null and _rig != null and _events != null


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
	print("JUMPSCARE SELF-TEST: %s" % ["PASS" if _fails == 0 else "FAIL"])
