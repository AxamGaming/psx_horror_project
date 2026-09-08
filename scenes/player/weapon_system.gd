extends Node
class_name WeaponSystem
## ============================================================================
## WEAPON SYSTEM — Phase 11. Double-barrel shotgun.
##
## Flow: find it (hall stage pickup) -> Tab -> USE to equip (item stays in
## inventory; it IS your gun) -> hold RMB to aim (focus mode AIMING: steadied
## gait + zoom + held-breath stamina drain + low-stamina tremble from the rig)
## -> LMB fires (positional blast, recoil nudge, muzzle flash) -> R reloads
## (consumes Shell items from the inventory through Events.shells_requested/
## shells_granted — the inventory is the ammo pool).
##
## No enemies yet: _trace_shot() runs the pellet ray anyway so the enemy phase
## only needs to read its result.
## ============================================================================

@export var barrels_max: int = 2
@export var reload_time: float = 1.4
@export var recoil_nudge: float = 1.4
@export var fire_distance: float = 40.0
@export var flash_time: float = 0.06

var equipped: String = ""
var barrels: int = 0
var _reloading: bool = false
var _was_aiming: bool = false
var _dead: bool = false
var _flash_t: float = 0.0
var _pending_shells: int = 0
var _player: PlayerMovement
var _rig: CameraRig
var _flash: OmniLight3D
var _stream_blast: AudioStream
var _stream_pump: AudioStream
var _stream_dry: AudioStream


func _ready() -> void:
	_player = get_parent() as PlayerMovement
	_rig = Events.main_camera as CameraRig
	_stream_blast = load("res://audio/sfx/shotgun_blast.wav") as AudioStream
	_stream_pump = load("res://audio/sfx/shotgun_pump.wav") as AudioStream
	_stream_dry = load("res://audio/sfx/gun_dry.wav") as AudioStream
	_flash = OmniLight3D.new()
	_flash.light_energy = 8.0
	_flash.omni_range = 6.0
	_flash.light_color = Color(1.0, 0.8, 0.4, 1.0)
	_flash.visible = false
	add_child(_flash)
	Events.item_used.connect(_on_item_used)
	Events.shells_granted.connect(_on_shells_granted)
	Events.player_died.connect(_on_died)
	Events.player_respawned.connect(_on_respawned)


func _on_died() -> void:
	_dead = true
	if _was_aiming:
		_was_aiming = false
		if _rig != null:
			_rig.set_focus_mode(CameraRig.FocusMode.EXPLORING)
			_rig.set_aim_zoom(false)


func _on_respawned() -> void:
	_dead = false


func _on_item_used(item_id: String) -> void:
	if item_id == "shotgun" and equipped == "":
		equipped = "shotgun"
		barrels = barrels_max   # found loaded
		AudioMgr.play_world_sound(_stream_pump, _muzzle_pos(), -6.0)


func _aiming() -> bool:
	return (
		equipped != ""
		and not _dead
		and not Events.ui_wants_mouse
		and Input.is_action_pressed("aim")
	)


func _process(delta: float) -> void:
	if _rig == null:
		return
	var want: bool = _aiming()
	if want != _was_aiming:
		_was_aiming = want
		_rig.set_focus_mode(CameraRig.FocusMode.AIMING if want else CameraRig.FocusMode.EXPLORING)
		_rig.set_aim_zoom(want)
	if _flash_t > 0.0:
		_flash_t = maxf(0.0, _flash_t - delta)
		if _flash_t <= 0.0:
			_flash.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _dead or equipped == "" or Events.ui_wants_mouse:
		return
	if event.is_action_pressed("fire"):
		_fire()
	elif event.is_action_pressed("reload"):
		_start_reload()


func _fire() -> void:
	if _reloading:
		return
	if barrels <= 0:
		AudioMgr.play_world_sound(_stream_dry, _muzzle_pos(), -8.0)
		return
	barrels -= 1
	# Real recording, slight per-shot pitch variance so repeats never identical.
	AudioMgr.play_world_sound(_stream_blast, _muzzle_pos(), -2.0, randf_range(0.94, 1.06))
	Events.gun_fired.emit(_rig.global_position)
	var fwd: Vector3 = -_rig.global_transform.basis.z
	var kick: Vector3 = fwd + Vector3.UP * 0.3 + _rig.global_transform.basis.x * randf_range(-0.2, 0.2)
	_rig.apply_nudge(kick, recoil_nudge)
	_flash.global_position = _rig.global_position + fwd * 0.6 - _rig.global_transform.basis.y * 0.08
	_flash.light_energy = randf_range(6.0, 9.0)
	_flash.visible = true
	_flash_t = flash_time
	_trace_shot(fwd)
	if barrels == 0:
		# Both barrels spent: the breach breaks open a beat later.
		var tw2: Tween = create_tween()
		tw2.tween_interval(0.5)
		tw2.tween_callback(_play_break_open)


func _trace_shot(fwd: Vector3) -> void:
	var world: World3D = _rig.get_world_3d()
	if world == null:
		return
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	if space == null:
		return
	var b: Basis = _rig.global_transform.basis
	var player_node: Node = _rig.get_parent().get_parent() if _rig.get_parent() != null else null
	# 8-pellet cone (~±3°): when enemies arrive, the spread will matter.
	for i in range(8):
		var dir: Vector3 = (fwd + b.x * randf_range(-0.05, 0.05) + b.y * randf_range(-0.05, 0.05)).normalized()
		var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			_rig.global_position, _rig.global_position + dir * fire_distance
		)
		if player_node != null:
			q.exclude = [player_node.get_rid()]
		var r: Dictionary = space.intersect_ray(q)
		if not r.is_empty():
			# Pellet hit: walk up the tree for anything that takes damage
			# (the creature, future enemies, destructibles...).
			var node: Node = r.get("collider") as Node
			while node != null:
				if node.has_method("take_damage"):
					node.take_damage(12.0, dir)
					break
				node = node.get_parent()


func _play_break_open() -> void:
	AudioMgr.play_world_sound(_stream_pump, _muzzle_pos(), -8.0)


func _start_reload() -> void:
	if _reloading or barrels >= barrels_max:
		return
	_reloading = true
	_pending_shells = 0
	AudioMgr.play_world_sound(_stream_pump, _muzzle_pos(), -6.0)
	Events.shells_requested.emit(barrels_max - barrels)
	var tw: Tween = create_tween()
	tw.tween_interval(reload_time)
	tw.tween_callback(_finish_reload)


func _on_shells_granted(n: int) -> void:
	if not _reloading:
		return
	_pending_shells = n
	if n <= 0:
		AudioMgr.play_world_sound(_stream_dry, _muzzle_pos(), -8.0)


func _finish_reload() -> void:
	var added: int = mini(barrels_max, barrels + _pending_shells) - barrels
	barrels += added
	_pending_shells = 0
	_reloading = false
	if added > 0:
		# Breach closes over fresh shells.
		AudioMgr.play_world_sound(_stream_pump, _muzzle_pos(), -7.0)


func _muzzle_pos() -> Vector3:
	if _rig == null:
		return Vector3.ZERO
	return _rig.global_position + (-_rig.global_transform.basis.z) * 0.5
