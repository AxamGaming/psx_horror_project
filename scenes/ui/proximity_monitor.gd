extends Control
class_name ProximityMonitor
## ============================================================================
## PROXIMITY MONITOR ("the cardiogram") — how close the creature is, as a
## found-footage biosignal strip. See docs/PROXIMITY_MONITOR_DESIGN.md.
##
## Reads distance (and awake state) from the creature, writes NOTHING back to
## gameplay. Distance-only by design: never direction.
##
## VISIBILITY CONTRACT (art direction, Round 25):
##   - creature asleep  -> widget fully hidden (faded out smoothly)
##   - creature awake   -> faded back in smoothly
##   - any menu open    -> hidden (same funnel as the noise meter)
##   - no text label by default (show_label = false)
##
## AUDIO: one realistic lub-dub one-shot (audio/sfx/heartbeat.wav, Woodingp,
## Freesound 116642, CC0) per visual beat, volume/pitch scaled by proximity.
## Widget-owned player so the feature stays self-contained; bus is an export.
##
## FUNCTIONALITY ONLY here; all layout lives in proximity_monitor.tscn and all
## drawing in proximity_trace.gd (house convention, same split as NoiseMeter).
## ============================================================================

# ── Value / source ───────────────────────────────────────────────────────────
@export_group("Source")
## Everything beyond this distance reads as FAR (flatline).
@export var max_range: float = 24.0
## While the creature is dormant the monitor stays hidden. Flip off to make it
## an always-on presence sensor.
@export var require_awake: bool = true
## Editor / capture mode: ignore the creature, use preview_prox, stay visible.
@export var preview_mode: bool = false
@export_range(0.0, 1.0) var preview_prox: float = 0.0

# ── Proximity curve ──────────────────────────────────────────────────────────
@export_group("Curve")
@export_range(0.2, 4.0) var prox_curve: float = 1.4
## Trace amplitude endpoints (fraction of half-height).
@export_range(0.0, 1.0) var amp_far: float = 0.06
@export_range(0.0, 1.0) var amp_contact: float = 0.92
@export_range(0.2, 4.0) var amp_curve: float = 1.6
## Beat rate endpoints (Hz): resting -> panicked.
@export var beat_hz_far: float = 0.8
@export var beat_hz_contact: float = 2.6
## High-frequency tremble on the trace, scaled by prox.
@export_range(0.0, 1.0) var jitter_amount: float = 0.10
## CONTACT clipping: peaks above this fraction of half-height are flat-topped.
@export_range(0.0, 1.0) var clip_top: float = 0.80
## Band boundaries as eased-proximity values (colour/LED/label stops).
@export_range(0.0, 1.0) var near_at: float = 0.17
@export_range(0.0, 1.0) var close_at: float = 0.50
@export_range(0.0, 1.0) var contact_at: float = 0.83

# ── Look ─────────────────────────────────────────────────────────────────────
@export_group("Look")
@export var color_far: Color = Color(0.62, 0.78, 0.60, 1.0)
@export var color_near: Color = Color(0.95, 0.78, 0.42, 1.0)
@export var color_close: Color = Color(0.98, 0.55, 0.25, 1.0)
@export var color_contact: Color = Color(0.95, 0.16, 0.14, 1.0)
@export var alpha_far: float = 0.35
@export var alpha_near: float = 0.75
@export var alpha_close: float = 0.95
@export var alpha_contact: float = 1.0
@export var trace_width: float = 2.0
## Draw-time chromatic fringe offset (px). The R25 screen-sampling bleed
## hid widget content in-game; fringes replace it (see ui_weather.gdshader).
@export_range(0.0, 6.0, 0.25) var bleed_pixels: float = 1.5
## Phosphor glow blob behind the trace centre (the mockup's hot middle).
@export_range(0.0, 1.0) var glow_strength: float = 0.55
@export_range(0.0, 4) var led_count: int = 4
@export var led_color: Color = Color(0.95, 0.20, 0.16, 1.0)
## Text label (TRK FAR / NEAR / CLOSE / CONTACT). Art direction: OFF.
@export var show_label: bool = false
@export var label_color: Color = Color(0.85, 0.90, 0.82, 0.9)

# ── Shake (internal, CONTACT only) ───────────────────────────────────────────
@export_group("Shake")
@export var shake_magnitude: float = 1.5
@export var shake_frequency: float = 26.0
@export var shake_seed: int = 4711

# ── Shader treatment (same shader as the noise meter) ────────────────────────
@export_group("Shader")
@export_range(0.0, 1.0) var shader_influence: float = 1.0

# ── Visibility / fade ────────────────────────────────────────────────────────
@export_group("Visibility")
@export var fade_in_speed: float = 6.0
@export var fade_out_speed: float = 8.0
@export var slide_offset: float = 12.0
@export_range(1.0, 5.0) var show_ease_power: float = 3.0

# ── Audio ────────────────────────────────────────────────────────────────────
@export_group("Audio")
@export var heartbeat_stream: AudioStream = preload("res://audio/sfx/heartbeat.wav")
## Beats only sound above this eased proximity (silence while far away).
@export_range(0.0, 1.0) var audio_threshold: float = 0.12
@export var audio_vol_far_db: float = -12.0
@export var audio_vol_contact_db: float = 0.0
@export_range(0.0, 0.2) var audio_pitch_jitter: float = 0.04
@export var heart_bus: String = "SFX"
## DEBUG: ignore fade/threshold gating and beat whenever the creature exists.
## Use to verify audibility on a new machine/setup in one click.
@export var debug_force_beats: bool = false

# ── Node refs ────────────────────────────────────────────────────────────────
@onready var _trace: Control = $Trace
@onready var _overlay: ColorRect = $Trace/BleedOverlay

# ── Runtime state ────────────────────────────────────────────────────────────
var _creature: Node3D = null
var _prox: float = 0.0            # eased 0..1, the single driving value
var _raw_prox: float = 0.0
var _phase: float = 0.0           # beat phase, wraps per heartbeat
var _fade: float = 0.0
var _open_menu_count: int = 0
var _menu_open: bool = false
var _awake: bool = false
var _shake_t: float = 0.0
var _noise_j: FastNoiseLite
var _heart_player: AudioStreamPlayer = null
var _last_beat_int: int = -1
## Debug/telemetry: how many heartbeat one-shots were triggered (selftest).
var beats_played: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _trace != null:
		_trace.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Duck-typed back-reference (no class_name both ways: circular
		# class_name deps do not parse — same trick as NoiseMeterBar).
		_trace.monitor = self
	if _overlay != null:
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_noise_j = FastNoiseLite.new()
	_noise_j.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_j.fractal_type = FastNoiseLite.FRACTAL_NONE
	_noise_j.seed = shake_seed
	_noise_j.frequency = 1.0

	# Menu funnel identical to the noise meter's (inventory today; any future
	# menu emits into the same handler).
	Events.inventory_toggled.connect(_set_menu_open)

	# Widget-owned heartbeat voice: self-contained feature, bus is tunable.
	_heart_player = AudioStreamPlayer.new()
	_heart_player.name = "Heartbeat"
	_heart_player.stream = heartbeat_stream
	if heartbeat_stream == null:
		push_warning("ProximityMonitor: heartbeat_stream is null — the wav is " \
			+ "missing/unimported; no heartbeat audio possible. Re-apply " \
			+ "audio/sfx/heartbeat.wav and reimport.")
	var bi: int = AudioServer.get_bus_index(heart_bus)
	if bi < 0:
		var warn := "ProximityMonitor: bus '%s' not found — falling back to Master; heartbeat bypasses SFX processing." % str(heart_bus)
		push_warning(warn)
		_heart_player.bus = "Master"
	else:
		_heart_player.bus = heart_bus
		if AudioServer.is_bus_mute(bi):
			var warn2 := "ProximityMonitor: bus '%s' is MUTED — heartbeat silent until unmuted." % str(heart_bus)
			push_warning(warn2)
	add_child(_heart_player)

	_fade = 1.0 if preview_mode else 0.0
	_apply_presentation(0.0)


# ── Menu open/close (counter-based, overlapping menus safe) ──────────────────

func _set_menu_open(open: bool) -> void:
	if open:
		_open_menu_count += 1
	else:
		_open_menu_count = maxi(0, _open_menu_count - 1)
	_menu_open = _open_menu_count > 0


# ── Frame update ─────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_update_source(delta)
	_update_fade(delta)
	_apply_presentation(delta)
	_update_audio()


## Resolve creature, distance, awake state; integrate the beat phase.
func _update_source(delta: float) -> void:
	if preview_mode:
		_raw_prox = clampf(preview_prox, 0.0, 1.0)
		_awake = true
	else:
		_creature = _resolve_creature()
		if _creature == null:
			_raw_prox = 0.0
			_awake = false
		else:
			var dist: float = float(_creature.call("dist_to_player"))
			_raw_prox = clampf(1.0 - dist / maxf(max_range, 0.001), 0.0, 1.0)
			_awake = bool(_creature.get("_awake"))
	# Smooth the raw value a touch so teleport-tier distance jumps (lunges,
	# unsticks) read as a swell, not a step.
	_prox = lerpf(_prox, pow(_raw_prox, prox_curve), 1.0 - exp(-8.0 * delta))
	_phase += lerpf(beat_hz_far, beat_hz_contact, _prox) * delta


func _resolve_creature() -> Node3D:
	if _creature != null and is_instance_valid(_creature):
		return _creature
	var cs: Array[Node] = get_tree().get_nodes_in_group("creature")
	return cs[0] as Node3D if cs.size() > 0 else null


## Visibility = awake (unless exempt) AND no menu. One fade factor drives
## alpha, slide, shader influence and the audio gate.
func _update_fade(delta: float) -> void:
	var want_visible: bool = true
	if not preview_mode:
		want_visible = (_awake or not require_awake) and not _menu_open
	var target: float = 1.0 if want_visible else 0.0
	var rate: float = fade_out_speed if target < _fade else fade_in_speed
	var k: float = 1.0 - exp(-maxf(rate, 0.0001) * delta)
	_fade = clampf(lerpf(_fade, target, k), 0.0, 1.0)
	if absf(_fade - target) < 0.002:
		_fade = target


func _apply_presentation(delta: float) -> void:
	_shake_t += delta
	# CONTACT jitter: visual-only offset on the trace node, exactly like the
	# noise meter's internal shake (camera-shake immune by construction).
	var amp: float = 0.0
	if _prox >= contact_at:
		var over: float = clampf(inverse_lerp(contact_at, 1.0, _prox), 0.0, 1.0)
		amp = shake_magnitude * over * _fade
	var offset := Vector2.ZERO
	if amp > 0.05 and _noise_j != null:
		var f: float = _shake_t * shake_frequency
		offset = Vector2(_noise_j.get_noise_1d(f), _noise_j.get_noise_1d(f + 91.7)) * amp
	if _trace != null:
		# Fully hidden: skip drawing the strip at all (modulate 0 still costs a
		# draw call otherwise).
		_trace.visible = _fade > 0.001
		_trace.offset_transform_enabled = offset != Vector2.ZERO or _slide_active()
		_trace.offset_transform_position = offset + _slide_vector()
		_trace.offset_transform_visual_only = true
		_trace.modulate = Color(1, 1, 1, _fade)
	if _overlay != null:
		var mat := _overlay.material as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("influence", shader_influence * _fade)
			mat.set_shader_parameter("rect_size", _trace.size)
		_overlay.modulate = Color(1, 1, 1, _fade)
		_overlay.visible = _fade > 0.001


func _slide_active() -> bool:
	return _fade > 0.0 and _fade < 1.0


func _slide_vector() -> Vector2:
	if not _slide_active():
		return Vector2.ZERO
	var t: float = 1.0 - _fade
	var eased: float = 1.0 - pow(1.0 - t, show_ease_power)
	return Vector2(0.0, slide_offset * eased)


## One lub-dub per visual beat while the widget is meaningfully visible.
func _update_audio() -> void:
	if _heart_player == null or heartbeat_stream == null:
		return
	var beat_int: int = int(_phase)
	if beat_int == _last_beat_int:
		return
	_last_beat_int = beat_int
	var audible: bool = debug_force_beats or (_fade > 0.5 and _prox > audio_threshold)
	if not audible:
		return
	if beats_played == 0:
		# One-shot diagnostic: proves the voice fires and where it is routed.
		# push_warning surfaces in the console AND in creature_log.txt's
		# ENGINEERR drain, so an uploaded log answers "why no heartbeat".
		# NOTE: format into a variable FIRST — "%" binds tighter than "+", so
		# formatting a concatenated literal misaligns the arguments (R25b bug:
		# "%.2f" received the bus name and errored on every first beat).
		var diag := "HEARTBEAT DIAG first beat: vol=%.1f dB bus=%s len=%.2f prox=%.2f fade=%.2f forced=%s" % [
			_heart_player.volume_db, str(_heart_player.bus),
			heartbeat_stream.get_length() if heartbeat_stream else -1.0,
			_prox, _fade, str(debug_force_beats)]
		push_warning(diag)
	var vol: float = lerpf(audio_vol_far_db, audio_vol_contact_db,
		clampf(inverse_lerp(audio_threshold, 1.0, _prox), 0.0, 1.0))
	_heart_player.volume_db = vol
	_heart_player.pitch_scale = 1.0 + randf_range(-audio_pitch_jitter, audio_pitch_jitter)
	_heart_player.play()
	beats_played += 1


# ── Accessors for the trace (drawn half) ─────────────────────────────────────

func current_prox() -> float:
	return _prox


func beat_phase() -> float:
	return _phase


func band_index() -> int:
	if _prox >= contact_at:
		return 3
	if _prox >= close_at:
		return 2
	if _prox >= near_at:
		return 1
	return 0


## Four-stop colour ramp by eased proximity.
func trace_color() -> Color:
	if _prox < near_at:
		return color_far.lerp(color_near, clampf(_prox / maxf(near_at, 0.001), 0.0, 1.0))
	if _prox < close_at:
		var t: float = clampf(inverse_lerp(near_at, close_at, _prox), 0.0, 1.0)
		return color_near.lerp(color_close, t)
	var t2: float = clampf(inverse_lerp(close_at, contact_at, _prox), 0.0, 1.0)
	return color_close.lerp(color_contact, t2)


func trace_alpha() -> float:
	match band_index():
		1: return alpha_near
		2: return alpha_close
		3: return alpha_contact
	return alpha_far


func trace_amp() -> float:
	return lerpf(amp_far, amp_contact, pow(_prox, amp_curve))


func jitter_seed_noise() -> FastNoiseLite:
	return _noise_j
