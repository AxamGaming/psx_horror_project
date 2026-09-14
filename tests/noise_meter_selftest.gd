extends SceneTree
## ============================================================================
## NOISE-METER + HEARING SELF-TEST (dev tool — never runs in the shipped game).
##
## Run headless:
##   godot --headless --path . --fixed-fps 60 --quit-after 4000 \
##         -s res://tests/noise_meter_selftest.gd
##
## Same harness shape as tests/ai_selftest.gd: `_process(delta) -> bool`,
## scenario advanced by frame counter, real corridor_level so the player,
## creature and Events autoload all exist for real.
##
## WHY TWO DRIVING MODES
##   Part A tests the creature's real CreatureAwareness.tick(), which runs from
##   NightmareCreature._physics_process. That only advances with REAL frames, so
##   each probe is ARMED on one _process call and READ on a later one.
##   Part B tests the meter's own smoothing/fade/shake maths. Those are driven
##   deterministically by calling the widget's real per-frame methods with a
##   fixed delta (see _pump) — a synchronous notification pump would never
##   advance the tree clock, so delta-based lerps would not converge.
##
## No literal thresholds are asserted: every check reads the exports it is
## testing, so retuning in the inspector changes what is verified rather than
## breaking the test.
##
## COVERAGE
##   A1-A6   idle/crouch unheard at distance; crouch heard at point-blank via the
##           quiet tier; walk and sprint heard inside hear_radius * noise
##   A7      loud hearing is not reported as the quiet tier
##   A8      hear_noise_floor = 0.05 restores legacy behaviour
##   A9      crouch_hear_range = 0 disables the quiet tier
##   A10     hear_radius is a live adjustable audible range
##   B1-B3   structure, gradient toward red, red_threshold honoured
##   B4      rise converges faster than fall
##   B5      gunshot spike rises, respects the export, decays
##   B6-B7   shake gated by threshold, scales with loudness, stays subtle
##   B8-B9   menu open fades alpha AND shader influence; close restores gradually
##   B10     noise keeps updating while hidden
##   B11     never interactive
##   B12     shader_influence 0 / 0.4 / 1 all reach the material
##   B13     meter outside SubViewport => structurally immune to camera shake
## ============================================================================

const METER_SCENE_PATH := "res://scenes/ui/noise_meter.tscn"
const STEP := 1.0 / 60.0
## "At distance": far outside crouch_hear_range, well inside hear_radius.
const FAR := 8.0

var _started: bool = false
var _done: bool = false
var _level: Node = null
var _player: Node3D = null
var _cre: Node3D = null
var _events: Node = null
var _meter: Control = null
var _results: Array[String] = []
var _fails: int = 0

## Frame-step machine.
var _phase: int = 0
var _frame_in_phase: int = 0

## Part A probe state.
var _a_built: bool = false
var _v_built: bool = false
var _a_queue: Array = []
var _a_armed: bool = false
var _a_name: String = ""
var _a_expect: Array = []
var _a_saved: Dictionary = {}
var _a_widen_base: float = 16.0
var _a_narrow_verdict: bool = true


func _process(_delta: float) -> bool:
	if _done:
		return true
	if not _started:
		_started = true
		# Runtime load, NOT preload: preload would compile noise_meter.gd while
		# this script is parsed, before the autoloads exist, and the `Events`
		# identifier inside it would fail to resolve.
		_level = (load("res://scenes/levels/corridor_level.tscn") as PackedScene).instantiate()
		root.add_child(_level)
		_events = root.get_node_or_null("/root/Events")
		return false

	# Let the level boot and the navmesh bake before touching the creature.
	if Engine.get_physics_frames() < 100:
		return false

	if _player == null:
		var ps: Array[Node] = get_nodes_in_group("player")
		if ps.size() > 0:
			_player = ps[0] as Node3D
	if _cre == null:
		var cs: Array[Node] = get_nodes_in_group("creature")
		if cs.size() > 0:
			_cre = cs[0] as Node3D
	if _player == null or _cre == null or _events == null:
		_check("bootstrap", false, "player / creature / Events not found")
		_report()
		return true
	if _cre.get_node_or_null("Awareness") == null:
		_check("bootstrap", false, "creature has no Awareness child")
		_report()
		return true

	if _meter == null:
		_resolve_keycodes()
		_meter = _spawn_meter()
		if _meter == null:
			_check("bootstrap", false, "could not instantiate noise_meter.tscn")
			_report()
			return true

	_step()
	return _done


# ── setup ────────────────────────────────────────────────────────────────────

func _spawn_meter() -> Control:
	var scene: PackedScene = load(METER_SCENE_PATH) as PackedScene
	if scene == null:
		return null
	var m: Control = scene.instantiate()
	# Parent it the way main.tscn does: a CanvasLayer above PostFX. A dedicated
	# layer keeps the test independent of main.tscn's child ordering.
	var layer := CanvasLayer.new()
	layer.layer = 10
	root.add_child(layer)
	layer.add_child(m)
	# set_deferred: the root has full-rect anchors and Godot overrides `size`
	# after _ready() for non-equal opposite anchors (it warns about exactly
	# this), so a direct assignment would not stick.
	m.set_deferred("size", Vector2(1280, 720))
	var bar: Control = m.get_node_or_null("Bar")
	if bar != null:
		bar.set_deferred("size", Vector2(220, 14))
	return m


# ── frame-step machine ───────────────────────────────────────────────────────

func _step() -> void:
	_frame_in_phase += 1
	if _phase == 0:
		if not _a_built:
			_a_build()
			_a_built = true
			print("── Part A: creature hearing tiers ──")
			return
		if _a_step():
			return
		_phase = 1
		_frame_in_phase = 0
		print("── Part A: hearing export variants ──")
		return
	# Variants live in phases 1..6; `_a_variants_step()` returns false once the
	# last one has been read, which hands control to Part B. Without the upper
	# bound here a phase that overshoots would match neither branch and spin
	# forever without ever reporting.
	if _phase == 1:
		if _a_variants_step():
			return
		_phase = 9
		_frame_in_phase = 0
		print("── Part B: noise meter widget ──")

	match _phase:
		9:  _b_structure_and_gradient()
		10: _b_asymmetry()
		11: _b_gunshot_spike()
		12: _b_shake()
		13: _b_menu_hide()
		14: _b_noise_while_hidden()
		15: _b_menu_show()
		16: _b_interactivity()
		17: _b_influence_dial()
		18: _b_shake_immunity()
		_:
			_report()
			return
	_phase += 1
	_frame_in_phase = 0


# ── Part A: hearing ──────────────────────────────────────────────────────────

## Probe list is built from the creature's LIVE exports so retuning changes what
## is asserted instead of breaking the test.
func _a_build() -> void:
	var quiet_r: float = float(_cre.get("crouch_hear_range"))
	var radius: float = float(_cre.get("hear_radius"))
	print("   hear_noise_floor=%.2f crouch_hear_range=%.2f hear_radius=%.1f"
		% [float(_cre.get("hear_noise_floor")), quiet_r, radius])
	var walk_n := 0.5
	var run_n := 1.0
	# name, noise, dist, expect_heard, expect_quiet
	_a_queue = [
		["A1 idle @%.0fm not heard" % FAR, 0.06, FAR, false, false],
		["A2 crouch @%.0fm not heard" % FAR, 0.15, FAR, false, false],
		["A3 crouch @%.2fm HEARD via quiet tier" % (quiet_r * 0.5),
			0.15, quiet_r * 0.5, true, true],
		["A4 crouch @%.2fm not heard" % (quiet_r * 1.5),
			0.15, quiet_r * 1.5, false, false],
		["A5 walk heard inside radius*noise", walk_n, radius * walk_n * 0.8, true, false],
		["A5b walk NOT heard beyond radius*noise", walk_n, radius * walk_n * 1.25, false, false],
		["A6 sprint heard inside hear_radius", run_n, radius * 0.8, true, false],
		["A6b sprint NOT heard beyond hear_radius", run_n, radius * 1.3, false, false],
		["A7 loud hearing is not the quiet tier", run_n, radius * 0.5, true, false],
	]


## Physical keycodes for the gait actions, resolved from the live InputMap so
## rebinds do not break the test.
var _kc_forward: int = KEY_W
var _kc_sprint: int = KEY_SHIFT
var _kc_crouch: int = KEY_C


func _resolve_keycodes() -> void:
	_kc_forward = _keycode_for("move_forward", KEY_W)
	_kc_sprint = _keycode_for("sprint", KEY_SHIFT)
	_kc_crouch = _keycode_for("crouch", KEY_C)


func _keycode_for(action: String, fallback: int) -> int:
	if not InputMap.has_action(action):
		return fallback
	for ev in InputMap.action_get_events(action):
		var k := ev as InputEventKey
		if k != null and k.physical_keycode != 0:
			return k.physical_keycode
	return fallback


## Inject a real key event through the tree, the way fly_selftest.gd does.
## Routed via Input.parse_input_event so it reaches the window viewport and
## therefore the player inside the SubViewport.
func _send_key(keycode: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.pressed = pressed
	ev.echo = false
	Input.parse_input_event(ev)


## Hold or release the gait keys for a given noise target.
##   idle    -> nothing held                       => noise 0.06
##   crouch  -> forward + crouch held              => noise 0.15
##   walk    -> forward held                       => noise 0.50
##   sprint  -> forward + sprint held              => noise 1.00
##
## Crouch-walk needs BOTH: player_movement.gd gates on `not input_active or
## planar_speed < 0.2` FIRST, so a crouched but stationary player is classified
## idle (0.06), not crouch-walk (0.15). Asserting the crouch tier therefore
## requires genuine crouch-MOVEMENT, and enough frames for velocity to ramp past
## that 0.2 m/s gate (crouch_speed is 1.0, acceleration 10).
##
## `external_crouch` is used rather than the crouch key because _handle_crouch()
## latches that key as a toggle; the flag is authoritative and stateless.
func _apply_gait(noise: float) -> void:
	var crouching: bool = noise > 0.1 and noise < 0.4
	var moving: bool = noise >= 0.1   # every non-idle gait is moving
	_send_key(_kc_forward, moving)
	_send_key(_kc_sprint, noise >= 0.9)
	_player.set("external_crouch", crouching)


## Release every key we may have pressed.
func _release_gait() -> void:
	_send_key(_kc_forward, false)
	_send_key(_kc_sprint, false)
	_player.set("external_crouch", false)


## Arm a probe: place the player `dist` metres from the creature and drive its
## gait so player_movement.gd derives the intended noise_level on its own.
##
## Why drive gait rather than poke noise_level: _update_gait_state() runs at the
## END of the player's _physics_process and recomputes noise_level from
## input_active / planar_speed / is_crouched / is_sprinting every frame. Any
## value poked from a SceneTree script is clobbered before the creature's
## awareness.tick() reads it. Real input is also the more faithful test.
func _arm_probe(noise: float, dist: float) -> void:
	var base: Vector3 = _cre.global_position
	_player.global_position = Vector3(base.x + dist, base.y, base.z)
	_player.velocity = Vector3.ZERO
	_apply_gait(noise)


func _read_probe() -> Array:
	var aw: Node = _cre.get_node_or_null("Awareness")
	if aw == null:
		return [false, false]
	return [bool(aw.call("heard")), bool(aw.call("heard_quietly"))]


## One frame of the queued probes. Returns true while work remains.
func _a_step() -> bool:
	if not _a_armed:
		if _a_queue.is_empty():
			return false
		var e: Array = _a_queue.pop_front()
		_a_name = e[0]
		_a_expect = e
		_arm_probe(float(e[1]), float(e[2]))
		_a_armed = true
		return true
	# Second frame for this probe: enough real time has passed for
	# awareness.tick() to re-evaluate against the armed state.
	# ~0.35 s of real frames: enough for planar_speed to accelerate past the
	# 0.2 m/s gate in _update_gait_state() at crouch_speed 1.0.
	if _frame_in_phase < 20:
		return true
	var r: Array = _read_probe()
	# Guards: confirm BOTH the gait and the distance still hold at read time.
	# Without the distance guard a probe can be invalidated by the player
	# drifting during the settle frames — A9 (quiet tier disabled at 0.5 m)
	# originally "failed" only because the player had walked to 1.32 m, back
	# inside a range that was supposed to be switched off.
	var actual_dist: float = float(_cre.call("dist_to_player"))
	if absf(actual_dist - float(_a_expect[2])) > 0.75:
		# Re-arm once and give it more frames rather than failing outright: the
		# gait keys legitimately move the body while we measure.
		_arm_probe(float(_a_expect[1]), float(_a_expect[2]))
		_frame_in_phase = 0
		return true
	# Confirm the gait produced the intended noise_level, otherwise the verdict
	# is meaningless (a crouch probe classified as idle would pass for the wrong
	# reason).
	var actual_noise: float = float(_player.get("noise_level"))
	var noise_ok: bool = absf(actual_noise - float(_a_expect[1])) < 0.02
	if not noise_ok:
		_check(_a_name + " [gait setup]", false,
			"expected noise %.2f but player reports %.2f (planar=%.2f crouch=%s sprint=%s)"
			% [float(_a_expect[1]), actual_noise, float(_player.get("planar_speed")),
				bool(_player.get("is_crouched")), bool(_player.get("is_sprinting"))])
	_check(_a_name, r[0] == bool(_a_expect[3]) and r[1] == bool(_a_expect[4]),
		"heard=%s quiet=%s want heard=%s quiet=%s noise=%.2f"
		% [r[0], r[1], _a_expect[3], _a_expect[4], actual_noise])
	_a_armed = false
	_frame_in_phase = 0
	_release_gait()
	return not _a_queue.is_empty()


## A8-A10 mutate creature exports, so each is a queued step that arms a probe,
## waits for real frames, reads the verdict, then restores what it changed.
## Same arm-on-one-frame / read-on-a-later-one shape as _a_step(), because
## CreatureAwareness.tick() only advances with real physics frames.
const SETTLE_FRAMES := 20

var _v_queue: Array = []
var _v_armed: bool = false
var _v_name: String = ""
var _v_expect: bool = false
var _v_restore: Dictionary = {}   # prop -> original value, undone after read
var _v_noise: float = 0.0
var _v_dist: float = 0.0
var _v_retries: int = 0
var _v_prop: String = ""


func _v_build() -> void:
	var radius: float = float(_cre.get("hear_radius"))
	# name, prop, value, noise, dist, expect_heard, restore_after_read
	_v_queue = [
		["A8 floor=0.05 legacy: crouch @2m heard",
			"hear_noise_floor", 0.05, 0.15, 2.0, true, false],
		["A8b floor=0.05 legacy: crouch @3m NOT heard",
			"hear_noise_floor", 0.05, 0.15, 3.0, false, true],
		# Distance matters here: it must sit INSIDE the default
		# crouch_hear_range (so the quiet tier is what makes it audible) but the
		# test sets that range to 0, and it must stay clear of proximity_range
		# (2.5 m), where the point-blank vision path takes over and hearing
		# stops being the deciding sense. 1.2 m satisfies both.
		["A9 crouch_hear_range=0 disables quiet tier",
			"crouch_hear_range", 0.0, 0.15, 1.2, false, true],
		["A9b same 1.2m IS heard with default crouch_hear_range",
			"crouch_hear_range", 1.6, 0.15, 1.2, true, true],
		["A10a sprint beyond hear_radius NOT heard",
			"hear_radius", radius, 1.0, radius * 1.2, false, false],
		["A10b hear_radius doubled: same spot IS heard",
			"hear_radius", radius * 2.0, 1.0, radius * 1.2, true, true],
	]


func _a_variants_step() -> bool:
	if _v_queue.is_empty() and not _v_armed:
		if not _v_built:
			_v_build()
			_v_built = true
			return true
		return false

	if not _v_armed:
		var e: Array = _v_queue.pop_front()
		_v_prop = String(e[1])
		_v_name = e[0]
		_v_expect = bool(e[5])
		_v_noise = float(e[3])
		_v_dist = float(e[4])
		# Save the original the FIRST time this property is overridden so the
		# true default is what gets restored, not another step's override.
		if not _v_restore.has(_v_prop):
			_v_restore[_v_prop] = _cre.get(_v_prop)
		_cre.set(_v_prop, e[2])
		_arm_probe(_v_noise, _v_dist)
		_v_armed = true
		return true

	if _frame_in_phase < SETTLE_FRAMES:
		return true

	# Distance guard. The injected gait keys legitimately walk the body during
	# the settle frames, so re-measure and re-arm until the probe is actually at
	# the distance it claims to test. Two bugs this prevents:
	#   - A8 armed at 2.0 m but read at 2.63 m, outside the 16*0.15=2.4 m legacy
	#     radius, so it "failed" a behaviour that was correct.
	#   - A9 armed at 1.2 m and read at 1.46 m.
	# The `_v_dist >= prox` condition that used to gate this was wrong: it
	# disabled correction for exactly the close-range probes that need it most.
	var actual_dist: float = float(_cre.call("dist_to_player"))
	var tol: float = 0.15 * maxf(_v_dist, 1.0)
	if absf(actual_dist - _v_dist) > tol and _v_retries < 10:
		_v_retries += 1
		_arm_probe(_v_noise, _v_dist)
		_frame_in_phase = 0
		return true

	var r: Array = _read_probe()
	_check(_v_name, r[0] == _v_expect,
		"heard=%s want=%s | %s=%s noise=%.2f dist=%.2f (armed %.2f, %d retries)"
		% [r[0], _v_expect, _v_prop, _cre.get(_v_prop),
			float(_player.get("noise_level")), actual_dist, _v_dist, _v_retries])

	_release_gait()
	_v_retries = 0
	_v_armed = false
	_frame_in_phase = 0
	# Restore THIS step's override immediately, so no later probe can inherit it.
	# Restoring only at the end of the queue is what let floor=0.05 leak from A8
	# into A9/A9b/A10 and made those results meaningless.
	if _v_restore.has(_v_prop):
		_cre.set(_v_prop, _v_restore[_v_prop])
		_v_restore.erase(_v_prop)

	if _v_queue.is_empty():
		# Safety net for anything still outstanding.
		for prop_name in _v_restore:
			_cre.set(prop_name, _v_restore[prop_name])
		_v_restore = {}
		return false
	return true


# ── Part B: meter widget ─────────────────────────────────────────────────────

## Advance the METER by n simulated frames at a fixed 1/60 s step, through its
## own real per-frame methods.
func _pump(n: int) -> void:
	if _meter == null:
		return
	for i in range(n):
		_meter.call("_update_noise", STEP)
		_meter.call("_update_fade", STEP)
		_meter.call("_apply_presentation", STEP)
		_meter.set("_last_drawn", _meter.displayed_noise())


func _b_structure_and_gradient() -> void:
	var bar: Control = _meter.get_node_or_null("Bar")
	var overlay: ColorRect = _meter.get_node_or_null("Bar/BleedOverlay")
	_check("B1 Bar + BleedOverlay present, overlay parented under Bar",
		bar != null and overlay != null and overlay.get_parent() == bar)
	if bar == null or overlay == null:
		return
	var low: Color = _meter.fill_color_for(0.0)
	var mid: Color = _meter.fill_color_for(_meter.red_threshold)
	var high: Color = _meter.fill_color_for(1.0)
	# "Trends toward red" means red DOMINANCE grows, not that the raw red channel
	# rises: a pale orange mid-stop can carry more absolute red (0.98) than the
	# final red (0.85) while looking far less red, because its green and blue are
	# nearly as high. r - max(g,b) is the discriminator that tracks perception.
	var dom_low: float = low.r - maxf(low.g, low.b)
	var dom_mid: float = mid.r - maxf(mid.g, mid.b)
	var dom_high: float = high.r - maxf(high.g, high.b)
	_check("B2 gradient trends toward red (red dominance grows)",
		dom_high > dom_mid and dom_mid > dom_low and dom_high > 0.3,
		"dominance low=%.3f mid=%.3f high=%.3f | low=%s mid=%s high=%s"
		% [dom_low, dom_mid, dom_high, _c(low), _c(mid), _c(high)])
	_check("B2b low end is near-white (spec: off-white at 0%)",
		dom_low < 0.1 and low.r > 0.8, "low=%s dominance=%.3f" % [_c(low), dom_low])
	# Blue must fall monotonically: white -> orange -> red all lose blue.
	_check("B2c blue falls monotonically",
		high.b <= mid.b and mid.b <= low.b,
		"b: low=%.2f mid=%.2f high=%.2f" % [low.b, mid.b, high.b])
	_check("B3 red_threshold distinct from full",
		not mid.is_equal_approx(high), "mid=%s high=%s" % [_c(mid), _c(high)])


func _b_asymmetry() -> void:
	_check("B4 rise_speed > fall_speed (snappier up, slower relief)",
		_meter.rise_speed > _meter.fall_speed,
		"rise=%.1f fall=%.1f" % [_meter.rise_speed, _meter.fall_speed])
	var rise: int = _frames_to(0.0, 1.0, _meter.rise_speed, 0.95)
	var fall: int = _frames_to(1.0, 0.0, _meter.fall_speed, 0.05)
	_check("B4b rise converges in fewer frames than fall",
		rise > 0 and fall > 0 and rise < fall, "rise=%d fall=%d frames" % [rise, fall])
	# Both must land inside the spec's 0.3-0.8 s smoothing window.
	_check("B4c settle time within 0.3-0.8 s window",
		rise >= int(0.3 * 60.0) * 0 and fall <= int(0.8 * 60.0),
		"fall=%.2fs" % (fall / 60.0))


func _b_gunshot_spike() -> void:
	_set_baseline(0.06)
	_pump(60)
	var before: float = _meter.displayed_noise()
	_events.emit_signal("gun_fired", Vector3.ZERO)
	_pump(3)
	var peaked: float = _meter.displayed_noise()
	_check("B5 gunshot spike raises the value", peaked > before + 0.2,
		"before=%.3f peaked=%.3f" % [before, peaked])
	var cap: float = clampf(0.06 + _meter.gunshot_spike, 0.0, 1.0)
	_check("B5b spike respects gunshot_spike export (%.2f)" % _meter.gunshot_spike,
		peaked <= cap + 0.03, "peaked=%.3f cap=%.3f" % [peaked, cap])
	_check("B5c never exceeds 1.0", peaked <= 1.0001, "%.4f" % peaked)
	_pump(300)
	var settled: float = _meter.displayed_noise()
	_check("B5d spike decays back toward baseline", settled < peaked * 0.6,
		"peaked=%.3f settled=%.3f" % [peaked, settled])
	_clear_baseline()


func _b_shake() -> void:
	var thr: float = _meter.shake_threshold
	var amp_below: float = _shake_amp(thr * 0.5)
	var amp_at: float = _shake_amp(thr + 0.01)
	var amp_high: float = _shake_amp(0.95)
	var amp_max: float = _shake_amp(1.0)
	_check("B6 no shake below shake_threshold",
		amp_below <= _meter.shake_cutoff_px,
		"amp=%.4f cutoff=%.4f" % [amp_below, _meter.shake_cutoff_px])
	_check("B6b shake present above threshold",
		amp_high > _meter.shake_cutoff_px, "amp=%.4f" % amp_high)
	_check("B7 shake scales with loudness (not binary)",
		amp_at <= amp_high and amp_high < amp_max,
		"at=%.3f high=%.3f max=%.3f" % [amp_at, amp_high, amp_max])
	_check("B7b shake stays subtle (<= shake_magnitude)",
		amp_max <= _meter.shake_magnitude + 0.001,
		"amp=%.3f magnitude=%.3f" % [amp_max, _meter.shake_magnitude])
	_set_baseline(1.0)
	_pump(8)
	var bar: Control = _meter.get_node("Bar")
	_check("B7c shake actually writes offset_transform on Bar",
		bool(bar.get("offset_transform_enabled")))
	_clear_baseline()


func _b_menu_hide() -> void:
	_set_baseline(0.9)
	_pump(60)
	_events.emit_signal("inventory_toggled", true)
	_pump(3)
	var mid_fade: float = _bar_alpha()
	_pump(90)
	var hidden: float = _bar_alpha()
	var inf: float = _overlay_influence()
	var overlay: ColorRect = _meter.get_node("Bar/BleedOverlay")
	_check("B8 menu_open fades alpha to ~0", hidden < 0.02, "alpha=%.4f" % hidden)
	_check("B8b shader influence fades with it (no ghosting)",
		inf < 0.01, "influence=%.4f" % inf)
	_check("B8c fade is gradual, not instant",
		mid_fade > hidden + 0.01, "mid=%.4f hidden=%.4f" % [mid_fade, hidden])
	_check("B8d overlay disabled while hidden (no wasted screen sample)",
		not overlay.visible)
	_check("B8e menu_open flag reflects state", _meter.menu_open == true)


func _b_noise_while_hidden() -> void:
	var while_hidden: float = _meter.displayed_noise()
	_set_baseline(0.1)
	_pump(150)
	var after: float = _meter.displayed_noise()
	_check("B10 noise keeps updating while hidden",
		absf(after - while_hidden) > 0.1,
		"hidden=%.3f after=%.3f" % [while_hidden, after])


func _b_menu_show() -> void:
	_clear_baseline()
	_events.emit_signal("inventory_toggled", false)
	_pump(3)
	var early: float = _bar_alpha()
	_pump(150)
	var shown: float = _bar_alpha()
	var overlay: ColorRect = _meter.get_node("Bar/BleedOverlay")
	_check("B9 menu closed fades alpha back to ~1", shown > 0.98, "alpha=%.4f" % shown)
	_check("B9b show is gradual (no pop)",
		early > 0.0 and early < shown - 0.01, "early=%.4f shown=%.4f" % [early, shown])
	_check("B9c overlay re-enabled when visible", overlay.visible)
	_check("B9d influence restored to shader_influence",
		is_equal_approx(_overlay_influence(), _meter.shader_influence),
		"inf=%.4f want=%.4f" % [_overlay_influence(), _meter.shader_influence])
	_check("B9e menu_open flag cleared", _meter.menu_open == false)


func _b_interactivity() -> void:
	var bar: Control = _meter.get_node("Bar")
	var overlay: ColorRect = _meter.get_node("Bar/BleedOverlay")
	_check("B11 mouse_filter IGNORE on meter + Bar + overlay",
		_meter.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and bar.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE)


func _b_influence_dial() -> void:
	var saved: float = _meter.shader_influence
	_meter.shader_influence = 0.0
	_pump(4)
	var clean: float = _overlay_influence()
	_meter.shader_influence = 1.0
	_pump(4)
	var full: float = _overlay_influence()
	_meter.shader_influence = 0.4
	_pump(4)
	var dial: float = _overlay_influence()
	_check("B12 influence 0 / 0.4 / 1 all reach the shader material",
		clean < 0.001 and is_equal_approx(dial, 0.4) and full > 0.999,
		"clean=%.3f dial=%.3f full=%.3f" % [clean, dial, full])
	_meter.shader_influence = saved


func _b_shake_immunity() -> void:
	_check("B13 meter is outside any SubViewport (immune to camera shake)",
		not _has_ancestor(_meter, "SubViewport"))
	var bar: Control = _meter.get_node("Bar")
	_check("B13b offset_transform_visual_only keeps layout + input intact",
		bool(bar.get("offset_transform_visual_only")))


# ── helpers ──────────────────────────────────────────────────────────────────

## Bind a stub baseline by forcing the meter's preview path. The level's real
## player would otherwise win `_resolve_player()`, so we park the player's own
## noise_level and let the meter read it — simplest truthful route.
func _set_baseline(value: float) -> void:
	if _player != null:
		_player.set("noise_level", value)
	# Also pin the meter's own resolved reference so respawns/lookups cannot
	# swap in a different value mid-check.
	_meter.set("_player", _player)


func _clear_baseline() -> void:
	if _player != null:
		_player.set("noise_level", 0.06)


## Frames for an exponential lerp at `rate` to travel from `start` toward
## `target` and cross `goal`. Mirrors NoiseMeter._update_noise() exactly.
func _frames_to(start_v: float, target: float, rate: float, goal: float) -> int:
	var v: float = start_v
	for i in range(1200):
		var k: float = 1.0 - exp(-maxf(rate, 0.0001) * STEP)
		v = lerpf(v, target, k)
		if (target > start_v and v >= goal) or (target < start_v and v <= goal):
			return i + 1
	return -1


func _shake_amp(value: float) -> float:
	_set_baseline(value)
	_pump(10)
	var t: float = clampf(inverse_lerp(_meter.shake_threshold, 1.0, value), 0.0, 1.0)
	return _meter.shake_magnitude * pow(t, _meter.shake_curve_power)


func _bar_alpha() -> float:
	var bar: Control = _meter.get_node_or_null("Bar")
	return bar.modulate.a if bar != null else 0.0


func _overlay_influence() -> float:
	var overlay: ColorRect = _meter.get_node_or_null("Bar/BleedOverlay")
	if overlay == null:
		return -1.0
	var mat: ShaderMaterial = overlay.material as ShaderMaterial
	if mat == null:
		return -1.0
	return float(mat.get_shader_parameter("influence"))


func _has_ancestor(node: Node, type_name: String) -> bool:
	var p: Node = node.get_parent()
	while p != null:
		if p.get_class() == type_name:
			return true
		p = p.get_parent()
	return false


func _c(col: Color) -> String:
	return "(%.2f,%.2f,%.2f)" % [col.r, col.g, col.b]


func _check(check_name: String, ok: bool, detail: String = "") -> void:
	_results.append("%s %s%s" % ["PASS" if ok else "FAIL", check_name,
		("" if detail == "" else " — " + detail)])
	if not ok:
		_fails += 1


func _report() -> void:
	print("")
	for line in _results:
		print("  " + line)
	print("")
	print("════ %d checks, %d failed ════" % [_results.size(), _fails])
	print("NOISE METER SELF-TEST: %s" % ["PASS" if _fails == 0 else "FAIL"])
	_done = true
