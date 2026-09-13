extends Node
class_name CreatureAwareness
## ============================================================================
## CREATURE AWARENESS — persistent perception controller.
##
## Owns all three sensors (vision, hearing, proximity) plus the last-seen
## memory that bridges "I see you" → "I saw you 1.2 s ago" → "I lost you."
## LimboAI tasks query this node; they do NOT query NightmareCreature directly
## for perception, so perception and decision-making are fully decoupled.
##
## Architecture:
##   NightmareCreature._physics_process  →  awareness.tick(delta)
##   CondSeesPlayer                      →  awareness.confirmed()
##   CondHearsPlayer                     →  awareness.heard()
##   ActChase                            →  awareness.last_known_pos()
##   ActInvestigate                      →  awareness.last_known_pos()
## ============================================================================

## How long since last sighting before memory expires.
const MEMORY_TIMEOUT := 10.0
## How many consecutive LOS samples must succeed to confirm a sighting.
## Keeps the creature from reacting to half-frame glimpses around corners.
const CONFIRM_TIME := 0.4
## How long a combat lock holds after LOS is lost (honest commitment).
const COMBAT_LOCK := 3.0

# ── Wired by NightmareCreature._ready() ──────────────────────────────────────
var _creature: NightmareCreature = null
var _player: PlayerMovement = null

# ── Vision state ─────────────────────────────────────────────────────────────
var _see_t: float = 0.0        # time currently seeing the player
var _lock_t: float = 0.0       # combat-commitment lock countdown
var _confirmed: bool = false   # true when _see_t > CONFIRM_TIME

# ── Memory ───────────────────────────────────────────────────────────────────
var _last_known: Vector3 = Vector3.ZERO
var _has_memory: bool = false
var _memory_t: float = 0.0    # time since last update; expires at MEMORY_TIMEOUT

# ── Aggregate flags (polled by BT tasks) ─────────────────────────────────────
var _confirmed_visible: bool = false
var _heard: bool = false
var _heard_quietly: bool = false   # true only when heard via the QUIET tier
var _proximity: bool = false


func setup(creature: NightmareCreature) -> void:
	_creature = creature
	_player = _creature.get_tree().get_first_node_in_group("player") as PlayerMovement


## Called once per physics frame by NightmareCreature.
func tick(delta: float) -> void:
	if _player == null:
		_player = _creature.get_tree().get_first_node_in_group("player") as PlayerMovement
	if _creature == null or _player == null:
		return
	if _creature.is_amnesiac():
		_reset_sensors()
		# R16: the post-recover daze dulls the far senses, but something
		# pressing against its face still startles it out of the fog — the
		# old behaviour ignored the player for 5 s at point-blank range
		# ("it just walks past me and does nothing").
		if _creature.dist_to_player() < _creature.proximity_range * 0.75 \
				and _point_blank_los():
			_creature.startle()
			_remember(_player.global_position)
		return

	# ── Vision ───────────────────────────────────────────────────────────────
	var raw_see: bool = _raw_vision_check()
	if _creature.dist_to_player() < _creature.proximity_range:
		# Point-blank: skip FOV, still require LOS (walls still block).
		if _point_blank_los():
			_see_t = CONFIRM_TIME + 1.0
		else:
			_see_t = maxf(0.0, _see_t - delta)
	elif raw_see:
		_see_t = minf(CONFIRM_TIME + 0.5, _see_t + delta)
	else:
		_see_t = maxf(0.0, _see_t - delta)

	if _see_t > CONFIRM_TIME:
		_lock_t = COMBAT_LOCK
		_confirmed = true
		_confirmed_visible = true
		_creature.note_combat_start()
		_remember(_player.global_position)
	else:
		_confirmed = false
		_lock_t = maxf(0.0, _lock_t - delta)
		_confirmed_visible = _lock_t > 0.0

	# ── Hearing ──────────────────────────────────────────────────────────────
	_heard = _hearing_check()
	if _heard:
		_remember(_player.global_position)

	# ── Proximity (wake / blind-spot coverage) ───────────────────────────────
	_proximity = _creature.dist_to_player() < _creature.proximity_range

	# ── Memory decay ─────────────────────────────────────────────────────────
	if _has_memory and not _confirmed_visible and not _heard:
		_memory_t += delta
		if _memory_t >= MEMORY_TIMEOUT:
			_has_memory = false
			_memory_t = 0.0


# ── Public query API (for BT tasks) ──────────────────────────────────────────

## True when player is visually confirmed or within the combat-lock window.
func confirmed() -> bool:
	return _confirmed_visible

## True when the creature can hear the player this frame.
func heard() -> bool:
	return _heard

## True when the CURRENT hearing is via the quiet tier only (idle/crouch
## rustle inside crouch_hear_range). False for loud-tier hearing (walk/sprint)
## and whenever nothing is heard. Lets BT/UI distinguish "faint rustle — go
## look" from "footsteps — hunt". See docs/NOISE_METER.md §3.
func heard_quietly() -> bool:
	return _heard_quietly

## True when the player is within point-blank proximity_range.
func proximity() -> bool:
	return _proximity

## True when any sensor has recently registered the player.
func has_memory() -> bool:
	return _has_memory

## Last position any sensor placed the player.
func last_known_pos() -> Vector3:
	return _last_known

## Force-stamp a position (gunshot, etc.) without requiring sensor confirmation.
func stamp_position(pos: Vector3) -> void:
	_remember(pos)

## Clear all state — post-recover amnesia wipe.
func reset() -> void:
	_reset_sensors()
	_has_memory = false
	_memory_t = 0.0


# ── Internal ─────────────────────────────────────────────────────────────────

func _reset_sensors() -> void:
	_see_t = 0.0
	_lock_t = 0.0
	_confirmed = false
	_confirmed_visible = false
	_heard = false
	_heard_quietly = false
	_proximity = false


func _remember(pos: Vector3) -> void:
	_last_known = pos
	_has_memory = true
	_memory_t = 0.0


## Full vision check: distance → FOV → multi-sample LOS.
## Four rays from slightly different eye origins defeat doorway slivers and
## corner clipping — the single-ray R22 check produced the "looking away but
## suddenly chases" symptom whenever the one ray grazed a doorway gap.
func _raw_vision_check() -> bool:
	if _creature == null or _player == null:
		return false
	var to_p: Vector3 = _player.global_position - _creature.global_position
	var dist_2d: float = Vector2(to_p.x, to_p.z).length()
	if dist_2d > _creature.sight_range:
		return false

	# Forward is the CharacterBody3D's own -Z. The model's orientation is
	# corrected by ModelRoot (rotation offset node), so AI forward == body -Z.
	var fwd: Vector3 = -_creature.global_transform.basis.z
	fwd.y = 0.0
	var flat: Vector3 = to_p
	flat.y = 0.0
	if fwd.length_squared() < 0.0001 or flat.length_squared() < 0.0001:
		return false
	if rad_to_deg(fwd.normalized().angle_to(flat.normalized())) > _creature.sight_fov_deg * 0.5:
		return false

	return _multi_los()


## Point-blank check: no FOV required, just LOS.
func _point_blank_los() -> bool:
	return _multi_los()


## Fire four rays from slightly different origins. Success on the first clear
## ray — "any part of you visible" semantics, not "all of you visible".
func _multi_los() -> bool:
	var world: World3D = _creature.get_world_3d()
	if world == null or world.direct_space_state == null:
		return true
	var target: Vector3 = _player.global_position + Vector3(0.0, 1.0, 0.0)
	# Four eye origins: centre, slight left, slight right, slightly higher.
	# This defeats single-ray misses caused by narrow doorways and pillar corners.
	var origins: Array[Vector3] = [
		_creature.global_position + Vector3(0.0, 1.5, 0.0),
		_creature.global_position + Vector3(0.2, 1.5, 0.0),
		_creature.global_position + Vector3(-0.2, 1.5, 0.0),
		_creature.global_position + Vector3(0.0, 1.75, 0.0),
	]
	for origin in origins:
		var q := PhysicsRayQueryParameters3D.create(origin, target)
		q.exclude = [_creature.get_rid()]
		q.collision_mask = 17   # world + doors; player layer excluded
		if world.direct_space_state.intersect_ray(q).is_empty():
			return true
	return false


## Two-tier hearing (docs/NOISE_METER.md §3):
##
##   LOUD tier  (noise > hear_noise_floor): audible radius scales with
##              loudness — hear_radius * noise. Walk heard at half range,
##              sprint at full range.
##   QUIET tier (idle / crouch-walk): point-blank only — inside
##              crouch_hear_range metres. Set crouch_hear_range = 0.0 to
##              disable the quiet tier entirely.
##
## Setting hear_noise_floor = 0.05 restores the legacy single-tier behaviour
## (crouch-walk faintly audible inside hear_radius * 0.15 ≈ 2.4 m).
func _hearing_check() -> bool:
	if _creature == null or _player == null:
		_heard_quietly = false
		return false
	var noise: float = _player.noise_level
	var dist: float = _creature.dist_to_player()
	if noise > _creature.hear_noise_floor:
		# LOUD tier — never reported as a quiet rustle.
		_heard_quietly = false
		return dist < _creature.hear_radius * noise
	# QUIET tier — faint rustle, point-blank only.
	_heard_quietly = dist < _creature.crouch_hear_range
	return _heard_quietly
