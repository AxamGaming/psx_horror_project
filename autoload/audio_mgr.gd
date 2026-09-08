extends Node
## ============================================================================
## AUDIO MANAGER (autoload, after Events) — Phase 8 FINAL architecture.
##
## HARD-WON RULES (four playtest rounds, all verified against 4.7 docs):
##   1. ONLY plain AudioStreamPlayer is used for playback. AudioStreamPlayer3D
##      is unreliable inside SubViewports (godot#94403) and AudioStreamPlayer2D
##      proved silent in this setup too; plain players are proven audible both
##      at the root viewport and inside the retro SubViewport (the flashlight
##      click never failed once).
##   2. Panning = per-bus AudioEffectPanner (4.7 class: single `pan` property,
##      -1..1). Buses: FootL/FootR (fixed), Hum (dynamic), World0-3 (pooled).
##      All send into SFX so deafness + room reverb still apply to them.
##   3. SELF-HEALING: every bus this manager needs is guaranteed to exist at
##      boot (_ensure_pan_bus creates missing ones). A stale/missing layout
##      file can never silently kill audio again.
##   4. One-shots are silence-trimmed WAVs: compressed formats carry decoder
##      priming padding that made sounds land late against gameplay events.
##
## Graph:
##   Master <- SFX      <- [0] LowPass "Deafness" + [1] Reverb "Room"
##          <- Ambient  <- [0] LowPass "Deafness" + [1] Reverb "Room"
##          <- tinnitus (direct: internal ring must never be muffled)
##   SFX    <- FootL/FootR/Hum/World0-3 <- [0] AudioEffectPanner
## ============================================================================

@export_group("Impact deafness")
@export var deaf_threshold: float = 12.0
@export var deaf_cutoff_hit: float = 400.0
@export var deaf_cutoff_normal: float = 20000.0
@export var deaf_recovery: float = 2.0
@export var tinnitus_peak_db: float = -10.0
@export var tinnitus_decay: float = 2.5
@export var impact_volume_base: float = -14.0
@export var impact_volume_per_damage: float = 0.4

@export_group("2.5D panning (bus panners)")
@export_range(0.0, 1.0) var foot_pan: float = 0.35        # FootL = -this, FootR = +this
@export_range(0.0, 1.0) var world_pan_amount: float = 0.8 # full-left/right for world sounds
@export var world_atten_db_per_meter: float = 1.2

@export_group("Reverb probe")
@export var probe_rate: float = 10.0
@export var probe_range: float = 12.0
@export var reverb_wet_min: float = 0.06
@export var reverb_wet_max: float = 0.35

var _lp_sfx: AudioEffectLowPassFilter
var _lp_amb: AudioEffectLowPassFilter
var _rev_sfx: AudioEffectReverb
var _rev_amb: AudioEffectReverb
var _pan_worlds: Array[AudioEffectPanner] = []
var stream_door_creak: AudioStream
var _stream_thud: AudioStream
var _tinnitus: AudioStreamPlayer
var _thud: AudioStreamPlayer
var _impact: AudioStreamPlayer
var _world_players: Array[AudioStreamPlayer] = []
var _deaf_t: float = 0.0
var _tinn_t: float = 0.0
var _probe_acc: float = 0.0
var _room_smooth: float = 0.5
var _dead: bool = false


func _ready() -> void:
	_resolve_buses()
	_ensure_pan_buses()
	_make_players()
	_make_world_pool()
	Events.player_damaged.connect(_on_damaged)
	Events.hard_landed.connect(_on_hard_landed)
	Events.wall_hit.connect(_on_wall_hit)
	Events.player_died.connect(_on_player_died)
	Events.player_respawned.connect(_on_player_respawned)


## World-sound pool players live in the camera's viewport so panning/position
## math stays viewport-correct.
func ensure_pan_bus(bus_name: String) -> AudioEffectPanner:
	## Creates (once) a bus with an AudioEffectPanner sending into SFX, so any
	## plain AudioStreamPlayer can be panned at runtime (plain players have
	## no `pan` property — panning lives in AudioEffectPanner).
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, &"SFX")
		var fx: AudioEffectPanner = AudioEffectPanner.new()
		AudioServer.add_bus_effect(idx, fx)
		return fx
	var fx2: AudioEffectPanner = AudioServer.get_bus_effect(idx, 0) as AudioEffectPanner
	if fx2 == null:
		fx2 = AudioEffectPanner.new()
		AudioServer.add_bus_effect(idx, fx2, 0)
	return fx2


func _on_player_died() -> void:
	_dead = true


## Respawn = clean audio slate: everything mid-play stops, no ghost loops.
func _on_player_respawned() -> void:
	_dead = false
	_tinnitus.stop()
	_thud.stop()
	_impact.stop()
	for p in _world_players:
		p.stop()


# ------------------------------------------------------------------------------
# Bus resolution / self-healing
# ------------------------------------------------------------------------------

## Buses live in default_bus_layout.tres (editor-visible). Effect ORDER is a
## contract: [0] = deafness low-pass, [1] = room reverb on SFX/Ambient.
## If the layout ever fails to load, rebuild the core graph at runtime.
func _resolve_buses() -> void:
	var sfx: int = AudioServer.get_bus_index(&"SFX")
	var amb: int = AudioServer.get_bus_index(&"Ambient")
	if sfx < 0 or amb < 0:
		push_warning("AudioMgr: bus layout not loaded — building core buses at runtime.")
		_build_buses()
		return
	_lp_sfx = AudioServer.get_bus_effect(sfx, 0) as AudioEffectLowPassFilter
	_rev_sfx = AudioServer.get_bus_effect(sfx, 1) as AudioEffectReverb
	_lp_amb = AudioServer.get_bus_effect(amb, 0) as AudioEffectLowPassFilter
	_rev_amb = AudioServer.get_bus_effect(amb, 1) as AudioEffectReverb
	if _lp_sfx == null or _rev_sfx == null or _lp_amb == null or _rev_amb == null:
		push_warning("AudioMgr: core bus effects missing — rebuilding.")
		_build_buses()


func _build_buses() -> void:
	_lp_sfx = _add_bus_with_fx("SFX")
	_lp_amb = _add_bus_with_fx("Ambient")


func _add_bus_with_fx(bus_name: String) -> AudioEffectLowPassFilter:
	AudioServer.add_bus()
	var idx: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, &"Master")
	var lp: AudioEffectLowPassFilter = AudioEffectLowPassFilter.new()
	lp.cutoff_hz = deaf_cutoff_normal
	AudioServer.add_bus_effect(idx, lp)
	var rv: AudioEffectReverb = AudioEffectReverb.new()
	rv.wet = 0.15
	rv.room_size = 0.5
	AudioServer.add_bus_effect(idx, rv)
	if bus_name == "SFX":
		_rev_sfx = rv
	else:
		_rev_amb = rv
	return lp


## Guarantees a send-to-SFX bus with an AudioEffectPanner at slot 0 exists.
## Creates it if the layout file didn't provide it (stale copy protection).
func _ensure_pan_bus(bus_name: String, default_pan: float) -> AudioEffectPanner:
	var idx: int = AudioServer.get_bus_index(bus_name)  # String converts to StringName implicitly
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, &"SFX")
		var p: AudioEffectPanner = AudioEffectPanner.new()
		p.pan = default_pan
		AudioServer.add_bus_effect(idx, p)
		return p
	var e: AudioEffectPanner = AudioServer.get_bus_effect(idx, 0) as AudioEffectPanner
	if e == null:
		e = AudioEffectPanner.new()
		e.pan = default_pan
		AudioServer.add_bus_effect(idx, e, 0)
	return e


func _ensure_pan_buses() -> void:
	# Exports win over layout-file defaults, so tuning works either way.
	_ensure_pan_bus("FootL", -foot_pan).pan = -foot_pan
	_ensure_pan_bus("FootR", foot_pan).pan = foot_pan
	_pan_worlds.clear()
	for i in range(4):
		_pan_worlds.append(_ensure_pan_bus("World" + str(i), 0.0))


# ------------------------------------------------------------------------------
# Players
# ------------------------------------------------------------------------------

func _make_players() -> void:
	_tinnitus = AudioStreamPlayer.new()
	var ts: AudioStream = load("res://audio/sfx/tinnitus.wav") as AudioStream
	var tw: AudioStreamWAV = ts as AudioStreamWAV
	if tw != null:
		tw.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_tinnitus.stream = ts
	_tinnitus.bus = &"Master"   # internal ring: never muffled by world low-pass
	_tinnitus.volume_db = -80.0
	add_child(_tinnitus)

	_thud = AudioStreamPlayer.new()
	_stream_thud = load("res://audio/sfx/land_heavy.wav") as AudioStream
	_thud.stream = _stream_thud
	_thud.bus = &"SFX"
	add_child(_thud)

	stream_door_creak = load("res://audio/sfx/door_creak.wav") as AudioStream

	_impact = AudioStreamPlayer.new()
	_impact.stream = load("res://audio/sfx/hit_impact.wav") as AudioStream
	_impact.bus = &"SFX"
	add_child(_impact)


func _make_world_pool() -> void:
	for i in range(4):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.bus = StringName("World" + str(i))   # & operator is literals-only; convert explicitly
		add_child(p)
		_world_players.append(p)


# ------------------------------------------------------------------------------
# Event reactions
# ------------------------------------------------------------------------------

func _on_damaged(amount: float, _direction: Vector3) -> void:
	if _dead:
		return
	# The blow itself: meaty thwack, loudness follows damage. Its tail gets
	# caught by the deafness low-pass slamming down right after — exactly the
	# "hit echoes, then the world goes underwater" beat from the design doc.
	if _impact != null:
		_impact.volume_db = clampf(impact_volume_base + amount * impact_volume_per_damage, impact_volume_base, 0.0)
		_impact.pitch_scale = randf_range(0.9, 1.15)
		_impact.play()
	if amount >= deaf_threshold:
		_deaf_t = deaf_recovery
		_tinn_t = tinnitus_decay
		_tinnitus.volume_db = tinnitus_peak_db
		if not _tinnitus.playing:
			_tinnitus.play()


func _on_hard_landed(energy: float) -> void:
	if energy > 0.05:
		_thud.volume_db = -14.0 + energy * 12.0
		_thud.pitch_scale = randf_range(0.9, 1.1)
		_thud.play()


## 2.5D spatialized one-shot for WORLD sounds (door creaks, creature noises,
## pickups...): pan via the slot bus's panner, volume via distance attenuation.
## Plain player + bus panner = no viewport/listener dependencies at all.
func play_world_sound(stream: AudioStream, world_pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if stream == null or _world_players.is_empty():
		return
	var pan_dir: float = 0.0
	var vol: float = volume_db
	var cam: Camera3D = Events.main_camera
	if cam != null and is_instance_valid(cam):
		var rel: Vector3 = world_pos - cam.global_position
		var dist: float = rel.length()
		var dir: Vector3 = rel / maxf(dist, 0.001)
		var b: Basis = cam.global_transform.basis
		pan_dir = clampf(dir.dot(b.x), -1.0, 1.0)
		vol -= clampf(dist - 1.0, 0.0, 40.0) * world_atten_db_per_meter
	var slot: int = 0
	for i in range(_world_players.size()):
		if not _world_players[i].playing:
			slot = i
			break
	if slot < _pan_worlds.size():
		_pan_worlds[slot].pan = pan_dir * world_pan_amount
	var p: AudioStreamPlayer = _world_players[slot]
	p.stream = stream
	p.volume_db = vol
	p.pitch_scale = pitch
	p.play()


## Wall/body-slam thud: positional, pitched down for mass.
func _on_wall_hit(hit_position: Vector3, strength: float) -> void:
	if _dead:
		return
	play_world_sound(_stream_thud, hit_position, -12.0 + strength * 10.0, 0.75)


# ------------------------------------------------------------------------------
# Per-frame: deafness recovery, tinnitus fade, reverb probe
# ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	# --- deafness recovery: fast slam (set on hit), slow quadratic re-open ---
	var cutoff: float = deaf_cutoff_normal
	if _deaf_t > 0.0:
		_deaf_t = maxf(0.0, _deaf_t - delta)
		var k: float = _deaf_t / deaf_recovery
		cutoff = lerpf(deaf_cutoff_normal, deaf_cutoff_hit, k * k)
	if _lp_sfx != null:
		_lp_sfx.cutoff_hz = cutoff
	if _lp_amb != null:
		_lp_amb.cutoff_hz = cutoff

	# --- tinnitus fade ---
	if _tinn_t > 0.0:
		_tinn_t = maxf(0.0, _tinn_t - delta)
		_tinnitus.volume_db = lerpf(-80.0, tinnitus_peak_db, _tinn_t / tinnitus_decay)
	elif _tinnitus.playing:
		_tinnitus.stop()

	# --- reverb probe ---
	_probe_acc += delta
	if _probe_acc >= 1.0 / probe_rate:
		_probe_acc = 0.0
		_update_probe()


func _update_probe() -> void:
	var cam: Camera3D = Events.main_camera
	if cam == null or not is_instance_valid(cam):
		return
	var world: World3D = cam.get_world_3d()
	if world == null:
		return
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	if space == null:
		return

	var basis: Basis = cam.global_transform.basis
	var dirs: Array[Vector3] = [
		basis.y, -basis.y, basis.x, -basis.x, -basis.z, basis.z,
	]
	# The camera sits INSIDE the player capsule — without excluding it every
	# ray would hit our own body and the room would read "coffin".
	var excl: Array[RID] = []
	var body_node: Node = cam.get_parent().get_parent() if cam.get_parent() != null else null
	if body_node != null:
		excl.append(body_node.get_rid())
	var total: float = 0.0
	for d in dirs:
		var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			cam.global_position, cam.global_position + d * probe_range
		)
		q.exclude = excl
		var r: Dictionary = space.intersect_ray(q)
		if r.is_empty():
			total += probe_range
		else:
			var hit_pos: Vector3 = r["position"] as Vector3
			total += cam.global_position.distance_to(hit_pos)
	var avg: float = total / float(dirs.size())
	var room: float = clampf(avg / probe_range, 0.0, 1.0)
	_room_smooth = lerpf(_room_smooth, room, 0.25)

	var wet: float = lerpf(reverb_wet_min, reverb_wet_max, _room_smooth)
	var size: float = lerpf(0.2, 0.9, _room_smooth)
	for rv in [_rev_sfx, _rev_amb]:
		var rev: AudioEffectReverb = rv as AudioEffectReverb
		if rev != null:
			rev.wet = wet
			rev.room_size = size
			rev.damping = lerpf(0.9, 0.4, _room_smooth)
