class_name CameraRig
extends Camera3D
## ============================================================================
## CAMERA RIG — v4 FOUND-FOOTAGE gait engine + spring / landing / impulse layer.
##
## SINGLE-WRITER RULE (Rule 1): this script is the ONLY writer of MainCamera's
## local position / rotation / fov. MouseLook owns pivot pitch + body yaw above
## it; PlayerMovement owns the body position below it.
##
## STYLE HISTORY (playtest-driven):
##   v1: raw noise waveform ............ "weird but correct" (drunk float)
##   v2: periodic gait backbone ........ "realistic" but metronomic/gamey
##   v3: softer dips, proportional FOV . better, still "not correct"
##   v4: FOUND FOOTAGE — the bob is a human carrying a camera, not an animated
##       gait cycle. Rounded bounce (low dip_sharpness), "flesh follow-through"
##       (the gait signal passes through a lag/mix stage so every movement
##       trails + overshoots slightly), gaze COUNTER-NOD (pitch follows the
##       LAGGED vertical: head dips -> gaze rotates up, the handheld
##       stabilization reflex), horizon never level (slow roll wander + tiny
##       high-frequency hand tremor), per-step random depth, and breathing
##       that becomes panting with exertion.
##
## PIPELINE ORDER inside _process (fixed — do not reorder):
##   mass -> energy -> phase advance -> step boundary (heel-strike + per-step
##   random depth) -> gait-start dip -> landing -> suppress decay ->
##   gait curves + found-footage layers -> spring integration -> inertia lag ->
##   fov -> [Phase 5 quantize hook] -> single WRITE
##
## NOTE for Phase 8: heel_strike fires at the phase boundary, while the visual
## dip lands ~50-80 ms later due to flesh lag. If footsteps feel early, either
## raise flesh_lag_rate (less lag) or delay audio by the measured offset.
## ============================================================================

enum FocusMode { EXPLORING, INVENTORY, AIMING }

## strength ~0..1.6 (gait+energy) for audio velocity; foot: 0=left, 1=right.
signal heel_strike(strength: float, foot: int)

@export_group("References")
@export var player_path: NodePath = NodePath("../..")

@export_group("Energy")
@export var energy_rise_rate: float = 5.0     # amplitude envelope swells in ~0.2 s
@export var energy_fall_rate: float = 3.0     # bob lingers ~0.3 s after stop
@export var min_step_energy: float = 0.12     # below: no stepping, no strikes

@export_group("Cadence (steps per second)")
@export var walk_step_rate: float = 1.9       # speed pass: cadence up so shorter strides never glide
@export var sprint_step_rate: float = 2.6     # 4.5 m/s / 2.6 ≈ 1.7 m stride — real sprint territory
@export var crouch_step_rate: float = 1.2
@export_range(0.0, 1.0) var cadence_floor: float = 0.6   # min cadence fraction while moving (kills slow-mo)
@export var step_rate_smooth: float = 6.0     # cadence change smoothing

@export_group("Gait Backbone")
@export_range(0.0, 2.0) var bob_intensity: float = 1.0    # MASTER scale for all gait motion — tune this first
@export_range(0.0, 0.5) var dip_sharpness: float = 0.10   # v4: rounded bounce, not sharp heel hits
@export var vert_amp_walk: float = 0.024      # meters at full walk energy
@export var vert_amp_sprint_mult: float = 2.2 # sprint ≈ 0.053 m bounding bounce
@export var vert_amp_crouch_mult: float = 0.6
@export var lat_amp_walk: float = 0.012       # v4.1: was 0.020 — big sway made the path arc "down-left/down-right"; real head lateral ≈ 50% of vertical
@export var surge_amp_walk: float = 0.008     # v4.1: was 0.012
@export var roll_amp_deg: float = 0.9         # v4.1: was 1.6 — roll was amplifying the waddle
@export var roll_sprint_mult: float = 1.5     # v4.1: was 1.8
@export var yaw_amp_deg: float = 0.6          # v4.1: was 0.8

@export_group("Found-Footage Feel")
@export var flesh_lag_rate: float = 12.0      # how fast the secondary motion catches up
@export_range(0.0, 1.0) var flesh_lag_mix: float = 0.55   # 0 = crisp game-bob, 1 = fully lagged handheld
@export var pitch_amp_deg: float = 0.7        # gaze COUNTER-NOD: deg per unit of lagged dip
@export var roll_wander_deg: float = 0.3      # v4.1: was 0.6 — slow horizon drift (never level)
@export var hand_tremor_deg: float = 0.08     # v4.1: was 0.15 — idle buzz complaint
@export_range(0.0, 1.0) var tremor_idle_scale: float = 0.35  # v4.1: tremor floor at idle; full at sprint = (this + energy)
@export var hand_tremor_rate: float = 7.0     # v4.1: was 9.0 (~Hz)
@export_range(0.0, 0.5) var step_randomize: float = 0.15  # per-step random depth ±%

@export_group("Noise Seasoning (organic, non-repeating)")
@export_range(0.0, 0.5) var step_variation: float = 0.22   # v4: slow ±% drift across steps
@export var var_noise_rate: float = 0.35
@export_range(0.0, 0.3) var timing_jitter_rad: float = 0.12 # v4: human cadence irregularity
@export_range(0.0, 1.0) var noise_mix: float = 0.25         # thin raw-noise layer over the curves
@export_range(0.05, 3.0) var noise_freq_vert: float = 1.0
@export_range(0.05, 3.0) var noise_freq_lat: float = 0.9
@export var noise_units_per_step: float = 1.0
@export var noise_seed: int = 1337

@export_group("Breathing")
@export var breath_amp: float = 0.007         # v4.1: was 0.012 — calm at idle, felt not seen
@export var breath_rate: float = 0.25
@export var breath_time_scale: float = 2.5    # noise-units per second of breath time
@export_range(0.05, 2.0) var noise_freq_breath: float = 0.35
@export var breath_roll_amp_deg: float = 0.18 # v4.1: was 0.35
@export var breath_exertion_mult: float = 2.5 # sprint -> panting (rate + depth)

@export_group("Focal Shift (FOV)")
@export var base_fov: float = 75.0
@export var aim_fov: float = -12.0            # zoom offset while aiming (weapon-driven)
@export var fov_bob_gain: float = 25.0        # FOV degrees per meter of dip (auto-scales with amplitude)
@export var fov_sprint_add: float = 5.0
@export var fov_sprint_rate: float = 4.0
@export var fov_punch_per_impact: float = 1.2
@export var fov_punch_decay: float = 6.0

@export_group("Spring (weight & elasticity)")
@export var spring_stiffness: float = 90.0
@export var spring_damping: float = 11.0      # zeta ~0.58: one clean overshoot
@export var roll_stiffness: float = 70.0      # roll spring works in DEGREES
@export var roll_damping: float = 9.0
@export var spring_mass: float = 1.0          # baseline; carry weight raises it
@export var spring_max_dt: float = 0.008333   # sub-step cap (1/120 s)

@export_group("Landing Response")
@export var land_dip_scale: float = 0.030     # spring vel (m/s) per m/s of fall
@export var land_hard_threshold: float = 7.0
@export var land_hard_vel: float = 0.55
@export var land_roll_deg: float = 40.0       # random roll vel (deg/s) when hard
@export var land_fov_punch: float = 2.5
@export var start_dip_vel: float = 0.35       # gait-start "heavy first step"
@export var start_dip_cooldown: float = 0.6

@export_group("Inertia (head lag)")
@export var inertia_scale: float = 0.018
@export var inertia_max: float = 0.05
@export var inertia_smooth_rate: float = 8.0
@export var inertia_pitch_deg: float = 0.5
@export var inertia_yaw_deg: float = 0.4

@export_group("Impacts (apply_impulse API — Phase 7 callers)")
@export var impulse_vel_scale: float = 0.9
@export var impulse_roll_deg_scale: float = 30.0
@export_range(0.05, 5.0) var suppress_full_at: float = 0.6  # magnitude that fully kills bob noise
@export var suppress_decay_rate: float = 2.5  # organic sway blends back over ~0.4 s

@export_group("Retro Quantization (Phase 5 snap filter)")
@export var snap_enabled: bool = true
@export var snap_position_step: float = 0.005   # metres; ≈0.6 low-res px at 2 m depth (640x360)
@export var snap_rotation_step_deg: float = 0.05
@export var snap_impact_mult: float = 3.0       # grid COARSENS during impacts -> jagged PSX jolts

@export_group("Gameplay Hooks (Phase 6)")
@export_range(0.0, 1.0) var focus_gait_mult_inventory: float = 0.2  # gait damps to a tense sway while menu open
@export_range(0.0, 1.0) var focus_gait_mult_aiming: float = 0.35    # steadying: held-breath stillness
@export var focus_blend_rate: float = 6.0       # smooth crossfade between focus modes
@export var breath_gasping_mult: float = 1.5    # extra breath rate+depth at zero stamina
@export var aim_tremble_mult: float = 2.0       # tremble multiplier when aiming at low stamina/health
@export_range(0.0, 1.0) var low_state_threshold: float = 0.35
@export var limp_depth_extra: float = 0.6       # limp "bad step" extra depth (+60%)
@export var limp_roll_kick_deg: float = 25.0    # roll vel kick per limp step (deg/s)

@export_group("Impacts Phase 7 (damage pipeline)")
@export var damage_impulse_scale: float = 0.2   # HP damage -> impulse magnitude (25 HP -> 5.0)
@export var debug_hit_amount: float = 25.0      # arrow-key test hits
@export var daze_threshold: float = 20.0        # damage that triggers the dazed state
@export var daze_duration: float = 2.5
@export var daze_mass_mult: float = 1.5         # doc: "increases weight and friction" while dazed

@export_group("Carry Weight API (Phase 6 wires real inventory)")
@export var mass_per_weight: float = 0.6
@export var amp_per_weight: float = 0.25
@export var mass_smooth_rate: float = 2.0

@export_group("Debug")
@export var show_debug: bool = false          # dev overlay; F3 toggles at runtime
@export var debug_font_size: int = 14

# --- Public runtime state (read-only for other systems) ------------------------
var energy: float = 0.0
var step_phase: float = 0.0                   # 1.0 = one footfall; integers = heel-strikes
var step_rate: float = 0.0                    # current steps/second (smoothed)
var carry_weight: float = 0.0
var stamina: float = 1.0                      # stub — Phase 6 (tremble/gasp)
var health01: float = 1.0                     # stub — Phase 6 (limp)
var focus_mode: FocusMode = FocusMode.EXPLORING
var noise_suppress: float = 0.0

# --- Internals ------------------------------------------------------------------
var _player: PlayerMovement
var _mass: float = 1.0

var _noise_vert: FastNoiseLite    # thin raw layer (vertical)
var _noise_lat: FastNoiseLite     # thin raw layer (lateral)
var _noise_var: FastNoiseLite     # slow step-depth variation + roll wander
var _noise_jit: FastNoiseLite     # cadence timing jitter
var _noise_trem: FastNoiseLite    # hand tremor (~9 Hz)
var _noise_breath: FastNoiseLite  # breathing drift
var _rng: RandomNumberGenerator

var _spring_pos: Vector3 = Vector3.ZERO
var _spring_vel: Vector3 = Vector3.ZERO
var _spring_acc: float = 0.0
var _roll_pos: float = 0.0                    # degrees (impulse domain)
var _roll_vel: float = 0.0                    # degrees/s

var _bob_offset: Vector3 = Vector3.ZERO
var _bob_rot: Vector3 = Vector3.ZERO          # radians (pitch, yaw, roll)
var _bob_lagged_offset: Vector3 = Vector3.ZERO
var _bob_lagged_rot: Vector3 = Vector3.ZERO
var _step_depth: float = 1.0                  # smoothed per-step depth multiplier
var _step_depth_target: float = 1.0
var _focus_mult: float = 1.0                  # smoothed focus-mode gait damping
var _daze_timer: float = 0.0                  # seconds of dazed state left
var _daze_factor: float = 1.0                 # smoothed daze weight multiplier
var _breath_phase: float = 0.0
var _breath_offset: Vector3 = Vector3.ZERO
var _breath_rot: Vector3 = Vector3.ZERO

var _inertia_offset: Vector3 = Vector3.ZERO
var _inertia_pitch: float = 0.0               # degrees
var _inertia_yaw: float = 0.0                 # degrees
var _pv_smoothed: Vector3 = Vector3.ZERO

var _fov_sprint_smoothed: float = 0.0
var _fov_punch: float = 0.0
var _aim_zoom_target: float = 0.0
var _aim_zoom_smooth: float = 0.0

var _last_step_idx: int = 0
var _last_start_dip_time: float = -10.0
var _strike_count: int = 0
var _prev_gait: int = -1
var _was_grounded: bool = true

var _time: float = 0.0
var _dead: bool = false
var _debug_layer: CanvasLayer
var _debug_label: Label
var _debug_timer: float = 0.0


func _ready() -> void:
	_player = get_node_or_null(player_path) as PlayerMovement
	assert(_player != null, "CameraRig: player_path must point at the PlayerMovement body (default ../.. from MainCamera).")

	_noise_vert = _make_noise(noise_seed, noise_freq_vert)
	_noise_lat = _make_noise(noise_seed + 101, noise_freq_lat)
	_noise_var = _make_noise(noise_seed + 202, 0.5)
	_noise_jit = _make_noise(noise_seed + 303, 0.4)
	_noise_trem = _make_noise(noise_seed + 505, 1.0)
	_noise_breath = _make_noise(noise_seed + 404, noise_freq_breath)

	_rng = RandomNumberGenerator.new()
	_rng.seed = noise_seed

	_mass = maxf(spring_mass, 0.05)
	fov = base_fov
	_prev_gait = _player.gait
	_was_grounded = _player.is_on_floor()
	_last_step_idx = int(floorf(step_phase))
	Events.inventory_toggled.connect(_on_inventory_toggled)
	Events.player_damaged.connect(_on_player_damaged)
	Events.wall_hit.connect(_on_wall_hit)
	Events.player_died.connect(_on_player_died_flag)
	Events.player_respawned.connect(_on_player_respawned_flag)
	Events.main_camera = self


func _on_player_died_flag() -> void:
	_dead = true


## Respawn also resets the whole physical state: no ghost wobble, no stuck
## suppress/daze, spring re-centered.
func _on_player_respawned_flag() -> void:
	_dead = false
	_spring_pos = Vector3.ZERO
	_spring_vel = Vector3.ZERO
	_roll_pos = 0.0
	_roll_vel = 0.0
	noise_suppress = 0.0
	_daze_timer = 0.0
	_daze_factor = 1.0


## Small spring kick WITHOUT noise suppression / FOV punch — for environmental
## feedback (heavy doors, wall slams) that shouldn't feel like combat damage.
func apply_nudge(direction_world: Vector3, magnitude: float) -> void:
	if _dead or magnitude <= 0.0 or direction_world.length_squared() < 0.0001:
		return
	var local: Vector3 = global_transform.basis.transposed() * direction_world.normalized()
	_spring_vel += -local * magnitude


func _on_wall_hit(hit_position: Vector3, strength: float) -> void:
	if _dead:
		return
	apply_nudge(hit_position - global_position, strength * 0.9)

	if show_debug:
		_build_debug_overlay()


func _process(delta: float) -> void:
	delta = minf(delta, 1.0 / 30.0)  # Rule 3: spike guard (alt-tab, breakpoints)
	_time += delta

	_update_mass(delta)
	_update_daze(delta)
	_update_energy(delta)
	_advance_phase(delta)
	_check_step_boundary()
	_detect_gait_start()
	_detect_landing()
	_update_noise_suppress(delta)
	_update_focus(delta)
	_compute_bob(delta)
	_integrate_spring(delta)
	_update_inertia(delta)
	_update_fov(delta)
	_apply_to_camera()
	_update_debug(delta)


# ------------------------------------------------------------------------------
# Public API (the black box surface — Rule 2)
# ------------------------------------------------------------------------------

func set_carry_weight(w: float) -> void:
	carry_weight = clampf(w, 0.0, 1.0)


func set_stamina(s: float) -> void:
	stamina = clampf(s, 0.0, 1.0)


func set_health(h: float) -> void:
	health01 = clampf(h, 0.0, 1.0)


func set_focus_mode(m: FocusMode) -> void:
	focus_mode = m


## `direction_world` = where the blow came FROM (hit from the right => points
## right). The camera snaps the OPPOSITE way and rolls, per the design doc.
## Magnitude ~4-8 feels like a solid enemy swipe.
func apply_impulse(direction_world: Vector3, magnitude: float) -> void:
	if _dead or magnitude <= 0.0 or direction_world.length_squared() < 0.0001:
		return
	var local: Vector3 = global_transform.basis.transposed() * direction_world.normalized()
	_spring_vel += -local * magnitude * impulse_vel_scale
	_roll_vel += -local.x * magnitude * impulse_roll_deg_scale
	_fov_punch += magnitude * fov_punch_per_impact
	# "Breaking the noise loop": big hits silence the organic bob briefly,
	# then it blends back as suppress decays (~0.4 s at magnitude 1.0).
	noise_suppress = clampf(magnitude / suppress_full_at, 0.0, 1.0)


# ------------------------------------------------------------------------------
# Pipeline steps
# ------------------------------------------------------------------------------

func _update_mass(delta: float) -> void:
	var target_mass: float = spring_mass * (1.0 + carry_weight * mass_per_weight) * _daze_factor
	_mass = lerpf(_mass, target_mass, 1.0 - exp(-mass_smooth_rate * delta))
	_mass = maxf(_mass, 0.05)  # never divide by ~zero


func _update_energy(delta: float) -> void:
	var gait_max: float = _player.walk_speed
	match _player.gait:
		PlayerMovement.Gait.SPRINT:
			gait_max = _player.sprint_speed
		PlayerMovement.Gait.CROUCH:
			gait_max = _player.crouch_speed
	var target: float = clampf(_player.planar_speed / maxf(gait_max, 0.1), 0.0, 1.0)
	var rate: float = energy_rise_rate if target > energy else energy_fall_rate
	energy = lerpf(energy, target, 1.0 - exp(-rate * delta))


func _advance_phase(delta: float) -> void:
	var gait_rate: float = _current_step_rate()
	var target_rate: float = 0.0
	if _player.input_active and energy > min_step_energy:
		# Cadence floor keeps early/late steps at human tempo — amplitude
		# carries the "starting/stopping" feel, never slow-motion cadence.
		target_rate = gait_rate * (cadence_floor + (1.0 - cadence_floor) * energy)
	# No input held = phase halts immediately. The bob amplitude then fades
	# via energy; no phantom "settling step", no footfall after key release.
	step_rate = lerpf(step_rate, target_rate, 1.0 - exp(-step_rate_smooth * delta))
	if step_rate < 0.02:
		step_rate = 0.0
	step_phase += step_rate * delta
	# Wrap to keep float32 sampling precise after marathon sessions (~11 days).
	if step_phase > 1000000.0:
		step_phase -= 1000000.0


func _check_step_boundary() -> void:
	var idx: int = int(floorf(step_phase))
	if idx <= _last_step_idx:
		return
	_last_step_idx = idx
	# v4: every step gets its own depth — nobody walks like a metronome.
	_step_depth_target = 1.0 + _rng.randf_range(-step_randomize, step_randomize)
	# Asymmetrical limp at critical health: every second step dips deeper and
	# drags a painful tilt with it (design doc: injury feedback).
	if health01 < low_state_threshold and (idx % 2) == 1:
		_step_depth_target *= 1.0 + limp_depth_extra
		_roll_vel += limp_roll_kick_deg * (1.0 - health01)
	if _player.input_active and _player.is_on_floor() and energy > min_step_energy:
		var strength: float = clampf(energy * _gait_amp_mult(), 0.0, 1.6)
		heel_strike.emit(strength, idx % 2)  # alternating feet, deterministic
		_strike_count += 1


func _detect_gait_start() -> void:
	var g: int = _player.gait
	if g != PlayerMovement.Gait.IDLE and _prev_gait == PlayerMovement.Gait.IDLE:
		if _time - _last_start_dip_time > start_dip_cooldown:
			_last_start_dip_time = _time
			var kick: float = start_dip_vel
			if g == PlayerMovement.Gait.SPRINT:
				kick *= 1.3
			_spring_vel.y -= kick
	_prev_gait = g


func _detect_landing() -> void:
	var grounded: bool = _player.is_on_floor()
	if grounded and not _was_grounded:
		var fs: float = _player.fall_speed_at_impact
		if fs > 1.5:
			var kv: float = fs * land_dip_scale
			var hard: float = 0.0
			if fs >= land_hard_threshold:
				hard = clampf((fs - land_hard_threshold) / 8.0, 0.0, 1.0)
				kv += land_hard_vel * hard
			_spring_vel.y -= kv
			_spring_vel.x += _rng.randf_range(-1.0, 1.0) * kv * 0.15
			_spring_vel.z += _rng.randf_range(-1.0, 1.0) * kv * 0.15
			if hard > 0.0:
				# "knees buckle": random sharp roll + FOV punch
				_roll_vel += _rng.randf_range(-land_roll_deg, land_roll_deg) * hard
				_fov_punch += kv * land_fov_punch
	_was_grounded = grounded


func _update_noise_suppress(delta: float) -> void:
	if noise_suppress > 0.0:
		noise_suppress = maxf(0.0, noise_suppress - suppress_decay_rate * delta)


func _compute_bob(delta: float) -> void:
	var amp_mult: float = _gait_amp_mult()
	var weight_amp: float = 1.0 + carry_weight * amp_per_weight
	var keep: float = 1.0 - noise_suppress
	var var_amt: float = 1.0 + step_variation * _noise_var.get_noise_1d(step_phase * var_noise_rate + 500.0)
	_step_depth = lerpf(_step_depth, _step_depth_target, 1.0 - exp(-8.0 * delta))
	var amp_scale: float = amp_mult * energy * weight_amp * keep * var_amt * _step_depth * _focus_mult * _daze_factor

	var vert_amp: float = vert_amp_walk * amp_scale * bob_intensity
	var lat_amp: float = lat_amp_walk * amp_scale * bob_intensity
	var surge_amp: float = surge_amp_walk * amp_scale * bob_intensity
	var roll_mult: float = roll_sprint_mult if _player.gait == PlayerMovement.Gait.SPRINT else 1.0
	var roll_amp: float = deg_to_rad(roll_amp_deg * roll_mult) * energy * keep * bob_intensity

	# --- Periodic gait backbone (rounded for handheld feel) ---------------------
	var jitter: float = _noise_jit.get_noise_1d(_time * 0.7) * timing_jitter_rad
	var theta: float = TAU * step_phase + jitter
	var v_gait: float = -(cos(theta) * (1.0 - dip_sharpness) + cos(2.0 * theta) * dip_sharpness)
	var l_gait: float = sin(theta * 0.5)
	var surge_gait: float = -sin(theta)
	var yaw_gait: float = -sin(theta)

	# --- Noise seasoning (thin organic layer) ------------------------------------
	var nv: float = _noise_vert.get_noise_1d(step_phase * noise_units_per_step)
	var nl: float = _noise_lat.get_noise_1d(step_phase * noise_units_per_step + 37.7)

	var raw_offset: Vector3 = Vector3(
		l_gait * lat_amp + nl * lat_amp * noise_mix,
		v_gait * vert_amp + nv * vert_amp * noise_mix,
		surge_gait * surge_amp
	)
	var raw_rot: Vector3 = Vector3(
		0.0,  # pitch comes from the counter-nod below, not the raw curve
		yaw_gait * deg_to_rad(yaw_amp_deg) * clampf(amp_scale, 0.0, 1.6),
		-l_gait * roll_amp
	)

	# --- FLESH FOLLOW-THROUGH (the handheld signature) ---------------------------
	# The raw gait signal passes through a lag stage; the output blends raw and
	# lagged, so every movement trails ~50-80 ms and overshoots slightly.
	var lag_k: float = 1.0 - exp(-flesh_lag_rate * delta)
	_bob_lagged_offset = _bob_lagged_offset.lerp(raw_offset, lag_k)
	_bob_lagged_rot = _bob_lagged_rot.lerp(raw_rot, lag_k)
	_bob_offset = raw_offset.lerp(_bob_lagged_offset, flesh_lag_mix)
	var rot_out: Vector3 = raw_rot.lerp(_bob_lagged_rot, flesh_lag_mix)

	# --- GAZE COUNTER-NOD (VHS stabilization reflex) -----------------------------
	# Pitch follows the LAGGED vertical: as the head dips, gaze rotates slightly
	# UP to keep the subject framed; as it rises, gaze settles back down.
	var pitch_from_dip: float = 0.0
	if vert_amp > 0.0005:
		pitch_from_dip = clampf(-_bob_lagged_offset.y / maxf(vert_amp, 0.0005), -1.5, 1.0)
	rot_out.x = pitch_from_dip * deg_to_rad(pitch_amp_deg) * (0.4 + 0.6 * energy) * keep

	# --- Always-alive handheld layers --------------------------------------------
	# Slow roll wander: the horizon is never perfectly level.
	rot_out.z += _noise_var.get_noise_1d(_time * 0.35 + 777.0) * deg_to_rad(roll_wander_deg)
	# Hand tremor: tiny ~7 Hz shimmer — mostly EXERTION (floor at idle is small).
	var trem_amt: float = deg_to_rad(hand_tremor_deg) * (tremor_idle_scale + energy) * keep
	if focus_mode == FocusMode.AIMING and (stamina < low_state_threshold or health01 < low_state_threshold):
		trem_amt *= aim_tremble_mult  # held-breath shiver when aiming exhausted/injured
	rot_out.x += _noise_trem.get_noise_1d(_time * hand_tremor_rate) * trem_amt
	rot_out.y += _noise_trem.get_noise_1d(_time * hand_tremor_rate + 91.7) * trem_amt
	_bob_rot = rot_out

	# --- Breathing: rate + depth climb with exertion (panting on sprint) ----------
	# ...and with exhaustion: low stamina = gasping heave (design doc).
	var gasp: float = 1.0 + (1.0 - stamina) * breath_gasping_mult
	_breath_phase += breath_rate * breath_time_scale * (1.0 + energy * breath_exertion_mult) * gasp * delta
	var b: float = _noise_breath.get_noise_1d(_breath_phase)
	var breath_amp_eff: float = breath_amp * (1.0 + energy * breath_exertion_mult * 0.6) * gasp
	_breath_offset = Vector3(0.0, b * breath_amp_eff, 0.0)
	_breath_rot = Vector3(0.0, 0.0, b * deg_to_rad(breath_roll_amp_deg))


func _integrate_spring(delta: float) -> void:
	_spring_acc = minf(_spring_acc + delta, 0.1)  # spiral-of-death guard
	while _spring_acc >= spring_max_dt:
		_step_spring(spring_max_dt)
		_spring_acc -= spring_max_dt
	if _spring_acc > 0.0:
		_step_spring(_spring_acc)
		_spring_acc = 0.0
	# Sanity clamp: no spring state survives this looking insane.
	if _spring_pos.length() > 0.5:
		_spring_pos = _spring_pos.normalized() * 0.5
		_spring_vel *= 0.5


func _step_spring(h: float) -> void:
	# Semi-implicit Euler (velocity first) — stable at any sane frame time.
	var accel: Vector3 = (-spring_stiffness * _spring_pos - spring_damping * _spring_vel) / _mass
	_spring_vel += accel * h
	_spring_pos += _spring_vel * h
	var racc: float = (-roll_stiffness * _roll_pos - roll_damping * _roll_vel) / _mass
	_roll_vel += racc * h
	_roll_pos += _roll_vel * h


func _update_inertia(delta: float) -> void:
	# Head-lag without fragile per-frame differentiation: compare raw velocity
	# against its own low-pass. Sudden starts/stops/impacts create a transient
	# deviation; the camera offsets OPPOSITE to it, then relaxes back.
	var pv: Vector3 = Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	var k: float = 1.0 - exp(-inertia_smooth_rate * delta)
	_pv_smoothed = _pv_smoothed.lerp(pv, k)
	var deviation: Vector3 = pv - _pv_smoothed

	var body_basis: Basis = _player.global_transform.basis
	var dx: float = deviation.dot(body_basis.x)     # rightward deviation
	var dz: float = deviation.dot(-body_basis.z)    # forward deviation

	var target: Vector3 = Vector3(-dx * inertia_scale, 0.0, dz * inertia_scale)
	_inertia_offset = _inertia_offset.lerp(target.limit_length(inertia_max), k)
	_inertia_pitch = lerpf(_inertia_pitch, clampf(dz * inertia_pitch_deg, -2.0, 2.0), k)
	_inertia_yaw = lerpf(_inertia_yaw, clampf(-dx * inertia_yaw_deg, -2.0, 2.0), k)


func _update_fov(delta: float) -> void:
	var sprint_target: float = 0.0
	if _player.is_sprinting:
		sprint_target = fov_sprint_add * energy
	_fov_sprint_smoothed = lerpf(_fov_sprint_smoothed, sprint_target, 1.0 - exp(-fov_sprint_rate * delta))
	_fov_punch *= exp(-fov_punch_decay * delta)
	_aim_zoom_smooth = lerpf(_aim_zoom_smooth, _aim_zoom_target, 1.0 - exp(-8.0 * delta))


## Called by WeaponSystem when aiming starts/stops.
func set_aim_zoom(on: bool) -> void:
	_aim_zoom_target = aim_fov if on else 0.0


func _apply_to_camera() -> void:
	var pos: Vector3 = _bob_offset + _breath_offset + _spring_pos + _inertia_offset
	pos = pos.limit_length(0.3)

	var roll_total: float = rad_to_deg(_bob_rot.z) + rad_to_deg(_breath_rot.z) + _roll_pos
	var rot: Vector3 = Vector3(
		clampf(_bob_rot.x + deg_to_rad(_inertia_pitch), deg_to_rad(-6.0), deg_to_rad(6.0)),
		clampf(_bob_rot.y + deg_to_rad(_inertia_yaw), deg_to_rad(-6.0), deg_to_rad(6.0)),
		clampf(deg_to_rad(roll_total), deg_to_rad(-15.0), deg_to_rad(15.0))
	)

	# --- Retro quantization (Phase 5): the doc's "snap filter" ---------------
	# Offsets round to render-scale steps so organic movement locks to the
	# retro pixel grid instead of shimmering at sub-pixel precision.
	# During impacts the grid COARSENS with noise_suppress -> the jagged,
	# digital "pixel-clamped" jolt the design doc asks for ("the camera steps
	# across the screen in jagged, distinct pixel increments").
	if snap_enabled:
		var coarsen: float = 1.0 + snap_impact_mult * noise_suppress
		var p_step: float = snap_position_step * coarsen
		var r_step: float = deg_to_rad(snap_rotation_step_deg * coarsen)
		if p_step > 0.0:
			pos = pos.snapped(Vector3(p_step, p_step, p_step))
		if r_step > 0.0:
			rot = rot.snapped(Vector3(r_step, r_step, r_step))

	position = pos
	rotation = rot

	# "Breathing lens": FOV opens a touch as the camera dips under a step.
	# Gain-based (deg per meter): pulse auto-scales with real dip depth.
	var focal: float = clampf(-pos.y * fov_bob_gain, -2.5, 2.5)
	fov = clampf(base_fov + _fov_sprint_smoothed + _fov_punch + focal + _aim_zoom_smooth, 40.0, 110.0)


func _update_focus(delta: float) -> void:
	var target: float = 1.0
	match focus_mode:
		FocusMode.INVENTORY:
			target = focus_gait_mult_inventory
		FocusMode.AIMING:
			target = focus_gait_mult_aiming
	_focus_mult = lerpf(_focus_mult, target, 1.0 - exp(-focus_blend_rate * delta))


func _on_inventory_toggled(is_open: bool) -> void:
	set_focus_mode(FocusMode.INVENTORY if is_open else FocusMode.EXPLORING)


func _update_daze(delta: float) -> void:
	if _daze_timer > 0.0:
		_daze_timer = maxf(0.0, _daze_timer - delta)
	var target: float = daze_mass_mult if _daze_timer > 0.0 else 1.0
	_daze_factor = lerpf(_daze_factor, target, 1.0 - exp(-4.0 * delta))


## The production damage entry point. Enemies/traps/falling debris will emit
## Events.player_damaged(amount, direction_from) — nothing should ever call
## apply_impulse() directly from gameplay code.
func _on_player_damaged(amount: float, direction: Vector3) -> void:
	if _dead:
		return   # corpse ignores damage: no shake, no sound-repeat, no deeper health hole
	apply_impulse(direction, amount * damage_impulse_scale)
	# Real damage -> real health: 25 damage = -0.25 health. Three arrow hits
	# and the limp takes over; medkits (inventory USE) heal it back.
	set_health(health01 - amount * 0.01)
	if amount >= daze_threshold:
		_daze_timer = daze_duration


# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

func _make_noise(seed_value: int, freq: float) -> FastNoiseLite:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_NONE  # single smooth scale: no micro-ripples
	n.seed = seed_value
	n.frequency = freq
	return n


func _current_step_rate() -> float:
	match _player.gait:
		PlayerMovement.Gait.SPRINT:
			return sprint_step_rate
		PlayerMovement.Gait.CROUCH:
			return crouch_step_rate
		_:
			return walk_step_rate


func _gait_amp_mult() -> float:
	match _player.gait:
		PlayerMovement.Gait.SPRINT:
			return vert_amp_sprint_mult
		PlayerMovement.Gait.CROUCH:
			return vert_amp_crouch_mult
		_:
			return 1.0


func _gait_name() -> String:
	match _player.gait:
		PlayerMovement.Gait.SPRINT:
			return "SPRINT"
		PlayerMovement.Gait.CROUCH:
			return "CROUCH"
		PlayerMovement.Gait.WALK:
			return "WALK"
		_:
			return "IDLE"


func _build_debug_overlay() -> void:
	_debug_layer = CanvasLayer.new()
	_debug_layer.layer = 100
	add_child(_debug_layer)
	_debug_label = Label.new()
	_debug_label.position = Vector2(12, 12)
	_debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_label.add_theme_font_size_override("font_size", debug_font_size)
	_debug_label.add_theme_color_override("font_color", Color(0.85, 0.95, 0.75))
	_debug_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_debug_label.add_theme_constant_override("outline_size", 4)
	_debug_layer.add_child(_debug_label)


func _update_debug(delta: float) -> void:
	if _debug_label == null or not _debug_label.visible:
		return
	_debug_timer -= delta
	if _debug_timer > 0.0:
		return
	_debug_timer = 0.1
	_debug_label.text = "energy %.2f | gait %s | step %.2f (%.2f/s) | depth %.2f\nspring |p| %.3f  roll %.1f deg  mass %.2f  daze %.1f\nstrikes %d | fov %.1f | suppress %.2f\n[H] rnd hit  [arrows] L/R/F/B hit  [F3] hide" % [
		energy, _gait_name(), step_phase, step_rate, _step_depth,
		_spring_pos.length(), _roll_pos, _mass, _daze_timer,
		_strike_count, fov, noise_suppress,
	]


func _unhandled_input(event: InputEvent) -> void:
	# Debug-only helpers. Guarded so a missing action can never spam errors.
	# Every test hit goes through Events.player_damaged — the exact path real
	# enemies will use — so impulse + daze + UI jolt are tested end-to-end.
	if InputMap.has_action("debug_impulse") and event.is_action_pressed("debug_impulse"):
		var ang: float = _rng.randf_range(0.0, TAU)
		var dir: Vector3 = _player.global_transform.basis * Vector3(cos(ang), 0.0, sin(ang))
		Events.player_damaged.emit(_rng.randf_range(15.0, 35.0), dir)
	elif InputMap.has_action("debug_hit_left") and event.is_action_pressed("debug_hit_left"):
		_debug_hit(-1.0, 0.0)
	elif InputMap.has_action("debug_hit_right") and event.is_action_pressed("debug_hit_right"):
		_debug_hit(1.0, 0.0)
	elif InputMap.has_action("debug_hit_front") and event.is_action_pressed("debug_hit_front"):
		_debug_hit(0.0, 1.0)
	elif InputMap.has_action("debug_hit_back") and event.is_action_pressed("debug_hit_back"):
		_debug_hit(0.0, -1.0)
	if InputMap.has_action("debug_overlay") and event.is_action_pressed("debug_overlay"):
		if _debug_label != null:
			_debug_label.visible = not _debug_label.visible


## side: -1 = blow from the left, +1 = from the right.
## fwd:  +1 = blow from the front,  -1 = from behind.
func _debug_hit(side: float, fwd: float) -> void:
	var body_basis: Basis = _player.global_transform.basis
	var dir: Vector3 = (body_basis.x * side - body_basis.z * fwd).normalized()
	Events.player_damaged.emit(debug_hit_amount, dir)
