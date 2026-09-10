extends SceneTree
## ============================================================================
## DEBUG-FLY SELF-TEST (dev tool — never runs in the shipped game).
##
## Run headless:
##   godot --headless --path . --fixed-fps 60 --quit-after 900 \
##         -s res://tests/fly_selftest.gd
##
## Asserts:
##   A  "debug_fly" action exists and is bound to physical F
##   B  F-event (or direct toggle fallback) turns fly ON: fly_debug + mask==0
##   C  holding jump+forward climbs and covers distance (camera-axis flight)
##   D  TRUE noclip: parked inside the solid Stage, nothing pushes the body
##   E  F again turns fly OFF: mask restored (19), physics re-engages and the
##      body is expelled from the Stage (up or sideways) and never falls out
##      of the world
## ============================================================================

var _t: float = 0.0
var _started: bool = false
var _level: Node = null
var _player: Node3D = null
var _results: Array[String] = []
var _fails: int = 0
var _once_map: Dictionary = {}
var _start_pos: Vector3 = Vector3.ZERO
var _used_fallback: bool = false


func _once(key: String) -> bool:
	if _once_map.has(key):
		return false
	_once_map[key] = true
	return true


func _send_f() -> void:
	# Route a real F key event through the input system (viewport → unhandled).
	var down := InputEventKey.new()
	down.physical_keycode = KEY_F
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.physical_keycode = KEY_F
	up.pressed = false
	Input.parse_input_event(up)


func _process(delta: float) -> bool:
	if not _started:
		_started = true
		_level = (load("res://scenes/levels/corridor_level.tscn") as PackedScene).instantiate()
		root.add_child(_level)
		return false
	_t = Engine.get_physics_frames() / float(Engine.physics_ticks_per_second)

	if _player == null:
		var ps: Array[Node] = get_nodes_in_group("player")
		if ps.size() > 0:
			_player = ps[0] as Node3D
		if _player == null:
			if _t > 3.0:
				_results.append("FAIL bootstrap: no player")
				_report()
				return true
			return false

	var fly: bool = bool(_player.get("fly_debug"))
	var mask: int = int(_player.get("collision_mask"))
	var pos: Vector3 = _player.global_position

	# A: binding
	if _t >= 1.0 and _once("A"):
		var ok: bool = InputMap.has_action("debug_fly")
		var has_f: bool = false
		if ok:
			for ev in InputMap.action_get_events("debug_fly"):
				var k := ev as InputEventKey
				if k != null and k.physical_keycode == KEY_F:
					has_f = true
		# Flashlight must have moved off F (else both fire on one press).
		var flash_off_f: bool = true
		if InputMap.has_action("flashlight"):
			for ev in InputMap.action_get_events("flashlight"):
				var k := ev as InputEventKey
				if k != null and k.physical_keycode == KEY_F:
					flash_off_f = false
		_results.append(("PASS" if (ok and has_f and flash_off_f) else "FAIL") + \
				" A debug_fly bound to F, flashlight moved off F")

	# B: toggle ON at t=2
	if _t >= 2.0 and _once("B"):
		_start_pos = pos
		_send_f()
	if _t >= 2.5 and _once("B2"):
		if not fly:
			# Headless input injection can be unavailable — fall back to the
			# direct call so the flight mechanics themselves still get tested.
			_used_fallback = true
			_player.call("_toggle_fly")
			fly = bool(_player.get("fly_debug"))
			mask = int(_player.get("collision_mask"))
		var ok: bool = fly and mask == 0
		_results.append(("PASS" if ok else "FAIL") + \
				" B fly ON via %s: fly_debug=%s mask=%d (want 0)" % [
					"direct call (input injection unavailable headless)" if _used_fallback else "F key event",
					str(fly), mask])

	# C: climb + move (t 3..5)
	if _t >= 3.0 and _once("C_start"):
		Input.action_press("jump")
		Input.action_press("move_forward")
	if _t >= 5.0 and _once("C"):
		Input.action_release("jump")
		Input.action_release("move_forward")
		var dy: float = pos.y - _start_pos.y
		var moved: float = pos.distance_to(_start_pos)
		var silent: bool = float(_player.get("noise_level")) <= 0.001
		var ok: bool = dy > 2.0 and moved > 3.0 and silent
		_results.append(("PASS" if ok else "FAIL") + \
				" C camera-axis flight: dy=%.2f moved=%.2f silent=%s" % [dy, moved, str(silent)])

	# D: park INSIDE the solid stage — true noclip (t 5.5..7)
	if _t >= 5.5 and _once("D_place"):
		_player.global_position = Vector3(-4.0, 0.15, -18.0)   # inside Stage box
		_player.velocity = Vector3.ZERO
	if _t >= 7.0 and _once("D"):
		var d: float = pos.distance_to(Vector3(-4.0, 0.15, -18.0))
		var ok: bool = d < 0.05 and bool(_player.get("fly_debug"))
		_results.append(("PASS" if ok else "FAIL") + \
				" D true noclip: rested INSIDE solid Stage unmoved (drift=%.3f)" % d)

	# E: toggle OFF inside the stage → collisions restore, body expelled
	if _t >= 7.2 and _once("E_off"):
		if _used_fallback:
			_player.call("_toggle_fly")
		else:
			_send_f()
	if _t >= 9.5 and _once("E"):
		var fly_now: bool = bool(_player.get("fly_debug"))
		var mask_now: int = int(_player.get("collision_mask"))
		var expelled: bool = pos.y >= 0.35 or Vector2(pos.x + 4.0, pos.z + 18.0).length() > 0.25
		var grounded: bool = pos.y > -1.0
		var ok: bool = (not fly_now) and mask_now == 19 and expelled and grounded
		_results.append(("PASS" if ok else "FAIL") + \
				" E fly OFF: fly=%s mask=%d (want 19) expelled=%s pos=(%.2f,%.2f,%.2f)" % [
					str(fly_now), mask_now, str(expelled), pos.x, pos.y, pos.z])
		_report()
		return true

	if _t > 12.0:
		_report()
		return true
	return false


func _report() -> void:
	print("\n══════════ DEBUG-FLY SELF-TEST (t=%.1f) ══════════" % _t)
	for r in _results:
		print("  " + r)
		if r.begins_with("FAIL"):
			_fails += 1
	print("══════════ %d FAILURES ══════════\n" % _fails)
	quit(1 if _fails > 0 else 0)
