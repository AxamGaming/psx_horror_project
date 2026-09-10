class_name Perception
extends Node

@export var sight_range: float = 12.0
@export var fov_deg: float = 75.0
@export var hear_radius: float = 16.0
@export var proximity_range: float = 2.5

var player: PlayerMovement = null
var creature: CharacterBody3D = null
var state: AwarenessState = AwarenessState.new()
var _ray: RayCast3D

func _ready() -> void:
    creature = get_parent() as CharacterBody3D
    assert(creature, "Perception must be child of NightmareCreature.")
    _ray = RayCast3D.new()
    _ray.name = "PerceptionRay"
    _ray.enabled = true
    _ray.collision_mask = 17
    add_child(_ray)

func update() -> void:
    if player == null:
        player = get_tree().get_first_node_in_group("player") as PlayerMovement
        if player == null:
            return
    var dist_2d: float = _flat_distance(creature.global_position, player.global_position)
    var proximity_los: bool = false
    if dist_2d < proximity_range:
        proximity_los = _has_los(creature, player, true)
    state.proximity_detected = proximity_los

    state.is_visible = _check_vision()
    if state.is_visible:
        state.last_seen_position = player.global_position
        state.last_seen_time = Time.get_ticks_msec() / 1000.0

    var noise: float = player.noise_level if player else 0.0
    if noise > 0.05 and dist_2d < hear_radius * noise:
        state.is_heard = true
        state.last_heard_position = player.global_position
        state.last_heard_time = Time.get_ticks_msec() / 1000.0
    else:
        state.is_heard = false

func _check_vision() -> bool:
    if player == null or creature == null:
        return false
    var to_player: Vector3 = player.global_position - creature.global_position
    var dist_2d: float = Vector2(to_player.x, to_player.z).length()
    if dist_2d > sight_range:
        return false
    var forward: Vector3 = -creature.global_transform.basis.z
    forward.y = 0.0
    var flat_to_player: Vector3 = to_player
    flat_to_player.y = 0.0
    if forward.length_squared() < 0.0001 or flat_to_player.length_squared() < 0.0001:
        return false
    if rad_to_deg(forward.normalized().angle_to(flat_to_player.normalized())) > fov_deg * 0.5:
        return false
    return _has_los(creature, player, false)

func _has_los(from_node: Node3D, to_node: Node3D, _use_proximity: bool) -> bool:
    var origin_offsets: Array[Vector3] = [
        Vector3(0.0, 1.5, 0.0),
        Vector3(0.25, 1.5, 0.0),
        Vector3(-0.25, 1.5, 0.0),
        Vector3(0.0, 1.8, 0.0)
    ]
    var target_pos: Vector3 = to_node.global_position + Vector3(0.0, 1.0, 0.0)
    for offset in origin_offsets:
        var origin: Vector3 = from_node.global_position + offset
        _ray.global_position = origin
        _ray.target_position = _ray.to_local(target_pos)
        _ray.force_raycast_update()
        if not _ray.is_colliding():
            return true
    return false

func _flat_distance(a: Vector3, b: Vector3) -> float:
    return Vector2(a.x - b.x, a.z - b.z).length()
