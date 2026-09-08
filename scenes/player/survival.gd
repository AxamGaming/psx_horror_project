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
var _spawn: Vector3


func _ready() -> void:
	_player = get_parent() as PlayerMovement
	assert(_player != null, "SurvivalSystem must be a child of the Player body.")
	_rig = Events.main_camera as CameraRig
	_spawn = _player.global_position
	Events.respawn_requested.connect(_on_respawn_requested)


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
		Events.player_died.emit()


func _on_respawn_requested() -> void:
	if not _dead:
		return
	_dead = false
	_player.dead = false
	_rig.set_health(1.0)
	_rig.set_stamina(1.0)
	_player.global_position = _spawn
	_player.velocity = Vector3.ZERO
	Events.player_respawned.emit()
