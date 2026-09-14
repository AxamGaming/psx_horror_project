extends Node
class_name SurvivalSystem
## ============================================================================
## SURVIVAL SYSTEM — Phase 11. Stamina drain/recovery + death/respawn.
##
## Mutates rig.stamina DIRECTLY (no private mirror), so the debug panel
## sliders keep working: set a value and the system continues from it.
## Sprinting drains; aiming (held breath) drains slower; recovery starts
## after recover_delay. At ~0 stamina, movement.exhausted gates sprinting
## (the doc's "stamina fully depleted" state) and the rig's gasping/tremble
## react to the value as built in Phase 6/8.
##
## Death: health <= 0 -> Events.player_died (overlay + gates); respawn via
## Events.respawn_requested (death overlay's R key) -> full reset to spawn.
## ============================================================================

@export var sprint_drain_per_sec: float = 0.14   # ~7 s of full sprint from full
@export var aim_drain_per_sec: float = 0.05      # holding your breath costs
@export var recover_per_sec: float = 0.09        # ~11 s back to full
@export var recover_delay: float = 1.5           # pause after exertion

var _player: PlayerMovement
var _rig: CameraRig
var _recover_timer: float = 0.0
var _dead: bool = false
## R26: who landed the last damaging blow. CREATURE routes the death through
## the kill sequence; NONE (environmental/unknown) keeps the classic death
## screen. R32: was a String ("creature" / "") — now an enum so the routing
## check cannot drift into a typo. Reset on respawn so a later fall doesn't
## inherit an old tag.
enum DamageSource { NONE, CREATURE }
var last_damage_source: DamageSource = DamageSource.NONE
## R29: when the tag was stamped (Time ticks, msec). A tag only routes the
## death while it is FRESH — a swipe you survived minutes ago must not turn a
## later fall death into a creature jumpscare (the kill cam would weld to a
## creature that may be across the map). The lethal blow lands within frames
## of its tag, so the window only needs to cover that + death-check latency.
var last_damage_stamp_ms: int = 0
## R30: world-space direction the last damaging blow was travelling (for a
## creature hit: creature -> player). The KillDirector whips the camera toward
## the blow from this, so a hit from the left reads as a hit from the LEFT.
var last_damage_direction: Vector3 = Vector3.ZERO
## How long a damage-source tag stays authoritative for death routing.
@export var kill_source_window: float = 2.0
var _spawn: Vector3


func _ready() -> void:
	_player = get_parent() as PlayerMovement
	assert(_player != null, "SurvivalSystem must be a child of the Player body.")
	_rig = Events.main_camera as CameraRig
	_spawn = _player.global_position
	Events.respawn_requested.connect(_on_respawn_requested)
	Events.player_damaged.connect(_on_player_damaged)


func _process(delta: float) -> void:
	if _rig == null or _player == null:
		return
	if _dead:
		return

	var draining := false
	if _player.is_sprinting and _player.planar_speed > 0.5:
		_rig.stamina = maxf(0.0, _rig.stamina - sprint_drain_per_sec * delta)
		draining = true
	elif _rig.focus_mode == CameraRig.FocusMode.AIMING:
		_rig.stamina = maxf(0.0, _rig.stamina - aim_drain_per_sec * delta)
		draining = true

	if draining:
		_recover_timer = recover_delay
	else:
		_recover_timer = maxf(0.0, _recover_timer - delta)
		if _recover_timer <= 0.0 and _rig.stamina < 1.0:
			_rig.stamina = minf(1.0, _rig.stamina + recover_per_sec * delta)

	# Exhaustion gate: movement reads this to refuse sprinting.
	_player.exhausted = _rig.stamina <= 0.02

	# Death check (damage flows into rig.health01 from Events.player_damaged).
	if _rig.health01 <= 0.0:
		_dead = true
		_player.dead = true
		# R29: only a FRESH creature tag routes through the jumpscare — see
		# last_damage_stamp_ms. Stale tags (survived swipe + later fall death)
		# keep the classic environmental route.
		var tag_fresh: bool = float(Time.get_ticks_msec() - last_damage_stamp_ms) \
				<= kill_source_window * 1000.0
		if last_damage_source == DamageSource.CREATURE and tag_fresh:
			Events.player_killed_by_creature.emit()
		Events.player_died.emit()


func _on_player_damaged(_amount: float, direction: Vector3) -> void:
	last_damage_direction = direction


func _on_respawn_requested() -> void:
	if not _dead:
		return
	_dead = false
	last_damage_source = DamageSource.NONE
	last_damage_stamp_ms = 0
	last_damage_direction = Vector3.ZERO
	_player.dead = false
	_rig.set_health(1.0)
	_rig.set_stamina(1.0)
	_player.global_position = _spawn
	_player.velocity = Vector3.ZERO
	Events.player_respawned.emit()
