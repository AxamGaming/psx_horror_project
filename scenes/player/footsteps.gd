extends AudioStreamPlayer
## ============================================================================
## FOOTSTEPS — Phase 8 FINAL.
##
## Plain AudioStreamPlayer (the only player type proven audible everywhere in
## this project) + per-foot PAN BUSSES (FootL/FootR, AudioEffectPanner on the
## bus, sending into SFX so deafness + room reverb still apply).
##   - No AudioStreamPlayer3D (unreliable in SubViewports, godot#94403).
##   - No AudioStreamPlayer2D (proved silent in this setup; 4.7 playtest).
##   - No `pan` property (does not exist on plain players in 4.7).
## Bus existence is guaranteed by AudioMgr at boot; if a foot bus is somehow
## missing we fall back to SFX — silent footsteps are structurally impossible.
## Streams are silence-trimmed WAVs (sample-exact against heel_strike).
## ============================================================================

@export var pitch_base: float = 1.0
@export var pitch_weight_drop: float = 0.2   # full carry weight -> -20% pitch (heavier thud)
@export var pitch_jitter: float = 0.04
@export var volume_base: float = -6.0
@export var volume_strength_scale: float = 5.0

var _rig: CameraRig
var _streams: Array[AudioStream] = []        # concrete takes
var _streams_wood: Array[AudioStream] = []   # wood takes (surface-tagged zones)
var _bus_l: StringName = &"SFX"
var _bus_r: StringName = &"SFX"


func _ready() -> void:
	for path in [
		"res://audio/sfx/footstep_concrete_01.wav",
		"res://audio/sfx/footstep_concrete_02.wav",
	]:
		var s: AudioStream = load(path) as AudioStream
		if s != null:
			_streams.append(s)
	for path in [
		"res://audio/sfx/footstep_wood_01.wav",
		"res://audio/sfx/footstep_wood_02.wav",
	]:
		var s: AudioStream = load(path) as AudioStream
		if s != null:
			_streams_wood.append(s)
	assert(not _streams.is_empty(), "Footsteps: no footstep streams found in audio/sfx/.")
	if AudioServer.get_bus_index(&"FootL") >= 0:
		_bus_l = &"FootL"
	if AudioServer.get_bus_index(&"FootR") >= 0:
		_bus_r = &"FootR"
	_rig = get_node("../HeadPivot/MainCamera") as CameraRig
	assert(_rig != null, "Footsteps: CameraRig not found at ../HeadPivot/MainCamera.")
	_rig.heel_strike.connect(_on_heel_strike)


func _on_heel_strike(strength: float, foot: int) -> void:
	# Surface-tagged sets (design doc Phase 9): ray straight down from the
	# body; colliders in group "surface_wood" switch the take pool.
	var pool: Array[AudioStream] = _streams
	if not _streams_wood.is_empty() and _is_wood_below():
		pool = _streams_wood
	stream = pool[randi() % pool.size()]   # natural take variation
	# Inventory-weight pitch shifting (design doc): loaded = deeper, bassier.
	# Left/right foot get slight pitch character + opposite pan buses.
	var foot_pitch: float = 1.0 if foot == 0 else 0.96
	pitch_scale = (pitch_base - _rig.carry_weight * pitch_weight_drop) * foot_pitch + randf_range(-pitch_jitter, pitch_jitter)
	volume_db = volume_base + strength * volume_strength_scale
	bus = _bus_l if foot == 0 else _bus_r
	play()


func _is_wood_below() -> bool:
	var player: Node = _rig.get_parent().get_parent() if _rig.get_parent() != null else null
	if player == null:
		return false
	var world: World3D = player.get_world_3d()
	if world == null:
		return false
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	if space == null:
		return false
	var from: Vector3 = player.global_position + Vector3(0.0, 0.1, 0.0)
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, from - Vector3(0.0, 0.8, 0.0))
	q.exclude = [player.get_rid()]
	var r: Dictionary = space.intersect_ray(q)
	if r.is_empty():
		return false
	var collider: Node = r.get("collider") as Node
	return collider != null and collider.is_in_group("surface_wood")
