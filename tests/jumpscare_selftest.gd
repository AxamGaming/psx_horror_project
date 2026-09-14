extends SceneTree
## ============================================================================
## KILL SEQUENCE SELF-TEST (R30, dev tool — never runs in the shipped game).
##
## Run headless:
##   godot --headless --path . --fixed-fps 60 --quit-after 1600 \
##         -s res://tests/jumpscare_selftest.gd
##
## Covers the R30 kill director (scenes/enemies/kill_director.gd):
##   K1  environmental death  -> classic overlay, director idle
##   K2  creature kill        -> overlay suppressed, cam authority, input lock,
##                               creature hold + its gait mixer disabled
##   K3  impact beat          -> whip spring kicked, audio layers live,
##                               kill FX flash uniform > 0, light curve driven
##   K4  warped clock         -> real time runs ahead of authored time (slow-mo)
##   K5  beats fire           -> beat index walks the staging table exactly
##                               once per beat; states progress
##                               IMPACT->HANG->THRASH->CRASH->SETTLE->FADE->HOLD
##   K6  body performance     -> skeleton pose advances with the warped clock
##   K7  crash                -> camera reaches the floor, blood pool decal on
##   K8  death hand-off       -> overlay presented at the end of the fade
##   K9  respawn              -> full teardown (cam, input, hold, BT, FX reset)
##   K10 settings gating      -> camera_shake 0 kills the whip; kill_fx 0 kills
##                               the flash uniform; pause menu refuses mid-scare
##   K11 variant forcing      -> force_variant selects body + staging clip
##   K12 (R31) footsteps      -> a held-walk death leaves stale input state;
##                               zero heel_strikes may fire after player_died
##   K13 (R31) crash weight   -> floor contact, a real bounce apex after first
##                               impact, SETTLE entered only once landed
##   K2h/i (R31) kill start   -> kill cam begins AT the player's view + FOV
##                               (no scare-cam snap / "rise from the ground")
##
##   R32: the suite resets Settings to authored defaults on frame 1, so a
##   stale user://settings.cfg (camera_shake 0 from an earlier session) can
##   no longer flip K3/K10.
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
var _fx: Node = null
var _menu: Node = null
var _cam_start: Vector3 = Vector3.ZERO
var _pose_a: Transform3D = Transform3D()
var _pose_b: Transform3D = Transform3D()
var _seen_states: Array[int] = []
var _max_beat_idx: int = 0
var _cam_lowest: float = 999.0
# R31 regression state
var _player_view: Transform3D = Transform3D()
var _player_fov: float = 0.0
var _strikes: int = 0
var _stale_injected: bool = false
var _contact_seen: bool = false
var _bounce_apex: float = -1.0
var _settle_checked: bool = false
var _settle_crashed_ok: bool = false


func _on_strike(_strength: float, _foot: int) -> void:
	_strikes += 1


func _process(_d: float) -> bool:
	_frames += 1
	match _phase:
		0:
			if _frames == 1:
				# R32: never let a persisted user://settings.cfg leak into the
				# assertions. K10 drives camera_shake/kill_fx to 0 mid-run and
				# restores them at the END — a cfg left behind by an earlier
				# session (or a run killed inside K10) zeroes the whip and the
				# flash before K3 ever runs. Resetting (and saving) here makes
				# the suite self-healing instead of flaky.
				var set0: Node = root.get_node("/root/Settings")
				set0.set_camera_shake(1.0)
				set0.set_kill_fx(1.0)
				set0.set_gore(1.0)
				set0.set_reduce_flashes(false)
				_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
				root.add_child(_main)
			if _frames > 30 and _boot_done():
				_phase = 1
				_frames = 0
		1:  # K1 environmental death
			if _frames == 1:
				_rig.call("set_health", 1.0)
				_events.call("emit_signal", "player_damaged", 999.0, Vector3(1.0, 0.0, 0.0))
			if _frames > 20:
				_check("K1 environmental death shows overlay", bool(_overlay.visible))
				_check("K1b director idle on environmental death", bool(_dir._active) == false)
				_events.call("emit_signal", "respawn_requested")
				_phase = 2
				_frames = 0
		2:  # K2/K3 creature kill, deterministic variant
			if _frames == 1:
				_dir.force_variant = "kill_grab"
				_rig.call("set_health", 1.0)
				_cre.call("_wake", _cre.global_position)
				_cre.call("_tag_damage_source")
				_cam_start = _dir.get_node("CreatureKillCamera").global_transform.origin
				# R31: capture the player's own lens BEFORE the kill claims it.
				var mc: Camera3D = _events.main_camera as Camera3D
				_player_view = mc.global_transform
				_player_fov = mc.fov
				if not _rig.heel_strike.is_connected(_on_strike):
					_rig.heel_strike.connect(_on_strike)
				_events.call("emit_signal", "player_damaged", 999.0, Vector3(-0.8, 0.1, 0.6))
			if _frames == 3 and not _stale_injected:
				# R31 K12: simulate "died while holding W". The kill lock froze
				# the body's physics process, so plant the stale living state
				# the freeze could have left behind and count heel strikes all
				# the way to HOLD — after player_died there must be ZERO.
				_stale_injected = true
				_strikes = 0
				_player.set("input_active", true)
				_player.set("planar_speed", 2.2)
			if _frames > 6:
				_check("K2 overlay suppressed on creature kill", bool(_overlay.visible) == false)
				_check("K2b director active + in kill_active group",
					bool(_dir._active) and _dir.is_in_group("kill_active"))
				var cam: Camera3D = _dir.get_node("CreatureKillCamera")
				_check("K2c kill cam current", cam.current)
				# R31: frame one of the kill must BE the player's last view —
				# the old scare-cam snap read as "the camera rises from the
				# ground" at every kill start. The 999-damage test blow kicks
				# the rig's damage spring between our pre-damage capture and
				# the kill start, so compare against the director's own
				# capture (_base_xf) and discriminate against the scare pose.
				var bx: Transform3D = _dir._base_xf as Transform3D
				var d0: float = cam.global_transform.origin.distance_to(bx.origin)
				_check("K2h kill cam holds the captured view (no scare-cam snap)",
					d0 < 0.06,
					"d=%.3f cam=%s base=%s" % [d0, str(cam.global_transform.origin), str(bx.origin)])
				var dv: float = bx.origin.distance_to(_player_view.origin)
				_check("K2h2 captured base IS the player view (recoil aside)",
					dv < 0.45 and absf(bx.origin.y - _player_view.origin.y) < 0.3,
					"d=%.3f base=%s view=%s" % [dv, str(bx.origin), str(_player_view.origin)])
				var ds: float = bx.origin.distance_to(_cam_start)
				_check("K2h3 base is NOT the authored scare-cam pose",
					ds > 0.5, "d_to_scare=%.3f" % ds)
				_check("K2i kill cam FOV starts at the captured player FOV",
					absf(cam.fov - float(_dir._base_fov)) < 10.0,
					"fov=%.1f base=%.1f (scare=94.25)" % [cam.fov, float(_dir._base_fov)])
				_check("K2d input locked via ui_wants_mouse", bool(_events.ui_wants_mouse))
				_check("K2e creature held (no feeding)", bool(_cre.get("jumpscare_hold")))
				var cap: AnimationPlayer = _cre.get("_anim") as AnimationPlayer
				_check("K2f creature gait mixer disabled for the duration",
					cap != null and cap.active == false)
				_check("K2g variant forced to kill_grab", String(_dir._variant) == "kill_grab")
				_check("K3 whip spring kicked (yaw velocity != 0)",
					absf(float(_dir._yaw_v)) + absf(float(_dir._roll_v)) > 0.01,
					"yaw_v=%.3f roll_v=%.3f" % [float(_dir._yaw_v), float(_dir._roll_v)])
				_check("K3b an audio layer is playing", _any_layer_playing())
				_check("K3c kill FX flash uniform live", _fx_uniform("flash") > 0.01,
					"flash=%.3f" % _fx_uniform("flash"))
				_check("K3d staging light curve sampled on the warped clock",
					float(_dir.get_node("JumpscareLight").light_energy) > 0.5,
					"energy=%.2f" % float(_dir.get_node("JumpscareLight").light_energy))
				_phase = 3
				_frames = 0
		3:  # K4 warped clock; capture pose A
			if _frames == 1:
				_pose_a = _head_pose()
			var st: int = int(_dir._state)
			if _seen_states.is_empty() or _seen_states[-1] != st:
				_seen_states.append(st)
			if float(_dir._wt) >= 1.7:
				_check("K4 slow-mo: real time ran ahead of authored time",
					float(_dir._real_t) > float(_dir._wt) + 0.4,
					"real=%.2f wt=%.2f" % [float(_dir._real_t), float(_dir._wt)])
				_phase = 4
				_frames = 0
		4:  # K5/K6/K7/K8: run the sequence to HOLD
			var st2: int = int(_dir._state)
			if _seen_states.is_empty() or _seen_states[-1] != st2:
				_seen_states.append(st2)
			_max_beat_idx = maxi(_max_beat_idx, int(_dir._beat_idx))
			if float(_dir._wt) > 2.4 and _pose_b == Transform3D():
				_pose_b = _head_pose()
			var cam2: Camera3D = _dir.get_node("CreatureKillCamera")
			_cam_lowest = minf(_cam_lowest, cam2.global_transform.origin.y)
			# R31 K13: crash physics — floor contact, the bounce apex after
			# first impact, and SETTLE only once the body has actually landed.
			var fy: float = float(_dir._floor_y)
			if st2 == 4:   # State.CRASH
				var y: float = cam2.global_transform.origin.y
				if not _contact_seen and y <= fy + 0.01:
					_contact_seen = true
				elif _contact_seen:
					_bounce_apex = maxf(_bounce_apex, y)
			elif st2 == 5 and not _settle_checked:   # first SETTLE frame
				_settle_checked = true
				_settle_crashed_ok = bool(_dir._crashed)
			if int(_dir._state) == 7 or _frames > 700:   # State.HOLD
				_check("K5 state machine walked the whole sequence",
					_seq_ok(), "seen=%s f=%d wt=%.2f" % [str(_seen_states), _frames, float(_dir._wt)])
				_check("K5b beat table fully consumed",
					_max_beat_idx >= 9, "beats=%d" % _max_beat_idx)
				_check("K6 body pose advanced with the warped clock",
					_pose_b != Transform3D() and _pose_a.origin.distance_to(_pose_b.origin) > 0.01,
					"d=%.4f a=%s b=%s" % [_pose_a.origin.distance_to(_pose_b.origin),
						str(_pose_a.origin), str(_pose_b.origin)])
				_check("K7 camera crashed down to the floor",
					_cam_lowest < _cam_start.y - 0.6,
					"lowest=%.2f start=%.2f" % [_cam_lowest, _cam_start.y])
				var bb: Node = _dir.get_node_or_null("BloodBurst")
				var pool: Node = bb.get_node_or_null("Pool") if bb != null else null
				_check("K7b blood pool decal deployed", pool != null and bool(pool.visible))
				_check("K8 death overlay presented at fade end", bool(_overlay.visible))
				_check("K8b kill FX desaturated into the fade",
					_fx_uniform("desat") > 0.5, "desat=%.2f" % _fx_uniform("desat"))
				# R31 regressions
				_check("K12 zero footstep strikes after death (stale held-walk state)",
					_strikes == 0, "strikes=%d" % _strikes)
				_check("K13 crash made floor contact", _contact_seen)
				var fy2: float = float(_dir._floor_y)
				_check("K13b heavy-object bounce after first impact",
					_bounce_apex > fy2 + 0.05,
					"apex=%.3f floor=%.3f" % [_bounce_apex, fy2])
				_check("K13c SETTLE entered only once the body had landed",
					_settle_checked and _settle_crashed_ok)
				_phase = 5
				_frames = 0
		5:  # K10 pause menu refuses mid-scare, then K9 respawn teardown
			if _frames == 1:
				_menu.call("open_menu")
			if _frames == 4:
				_check("K10 pause menu refuses to open mid-scare",
					bool(_menu.visible) == false and paused == false,
					"visible=%s paused=%s" % [bool(_menu.visible), paused])
				_events.call("emit_signal", "respawn_requested")
			if _frames > 40:
				_check("K9 director torn down after respawn", bool(_dir._active) == false)
				var cam3: Camera3D = _dir.get_node("CreatureKillCamera")
				_check("K9b kill cam released", cam3.current == false)
				_check("K9c main cam restored",
					_events.main_camera != null and bool(_events.main_camera.current))
				_check("K9d ui_wants_mouse restored", bool(_events.ui_wants_mouse) == false)
				_check("K9e creature hold released + BT live",
					bool(_cre.get("jumpscare_hold")) == false
					and bool((_cre.get("_bt_player") as Node).get("active")))
				var cap2: AnimationPlayer = _cre.get("_anim") as AnimationPlayer
				_check("K9f gait mixer re-enabled", cap2 != null and cap2.active == true)
				_check("K9g kill FX reset",
					_fx_uniform("flash") < 0.001 and _fx_uniform("fade") < 0.001)
				_check("K9h not in kill_active group", _dir.is_in_group("kill_active") == false)
				_phase = 6
				_frames = 0
		6:  # K10b/K10c/K10d settings gating on a fresh kill
			if _frames == 1:
				var stg: Node = root.get_node("/root/Settings")
				stg.set_camera_shake(0.0)
				stg.set_kill_fx(0.0)
				_rig.call("set_health", 1.0)
				_cre.call("_tag_damage_source")
				_events.call("emit_signal", "player_damaged", 999.0, Vector3(0.0, 0.0, 1.0))
			if _frames > 8:
				_check("K10b camera_shake 0 -> no whip impulse",
					absf(float(_dir._yaw_v)) + absf(float(_dir._roll_v)) < 0.0001,
					"yaw_v=%.5f" % float(_dir._yaw_v))
				_check("K10c kill_fx 0 -> flash uniform stays 0",
					_fx_uniform("flash") < 0.001, "flash=%.4f" % _fx_uniform("flash"))
				_check("K10d audio still plays with FX off (sound is not an FX)",
					_any_layer_playing(),
					"active=%s state=%d wt=%.2f" % [bool(_dir._active), int(_dir._state), float(_dir._wt)])
				_phase = 7
				_frames = 0
		7:  # K11 variant forcing, then clean up
			if _frames == 1:
				_events.call("emit_signal", "respawn_requested")
			if _frames == 30:
				_dir.force_variant = "kill_slam"
				_rig.call("set_health", 1.0)
				_cre.call("_tag_damage_source")
				_events.call("emit_signal", "player_damaged", 999.0, Vector3(0.0, 0.0, 1.0))
			if _frames > 40:
				_check("K11 force_variant selects the variant",
					String(_dir._variant) == "kill_slam",
					"variant=%s active=%s" % [String(_dir._variant), bool(_dir._active)])
				_check("K11b staging beat table reloaded for the variant",
					int(_dir._beats.size()) > 0)
				var stg2: Node = root.get_node("/root/Settings")
				stg2.set_camera_shake(1.0)
				stg2.set_kill_fx(1.0)
				_events.call("emit_signal", "respawn_requested")
				_phase = 8
				_frames = 0
		8:
			if _frames > 20:
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
		_dir = _cre.get_node_or_null("KillDirector")
	if _overlay == null:
		_overlay = get_first_node_in_group("death_overlay")
	if _fx == null:
		_fx = get_first_node_in_group("kill_fx")
	if _menu == null and _main != null:
		_menu = _main.get_node_or_null("UI/SettingsMenu")
	if _rig == null and _events != null:
		_rig = _events.main_camera
	return _player != null and _cre != null and _surv != null \
		and _dir != null and _overlay != null and _rig != null and _events != null \
		and _fx != null and _menu != null


func _seq_ok() -> bool:
	# IMPACT(1) HANG(2) THRASH(3) CRASH(4) SETTLE(5) FADE(6) HOLD(7)
	for want in [1, 2, 3, 4, 5, 6, 7]:
		if not _seen_states.has(want):
			return false
	return true


func _find_skel(n: Node) -> Skeleton3D:
	for c in n.get_children():
		var sk := c as Skeleton3D
		if sk != null:
			return sk
		var r := _find_skel(c)
		if r != null:
			return r
	return null


func _head_pose() -> Transform3D:
	var skel: Skeleton3D = _find_skel(_cre)
	if skel == null:
		return Transform3D()
	var idx: int = skel.find_bone("Head_015")
	if idx < 0:
		return Transform3D()
	return skel.global_transform * skel.get_bone_global_pose(idx)


func _any_layer_playing() -> bool:
	for c in _dir.get_children():
		var p := c as AudioStreamPlayer
		if p != null and p.name.begins_with("KillLayer") and p.playing:
			return true
	return false


func _fx_uniform(which: String) -> float:
	var rect: ColorRect = _fx.get_node_or_null("Rect")
	if rect == null:
		return -1.0
	var m: ShaderMaterial = rect.material as ShaderMaterial
	if m == null:
		return -1.0
	return float(m.get_shader_parameter(which))


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
	print("KILL SELF-TEST: %s" % ["PASS" if _fails == 0 else "FAIL"])
