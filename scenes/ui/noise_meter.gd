extends Control
class_name NoiseMeter
## ============================================================================
## NOISE METER — how loud the player is right now, as tension feedback.
##
## Functionality only; every visual number is an @export so it can be retuned
## from the inspector or per-instance in the .tscn (house convention).
##
## PRESENTATION MODEL (see docs/NOISE_METER.md §1):
##   This Control sits ABOVE the PostFX/VHS layer, drawn crisp. The atmosphere
##   comes from `BleedOverlay`, a child ColorRect covering exactly this rect and
##   running noise_meter_bleed.gdshader, which re-samples the screen inside the
##   widget area and mixes toward a degraded look by `shader_influence`.
##   => influence is an exact linear mix weight, and there is no UV wobble.
##
## SHAKE EXEMPTION:
##   All camera shake in this project is camera-space (CameraRig springs /
##   impulses inside GameViewport). This node lives on a CanvasLayer in screen
##   space and is not a descendant of that camera, so it is structurally immune.
##   Its OWN jitter uses offset_transform_* (visual-only by default in 4.7), so
##   it cannot disturb anchoring, container sorting, or mouse hit-testing, and
##   it writes a channel nothing else touches — no stacking is possible.
##
## DECOUPLING:
##   Reads one float (PlayerMovement.noise_level) plus existing Events signals.
##   Nothing here writes back to gameplay: spikes and smoothing are DISPLAY ONLY,
##   so creature hearing balance is untouched by HUD tuning.
## ============================================================================

# ── Value ────────────────────────────────────────────────────────────────────
@export_group("Value")
## Live loudness 0..1. Driven from the player each frame; also settable directly
## (editor preview, tests, cutscenes).
@export_range(0.0, 1.0) var noise_level: float = 0.0
## When no player is bound, the meter demos itself from these bands instead of
## sitting dead at zero. Matches movement.gd's real values by default.
@export_range(0.0, 1.0) var idle_noise: float = 0.06
@export_range(0.0, 1.0) var crouch_noise: float = 0.15
@export_range(0.0, 1.0) var walk_noise: float = 0.5
@export_range(0.0, 1.0) var run_noise: float = 1.0
## Exponential lerp rates (units/second). Rise is deliberately faster than fall:
## danger should snap on, relief should ease off.
@export var rise_speed: float = 10.0
@export var fall_speed: float = 4.0
## Event spikes are added on top of the movement baseline, then decay.
@export_range(0.0, 1.0) var gunshot_spike: float = 0.85
@export_range(0.0, 1.0) var landing_spike_scale: float = 0.6
@export_range(0.0, 1.0) var wall_hit_spike_scale: float = 0.25
@export var spike_decay_rate: float = 3.0

# ── Look ─────────────────────────────────────────────────────────────────────
@export_group("Look")
## Geometry is laid out in the .tscn (size/anchors); these are the drawn bits
## that have no StyleBox equivalent.
@export var track_color: Color = Color(0.09, 0.10, 0.11, 0.78)
@export var border_color: Color = Color(0.26, 0.28, 0.30, 0.85)
@export var border_width: float = 1.0
@export var corner_radius: int = 4
@export var fill_padding: float = 2.0
## Gradient: low -> mid over [0, red_threshold], mid -> high over [threshold, 1].
@export var fill_color_low: Color = Color(0.92, 0.92, 0.90, 1.0)
@export var fill_color_mid: Color = Color(0.98, 0.78, 0.45, 1.0)
@export var fill_color_high: Color = Color(0.85, 0.12, 0.10, 1.0)
@export_range(0.0, 1.0) var red_threshold: float = 0.7
## Optional tick marks, purely decorative scale cues.
@export var tick_count: int = 5
@export var tick_color: Color = Color(1.0, 1.0, 1.0, 0.10)
@export var tick_width: float = 1.0

# ── Shake (internal loudness feedback ONLY) ──────────────────────────────────
@export_group("Shake")
@export_range(0.0, 1.0) var shake_threshold: float = 0.65
## Peak jitter in pixels at noise_level == 1.0. Keep small: this is a tell, not
## a screen shake.
@export var shake_magnitude: float = 2.5
@export var shake_frequency: float = 28.0
## Jitter ramps as t^shake_curve_power, so onset is gentle rather than binary.
@export_range(0.5, 4.0) var shake_curve_power: float = 2.0
@export var shake_seed: int = 20260912
## Below this many pixels the offset is dropped entirely (stops sub-pixel buzz
## and lets offset_transform_enabled go false when calm).
@export var shake_cutoff_px: float = 0.05

# ── Shader treatment ─────────────────────────────────────────────────────────
@export_group("Shader")
## 0.0 = fully clean UI, 1.0 = fully shader-treated.
## Ships at 1.0 (the full tape-degraded look — art decision, it just looks right).
## The original stealth-HUD spec asked for ~0.4; set it back to 0.4 for that
## subtler read. Whatever the value, it is an exact linear mix weight.
@export_range(0.0, 1.0) var shader_influence: float = 1.0
## Draw-time chromatic fringe offset (px) for the fill (R25 fix: replaced
## screen-sampling bleed, which hid the fill in-game).
@export_range(0.0, 6.0, 0.25) var bleed_pixels: float = 1.5

# ── Menu visibility ──────────────────────────────────────────────────────────
@export_group("Visibility")
## True while an in-game GUI owns the screen. Driven by Events signals (see
## _ready); also settable directly for testing. Changing it starts the fade.
@export var menu_open: bool = false:
	set(value):
		menu_open = value
		_on_menu_state_changed(value)
## Fade rates (exponential, units/second). ~0.2 s out, ~0.25 s in.
@export var fade_in_speed: float = 10.0
@export var fade_out_speed: float = 14.0
## Downward slide in pixels while hiding.
@export var slide_offset: float = 16.0
## Ease-out exponent on the slide term when showing (1.0 = linear).
@export_range(1.0, 5.0) var show_ease_power: float = 3.0
## Counted, not boolean, so overlapping menus (pause over inventory) are correct.
var _open_menu_count: int = 0

# ── Node refs ────────────────────────────────────────────────────────────────
## Untyped on purpose: see the header of noise_meter_bar.gd. Naming both halves
## would create a circular class_name dependency GDScript cannot parse.
@onready var _bar: Control = $Bar
@onready var _overlay: ColorRect = $Bar/BleedOverlay

# ── Runtime state ────────────────────────────────────────────────────────────
var _player: PlayerMovement = null
var _displayed: float = 0.0        # smoothed value actually drawn
var _spike: float = 0.0            # decaying event spike
var _fade: float = 1.0             # 0 = hidden, 1 = fully shown
var _shake_t: float = 0.0
var _noise_x: FastNoiseLite
var _noise_y: FastNoiseLite
## Preview cycling when no player exists (editor/demo only).
var _preview_t: float = 0.0
var _last_drawn: float = -1.0      # for needs_bar_redraw() change detection


func _ready() -> void:
	# Never interactive, even mid-fade — the spec requires no input while hidden
	# and there is no reason to ever catch clicks here.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _bar != null:
		_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# The bar draws itself (see NoiseMeterBar header for why the art cannot
		# live on this parent node: the shake offset only moves children).
		_bar.owner_meter = self
	if _overlay != null:
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Organic non-repeating jitter, same rationale as CameraRig's noise layers:
	# randf() per frame reads as harsh static, FastNoiseLite reads as a tremble.
	_noise_x = _make_noise(shake_seed)
	_noise_y = _make_noise(shake_seed + 101)

	# Hide sources. TODAY this is the inventory only — the debug panel is a dev
	# overlay and deliberately does NOT hide the meter (it also sets
	# Events.ui_wants_mouse, so keying off that flag would wrongly hide on F2).
	# Future menus (pause / map / journal / crafting) should either emit
	# inventory_toggled-style state or, cleaner, a generalized
	# Events.menu_state_changed(is_open) — either way they land in
	# _set_menu_open() and nothing else here changes.
	Events.inventory_toggled.connect(_set_menu_open)

	# Noise spikes. These signals already exist and are already emitted by
	# movement.gd / weapon_system.gd — the meter is just another subscriber.
	Events.hard_landed.connect(_on_hard_landed)
	Events.gun_fired.connect(_on_gun_fired)
	Events.wall_hit.connect(_on_wall_hit)

	# Start hidden if a menu is somehow already open, without animating.
	_set_menu_open(menu_open)
	_fade = 0.0 if menu_open else 1.0
	_apply_presentation(0.0)


## Same shape as CameraRig._make_noise(): one smooth scale, no micro-ripples.
## frequency stays 1.0 because shake_frequency is applied at sample time, which
## keeps the rate tunable at runtime without rebuilding the noise objects.
func _make_noise(seed_value: int) -> FastNoiseLite:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	n.seed = seed_value
	n.frequency = 1.0
	return n


# ── Menu open/close ──────────────────────────────────────────────────────────

## Single funnel for every hide source. `open` is the new state of ONE menu.
func _set_menu_open(open: bool) -> void:
	# inventory_toggled reports absolute state for that menu, so track it by
	# delta to keep the counter honest across repeated signals.
	if open:
		if _open_menu_count == 0:
			menu_open = true
		_open_menu_count += 1
	else:
		_open_menu_count = maxi(0, _open_menu_count - 1)
		if _open_menu_count == 0:
			menu_open = false


func _on_menu_state_changed(_open: bool) -> void:
	# Nothing to do beyond letting _process animate; kept as an explicit hook so
	# a future "cancel shake immediately on hide" tweak has an obvious home.
	pass


## Public API for any system that wants to add loudness without the meter
## knowing what it was (doors, glass, machinery, future interactables).
func add_noise_spike(amount: float) -> void:
	_spike = clampf(maxf(_spike, amount), 0.0, 1.0)


func _on_hard_landed(energy: float) -> void:
	add_noise_spike(landing_spike_scale * clampf(energy, 0.0, 1.0))


func _on_gun_fired(_position: Vector3) -> void:
	add_noise_spike(gunshot_spike)


func _on_wall_hit(_position: Vector3, strength: float) -> void:
	add_noise_spike(wall_hit_spike_scale * clampf(strength, 0.0, 1.0))


# ── Frame update ─────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_update_noise(delta)
	_update_fade(delta)
	_apply_presentation(delta)


## Noise tracking runs EVEN WHILE HIDDEN — only presentation is gated. That is
## what makes the bar accurate the instant a menu closes.
func _update_noise(delta: float) -> void:
	# Decay the event spike first so it relaxes over ~0.5 s regardless of gait.
	_spike = maxf(0.0, _spike - spike_decay_rate * delta * maxf(_spike, 0.2))

	var baseline := _read_baseline()
	var target := clampf(baseline + _spike, 0.0, 1.0)

	# Asymmetric exponential lerp — frame-rate independent, same idiom the
	# existing SurvivalHUD uses.
	var rate: float = rise_speed if target > _displayed else fall_speed
	var k: float = 1.0 - exp(-maxf(rate, 0.0001) * delta)
	_displayed = lerpf(_displayed, target, k)
	noise_level = _displayed


## Live player value when bound; otherwise a slow demo sweep so the widget is
## previewable in-editor and in a test harness with no level loaded.
func _read_baseline() -> float:
	_player = _resolve_player()
	if _player != null:
		return clampf(_player.noise_level, 0.0, 1.0)
	# No player bound — cycle the four bands so designers can eyeball the
	# gradient and shake without wiring a level.
	_preview_t += get_process_delta_time() * 0.25
	var bands: Array[float] = [idle_noise, crouch_noise, walk_noise, run_noise]
	var i: int = int(_preview_t) % bands.size()
	return bands[i]


## Lazy, repeating lookup: the player respawns and the level may not exist yet
## when the UI does. Group lookup matches nightmare_creature / creature_awareness,
## so the meter and the AI always agree on who the player is.
func _resolve_player() -> PlayerMovement:
	if _player != null and is_instance_valid(_player):
		return _player
	return get_tree().get_first_node_in_group("player") as PlayerMovement


func _update_fade(delta: float) -> void:
	var target: float = 0.0 if menu_open else 1.0
	var rate: float = fade_out_speed if target < _fade else fade_in_speed
	var k: float = 1.0 - exp(-maxf(rate, 0.0001) * delta)
	_fade = clampf(lerpf(_fade, target, k), 0.0, 1.0)
	# Snap when effectively settled so we stop redrawing a static widget forever.
	if absf(_fade - target) < 0.002:
		_fade = target


## Pushes fade/shake/shader state onto the child nodes.
func _apply_presentation(delta: float) -> void:
	_shake_t += delta

	# Shake ramps from shake_threshold, curved so onset is gentle, and is damped
	# by the fade so jitter settles as the meter disappears.
	var t: float = clampf(inverse_lerp(shake_threshold, 1.0, _displayed), 0.0, 1.0)
	var amp: float = shake_magnitude * pow(t, shake_curve_power) * _fade
	var offset := Vector2.ZERO
	if amp > shake_cutoff_px and _noise_x != null and _noise_y != null:
		var f: float = _shake_t * shake_frequency
		# get_noise_1d() returns roughly -1..1. Two decorrelated samples give an
		# organic 2D tremble; the +91.7 phase offset on Y is the same trick
		# CameraRig uses for its tremor axes (avoids a visible diagonal).
		offset = Vector2(
			_noise_x.get_noise_1d(f),
			_noise_y.get_noise_1d(f + 91.7)) * amp

	if _bar != null:
		# offset_transform_* is Godot 4.7's visual-only Control transform: it
		# moves the drawing (and children) without touching layout or input.
		_bar.offset_transform_enabled = offset != Vector2.ZERO
		_bar.offset_transform_position = offset
		_bar.offset_transform_visual_only = true
		# Slide rides the same channel; ease-out on show so it glides back.
		var slide_t: float = 1.0 - _fade
		if _fade > 0.0 and _fade < 1.0 and slide_t > 0.0:
			var eased: float = 1.0 - pow(1.0 - slide_t, show_ease_power)
			_bar.offset_transform_position += Vector2(0.0, slide_offset * eased)
			_bar.offset_transform_enabled = true
		_bar.modulate = Color(1, 1, 1, _fade)

	# Shader influence fades WITH alpha. Without this the degraded sample of the
	# background would linger as a faint rectangle after the bar itself is gone
	# — the "shader ghosting" the spec forbids.
	if _overlay != null:
		var mat := _overlay.material as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("influence", shader_influence * _fade)
			mat.set_shader_parameter("rect_size", _bar.size)
		_overlay.modulate = Color(1, 1, 1, _fade)
		# Fully hidden: skip the screen-texture sample entirely (it is not free).
		_overlay.visible = _fade > 0.001


# ── Accessors for NoiseMeterBar (drawing lives there, tunables live here) ────

## Smoothed value actually being drawn. Distinct from `noise_level`'s raw input.
func displayed_noise() -> float:
	return _displayed


## True when the drawn value moved enough to warrant a redraw. Lets the bar skip
## queue_redraw() while the meter is calm and fully settled.
## NOTE: `_last_drawn` is written by the bar from its own _draw(), NOT from
## _process() — stamping it before the draw would make this permanently false
## (the bar compares against the value it last actually painted).
func needs_bar_redraw() -> bool:
	if absf(_displayed - _last_drawn) > 0.0005:
		return true
	return _fade > 0.0 and _fade < 1.0


## Called by NoiseMeterBar._draw() to record what it painted.
func mark_bar_drawn(value: float) -> void:
	_last_drawn = value


## Two-segment gradient: low -> mid up to red_threshold, mid -> high after it.
func fill_color_for(v: float) -> Color:
	v = clampf(v, 0.0, 1.0)
	if v <= red_threshold:
		var t: float = 0.0 if red_threshold <= 0.0 else v / red_threshold
		return fill_color_low.lerp(fill_color_mid, t)
	var span: float = maxf(1.0 - red_threshold, 0.0001)
	var t2: float = clampf((v - red_threshold) / span, 0.0, 1.0)
	return fill_color_mid.lerp(fill_color_high, t2)


# ── Editor preview ───────────────────────────────────────────────────────────

## Lets the widget show a representative state inside the editor without running
## the game. Kept explicit (no @tool on the class) so nothing ticks in-editor by
## accident; call it from a debug scene if you want a live editor preview.
func preview_noise(value: float) -> void:
	_displayed = clampf(value, 0.0, 1.0)
	_spike = 0.0
	if _bar != null:
		_bar.queue_redraw()
