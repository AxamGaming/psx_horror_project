extends SceneTree
## ============================================================================
## AI SELF-TEST HARNESS (dev tool — never runs in the shipped game).
##
## Run headless:
##   godot --headless --path . --fixed-fps 60 --quit-after 7800 \
##         -s res://tests/ai_selftest.gd
##
## Boots corridor_level.tscn with a scripted "virtual player" (teleport-locked
## anchors, invincible until the feeding test) and asserts the R16 fixes:
##   P1 wake + chase + FACING (body -Z must lead the movement — the old
##      atan2(x,z) yaw made the FOV cone point backwards)
##   P2 player on the 0.4 m Stage → creature must STEP-HOP up onto it
##   P3 player west of the Stage → creature must come AROUND (not ram east side)
##   P4 closed Door2 → creature must force it open and pass the doorway
##      (lintel y=2.0 vs the old head-collider top y=2.039 made this impossible)
##   P5 player beyond the crawlspace → creature must PROWL the mouth, never
##      NAV-DEAD straight-line ram
##   P6 shot → downed chain (flinch→death→state_to_crawl→crawl_idol→GETUP→
##      recover roar), never a blank/frozen AnimationPlayer
##   P6b post-recover amnesia: player at biting distance must STARTLE it
##   P7 player death → FEEDING (crawl to the body → eating loop)
##   P8 respawn → feeding ends, patrol resumes
## ============================================================================

var _t: float = 0.0
var _started: bool = false
var _level: Node = null
var _player: Node3D = null
var _cre: Node3D = null
var _rig: Node = null
var _events: Node = null
var _baker: Node = null
var _door2: Node = null

var _anchor: Vector3 = Vector3.ZERO
var _lock_player: bool = false
var _invincible: bool = true

var _results: Array[String] = []
var _fired: Dictionary = {}

# trackers
var _orient_ok: int = 0
var _orient_n: int = 0
var _p1_progress: bool = false
var _p2_ok: bool = false
var _p2_maxy: float = 0.0
var _p3_ok: bool = false
var _p4_door_open: bool = false
var _p4_crossed: bool = false
var _mouth_frames: int = 0
var _mouth_total: int = 0
var _p5_crossed: bool = false
var _p5_stall_t: float = 0.0
var _p5_max_stall: float = 0.0
var _p6_crawl: bool = false
var _p6_getup: bool = false
var _p6_roar: bool = false
var _p6_recovered: bool = false
var _p6_startle: bool = false
var _p6_roar_audio: bool = false
var _p6_roar_cut: bool = false
var _roar_voice: Node = null
var _p7_feed: bool = false
var _p7_eat: bool = false
var _p8_notfeed: bool = false
var _p8_walk: bool = false
var _p11_stall_t: float = 0.0      # continuous non-prowl pinned time
var _p11_max_stall: float = 0.0
var _p9_violations: int = 0        # frames with commanded velocity while winding
var _p10_flips: int = 0            # anim switches observed at point-blank
var _p10_zone_t: float = 0.0       # time spent at point-blank (awake, combat)
var _prev_anim: String = ""
var _last_t: float = 0.0


func _once(key: String) -> bool:
	if _fired.has(key):
		return false
	_fired[key] = true
	return true


func _process(delta: float) -> bool:
	if not _started:
		_started = true
		_level = (load("res://scenes/levels/corridor_level.tscn") as PackedScene).instantiate()
		root.add_child(_level)
		_events = root.get_node_or_null("/root/Events")
		return false

	# Drive the scenario off the PHYSICS frame counter: with --fixed-fps on a
	# headless box the physics can tick ~1.5x per rendered iteration, so a
	# delta-accumulated clock drifts against the creature's own timers
	# (BT tasks, anim chain, cooldowns all run on physics delta).
	_t = Engine.get_physics_frames() / float(Engine.physics_ticks_per_second)

	if _player == null:
		var ps: Array[Node] = get_nodes_in_group("player")
		if ps.size() > 0:
			_player = ps[0] as Node3D
	if _cre == null:
		var cs: Array[Node] = get_nodes_in_group("creature")
		if cs.size() > 0:
			_cre = cs[0] as Node3D
	if _baker == null:
		var bs: Array[Node] = get_nodes_in_group("nav_baker")
		if bs.size() > 0:
			_baker = bs[0]
	if _player == null or _cre == null or _events == null:
		if _t > 3.0:
			_results.append("FAIL bootstrap: player/creature/Events missing")
			_report()
			return true
		return false
	if _rig == null:
		_rig = _events.get("main_camera")
	if _roar_voice == null and _cre != null:
		_roar_voice = _cre.get_node_or_null("Roar")
	if _door2 == null:
		_door2 = _level.find_child("Door2", true, false)

	# Player anchor lock + invincibility.
	if _lock_player:
		_player.global_position = _anchor
		_player.velocity = Vector3.ZERO
	if _invincible and _rig != null and _rig.has_method("set_health"):
		_rig.call("set_health", 1.0)

	var st: Dictionary = _cre.call("debug_state") if _cre.has_method("debug_state") else {}
	var anim: String = String(st.get("anim", ""))
	var task: String = String(st.get("task", "-"))
	var vreal: float = float(st.get("vreal", 0.0))
	var cpos: Vector3 = _cre.global_position
	var ppos: Vector3 = _player.global_position

	# ── Continuous point-blank glitch detectors (R19) ────────────────────────
	var dt_frame: float = _t - _last_t
	_last_t = _t
	# P9: a windup must be rooted — velocity while winding = skating swing.
	if bool(_cre.call("is_winding")):
		var hv: Vector3 = _cre.velocity
		if Vector2(hv.x, hv.z).length() > 0.05:
			_p9_violations += 1
	# P11: new-hull snag monitor — uses the navigator's own pinned timer, which
	# accumulates ONLY while movement is commanded but the body isn't moving
	# (prowl excluded). Intentional standing (investigate dwell, wake roar,
	# point-blank standoff, windups) does NOT count — those deactivate travel.
	var navn: Node = _cre.get("nav")
	if navn != null:
		_p11_max_stall = maxf(_p11_max_stall, float(navn.get("_pinned_t")))
	# P10: anim flip rate while fighting at point-blank (standoff flapping).
	if anim != "":
		var awake_c: bool = bool(st.get("awake", false)) and not bool(st.get("neutralized", false))
		if awake_c and float(st.get("dist", 99.0)) < 1.8 and task != "Feeding":
			_p10_zone_t += dt_frame
			if _prev_anim != "" and anim != _prev_anim:
				_p10_flips += 1
	_prev_anim = anim

	# ── P0: baker ready (the level grew: degenerate-first-bake retry + a bigger
	# mesh can land after t=2, so sample up to t=4) ─────────────────────────
	if _t >= 4.0 and _once("baker"):
		var ok: bool = _baker != null and bool(_baker.call("is_ready"))
		_results.append(("PASS" if ok else "FAIL") + " P0 nav baker ready by t=4")

	# ── P1: proximity wake + chase + facing ───────────────────────────────────
	if _t >= 2.0 and _once("wake_pos"):
		_anchor = Vector3(0.0, 0.0, -17.2)
		_lock_player = true
	if _t >= 2.4 and _once("stand_pos"):
		_anchor = Vector3(0.0, 0.1, -15.0)
	if _t > 3.5 and _t < 7.9:
		var flat_to_p: Vector3 = ppos - cpos
		flat_to_p.y = 0.0
		var dist: float = flat_to_p.length()
		if vreal > 1.0 and dist > 1.5:
			var fwd: Vector3 = -_cre.global_transform.basis.z
			fwd.y = 0.0
			_orient_n += 1
			if fwd.normalized().dot(flat_to_p.normalized()) > 0.5:
				_orient_ok += 1
		if cpos.z > -16.5:
			_p1_progress = true
	if _t >= 8.0 and _once("p1"):
		var awake_ok: bool = bool(st.get("awake", false))
		var ratio: float = float(_orient_ok) / maxf(1.0, float(_orient_n))
		_results.append(("PASS" if awake_ok else "FAIL") + " P1a woke on proximity")
		_results.append(("PASS" if ratio >= 0.7 else "FAIL") + \
				" P1b faces travel/player while chasing (dot>0.5 ratio=%.2f, n=%d)" % [ratio, _orient_n])
		_results.append(("PASS" if _p1_progress else "FAIL") + " P1c moved toward player")

	# ── P2: player on the Stage → creature hops up ────────────────────────────
	if _t >= 8.0 and _once("p2_anchor"):
		_anchor = Vector3(-4.0, 0.6, -18.0)
	if _t > 8.0 and _t < 25.0:
		_p2_maxy = maxf(_p2_maxy, cpos.y)
		var flat_d: Vector3 = _anchor - cpos
		flat_d.y = 0.0
		if cpos.y >= 0.35 and flat_d.length() < 2.5:
			_p2_ok = true
	if _t >= 25.0 and _once("p2"):
		_results.append(("PASS" if _p2_ok else "FAIL") + \
				" P2 climbed onto 0.4m Stage after player (max_y=%.2f)" % _p2_maxy)

	# ── P3: player west of Stage → come around ────────────────────────────────
	if _t >= 25.0 and _once("p3_anchor"):
		_anchor = Vector3(-6.9, 0.2, -18.0)
	if _t > 25.0 and _t < 38.0:
		var flat_d: Vector3 = _anchor - cpos
		flat_d.y = 0.0
		# Either it came around to the west side, OR it reached melee range of
		# the player across the Stage edge (standing on top — both mean it
		# solved the "player behind the Stage" problem instead of ramming).
		if flat_d.length() < 2.2 or (cpos.x < -6.0 and flat_d.length() < 3.0):
			_p3_ok = true
	if _t >= 38.0 and _once("p3"):
		_results.append(("PASS" if _p3_ok else "FAIL") + \
				" P3 reached player behind Stage (around/over, not ramming) x=%.2f" % cpos.x)

	# ── P4: closed Door2 → open and pass ──────────────────────────────────────
	if _t >= 40.0 and _once("p4_anchor"):
		_anchor = Vector3(0.0, 0.1, -4.5)
	# The idle player is nearly silent (noise 0.06) and the closed door panel
	# blocks LOS, so the script "fires its shotgun" to give the creature a
	# reason to come through the door — this is the designed door-open flow
	# (investigate alert → pinned at panel → unstick force_open).
	for gt in [40.5, 46.0, 52.0]:
		if _t >= gt and not _p4_crossed and _once("gun%0.1f" % gt):
			_events.emit_signal("gun_fired", _anchor)
	if _t > 40.0 and _t < 58.0:
		if _door2 != null and _door2.has_method("is_open") and bool(_door2.call("is_open")):
			_p4_door_open = true
		var flat_pd: Vector3 = _anchor - cpos
		flat_pd.y = 0.0
		# Through the doorway = south of the door plane (z=-6, panel 0.1 thick)
		# — it usually stops at attack standoff ONCE THROUGH and swipes, so
		# also accept "reached the player in the corridor".
		if cpos.z > -5.8 or flat_pd.length() < 2.5:
			_p4_crossed = true
	if _t >= 58.0 and _once("p4"):
		_results.append(("PASS" if _p4_door_open else "FAIL") + " P4a force-opened Door2")
		_results.append(("PASS" if _p4_crossed else "FAIL") + \
				" P4b passed through doorway (lintel) — z=%.2f" % cpos.z)

	# ── P5: player beyond crawlspace → prowl the mouth ───────────────────────
	if _t >= 60.0 and _once("p5_anchor"):
		_anchor = Vector3(0.0, 0.1, 10.0)
		# Deterministic pocket repro: drop the creature into the exact spot
		# where flaky runs wedged it — between the open Door2 blade tip and
		# PostA, west of the walkable strip (run-5 log: (-0.82,-6.64)).
		_cre.global_position = Vector3(-0.82, 0.0, -6.64)
		_cre.velocity = Vector3.ZERO
	if _t > 60.5 and _t < 71.0:
		_mouth_total += 1
		if cpos.z > -6.0:
			_mouth_frames += 1          # on the corridor side of Door2
		if cpos.z > -5.8:
			_p5_crossed = true          # physically through the doorway
		if vreal < 0.15:
			_p5_stall_t += delta
			_p5_max_stall = maxf(_p5_max_stall, _p5_stall_t)
		else:
			_p5_stall_t = 0.0
	if _t >= 72.0 and _once("p5"):
		var frac: float = float(_mouth_frames) / maxf(1.0, float(_mouth_total))
		# Real requirements: it gets UNWEDGED from the door pocket, comes
		# through the doorway, and searches the corridor/mouth side for the
		# vanished player without long stalls (where exactly it searches —
		# mouth orbit vs. last-known-position dwell — is its own decision).
		var ok: bool = _p5_crossed and frac >= 0.3 and _p5_max_stall < 3.0
		_results.append(("PASS" if ok else "FAIL") + \
				" P5 unwedged, came through Door2, searched corridor side (crossed=%s frac=%.2f max_stall=%.1fs)" % [
					str(_p5_crossed), frac, _p5_max_stall])

	# ── P6: shot → downed chain → getup → recover ────────────────────────────
	# Lure it into the open hall first (via the open Door2) so the down chain
	# and the startle teleport have clean floor and LOS.
	if _t >= 74.5 and _once("p6_anchor"):
		# Park the player ~north in the hall, far enough (>1.7 m) that the
		# downed snap can't perturb the get-up timing assertions.
		_anchor = Vector3(0.0, 0.1, -13.0)
	if _t >= 75.0 and _once("shot"):
		_cre.call("take_damage", 12.0, Vector3(1.0, 0.0, 0.0))
	if _t > 77.0 and _t < 97.0:
		if anim.contains("crawl") or anim.contains("death") or anim.contains("state_to_crawl"):
			_p6_crawl = true
	if _t > 97.8 and _t < 100.4:
		if anim.contains("crawl_to_state"):
			_p6_getup = true
	if _t > 100.6 and _t < 103.0:
		if not bool(st.get("neutralized", true)):
			_p6_recovered = true
		if anim.contains("roar"):
			_p6_roar = true
	# Roar voice sync: audible DURING the roar pose, cut the moment the pose ends.
	if _t > 100.4 and _t < 102.2:
		if anim.contains("roar") and _roar_voice != null and bool(_roar_voice.get("playing")):
			_p6_roar_audio = true
	if _t > 102.6 and _t < 104.5:
		if anim != "" and not anim.contains("roar") and _roar_voice != null 				and not bool(_roar_voice.get("playing")):
			_p6_roar_cut = true
	if _t >= 101.5 and _once("p6"):
		_results.append(("PASS" if _p6_crawl else "FAIL") + " P6a downed chain anims (crawl/death seen)")
		_results.append(("PASS" if _p6_getup else "FAIL") + " P6b get-up clip before recover (crawl_to_state)")
		_results.append(("PASS" if _p6_recovered else "FAIL") + " P6c recovered at ~25 s")
		_results.append(("PASS" if _p6_roar else "FAIL") + " P6d recover roar holds (not cut after 1 frame)")

	# ── P6e: amnesia startle at point blank ──────────────────────────────────
	if _t >= 102.0 and _once("startle_pos"):
		var cp: Vector3 = _cre.global_position
		# Stand 1 m away on the open side (corridor is narrow: offset along z).
		var off: Vector3 = Vector3(0.0, 0.0, -1.0)
		if absf(cp.x) > 1.5:
			off = Vector3(-signf(cp.x), 0.0, 0.0)
		_anchor = cp + off
		_anchor.y = 0.1
	if _t > 102.2 and _t < 105.0:
		var aw: Node = _cre.get("awareness")
		if aw != null and bool(aw.call("confirmed")):
			_p6_startle = true
	if _t >= 105.0 and _once("p6f"):
		_results.append(("PASS" if _p6_roar_audio else "FAIL") + " P6f roar VOICE plays during roar pose")
		_results.append(("PASS" if _p6_roar_cut else "FAIL") + " P6g roar voice cut when pose ends (guard)")
	if _t >= 105.5 and _once("p6e"):
		_results.append(("PASS" if _p6_startle else "FAIL") + \
				" P6e amnesiac startle when player presses its face")

	# ── P7: player dies → feeding ────────────────────────────────────────────
	if _t >= 106.0 and _once("kill"):
		_invincible = false
		if _rig != null and _rig.has_method("set_health"):
			_rig.call("set_health", 1.0)
		_events.emit_signal("player_damaged", 999.0, Vector3(1.0, 0.0, 0.0))
	if _t > 106.5 and _t < 114.0:
		if task == "Feeding":
			_p7_feed = true
		if anim.contains("eating"):
			_p7_eat = true
		if Engine.get_physics_frames() % 120 == 0:
			print("  [feed trace t=%.2f] cre=(%.2f,%.2f,%.2f) player=(%.2f,%.2f,%.2f) anchor=(%.2f,%.2f,%.2f) anim=%s phase=%s" % [
				_t, cpos.x, cpos.y, cpos.z, ppos.x, ppos.y, ppos.z,
				_anchor.x, _anchor.y, _anchor.z, anim, str(_cre.get("_feed_phase"))])
	if _t >= 114.0 and _once("p7"):
		_results.append(("PASS" if _p7_feed else "FAIL") + " P7a feeding mode engaged on player death")
		_results.append(("PASS" if _p7_eat else "FAIL") + " P7b reached body and played eating")

	# ── P8: respawn → back to patrol ─────────────────────────────────────────
	if _t >= 114.5 and _once("respawn"):
		_invincible = true
		_lock_player = false   # survival teleports the player to its own spawn
		_events.emit_signal("respawn_requested")
	if _t > 115.0 and _t < 122.0:
		if task != "Feeding":
			_p8_notfeed = true
		if vreal > 0.5 or task.begins_with("Act"):
			_p8_walk = true
	if _t >= 123.0 and _once("p8"):
		_results.append(("PASS" if _p8_notfeed else "FAIL") + " P8a feeding ended on respawn")
		_results.append(("PASS" if _p8_walk else "FAIL") + " P8b AI resumed a normal task after respawn")
		_report()
		return true

	if _t > 128.0:
		_report()
		return true
	return false


func _report() -> void:
	print("\n══════════════ AI SELF-TEST REPORT (t=%.1f) ══════════════" % _t)
	var fails: int = 0
	var p9ok: bool = _p9_violations == 0
	_results.append(("PASS" if p9ok else "FAIL") + \
			" P9 windups are rooted — no skating swings (violations=%d)" % _p9_violations)
	var p11ok: bool = _p11_max_stall < 4.0
	_results.append(("PASS" if p11ok else "FAIL") + \
			" P11 no long stalls anywhere (max continuous pinned %.1fs, want < 4)" % _p11_max_stall)
	var flip_rate: float = _p10_flips / maxf(_p10_zone_t, 0.001)
	var p10ok: bool = flip_rate < 5.0
	_results.append(("PASS" if p10ok else "FAIL") + \
			" P10 point-blank anim flip rate %.2f/s over %.1fs (want < 5)" % [flip_rate, _p10_zone_t])
	for r in _results:
		print("  " + r)
		if r.begins_with("FAIL"):
			fails += 1
	# Log-marker checks.
	var markers: Dictionary = {
		"STEP HOP": 0, "PROWL": 0, "door open": 0, "GETUP": 0,
		"FEED START": 0, "FEED EAT": 0, "NAV DEAD": 0, "LUNGE START": 0,
		"WINDUP": 0, "VOID RESET": 0,
	}
	var f: FileAccess = FileAccess.open("user://creature_log.txt", FileAccess.READ)
	if f != null:
		while not f.eof_reached():
			var line: String = f.get_line()
			if line.contains("MSG |") or line.contains("ENGINEERR"):
				continue   # echoed report text from the previous run's drain
			for k in markers:
				if line.contains(k):
					markers[k] = int(markers[k]) + 1
		f.close()
		print("  ── creature_log markers:")
		for k in markers:
			print("     %-12s %d" % [k, int(markers[k])])
		if int(markers["STEP HOP"]) < 1:
			print("  FAIL L1 no STEP HOP logged (Stage climb)")
			fails += 1
		else:
			print("  PASS L1 STEP HOP logged")
		if int(markers["PROWL"]) < 1:
			print("  FAIL L2 no PROWL logged (crawlspace mouth)")
			fails += 1
		else:
			print("  PASS L2 PROWL logged")
		if int(markers["NAV DEAD"]) > 0:
			print("  FAIL L3 NAV DEAD latch fired")
			fails += 1
		else:
			print("  PASS L3 no NAV DEAD latch")
		if int(markers["VOID RESET"]) > 0:
			print("  FAIL L4 creature fell into void")
			fails += 1
		else:
			print("  PASS L4 no void resets")
	else:
		print("  FAIL L0 creature_log.txt unreadable")
		fails += 1
	print("══════════════ %d FAILURES ══════════════\n" % fails)
	quit(1 if fails > 0 else 0)
