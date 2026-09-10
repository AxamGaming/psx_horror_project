class_name MovementController
extends Node

@export var walk_speed: float = 2.2
@export var run_speed: float = 4.6
@export var lunge_speed: float = 7.5
@export var gravity: float = 18.0
@export var attack_standoff: float = 1.35

var parent_body: CharacterBody3D = null
var nav_agent: NavigationAgent3D = null

var _current_target: Vector3 = Vector3.ZERO
var _is_moving: bool = false
var _move_speed: float = 0.0
var _move_dir: Vector3 = Vector3.ZERO
var _stuck_timer: float = 0.0

signal arrived

func _ready() -> void:
	parent_body = get_parent() as CharacterBody3D
	assert(parent_body, "MovementController must be child of a CharacterBody3D.")

	nav_agent = NavigationAgent3D.new()
	nav_agent.name = "NavAgent"
	nav_agent.path_desired_distance = 0.4
	nav_agent.target_desired_distance = 0.4
	nav_agent.path_max_distance = 6.0
	nav_agent.avoidance_enabled = false

	call_deferred("add_child", nav_agent)
	call_deferred("_setup_nav_agent")

func _setup_nav_agent() -> void:
	if nav_agent == null:
		return
	var baker = get_tree().get_first_node_in_group("nav_baker")
	if baker and baker.has_method("get_map_rid"):
		NavigationServer3D.agent_set_map(nav_agent.get_rid(), baker.get_map_rid())

# Public helper to check if navigation is ready
func has_navigation() -> bool:
	return nav_agent != null and nav_agent.get_navigation_map().is_valid()

func move_to(target: Vector3, speed: float, stop_distance: float = 0.7) -> bool:
	if parent_body == null:
		return true
	_current_target = target
	_move_speed = speed
	_is_moving = true
	var to_target: Vector3 = target - parent_body.global_position
	to_target.y = 0.0
	if to_target.length() <= stop_distance:
		_is_moving = false
		emit_signal("arrived")
		return true
	if has_navigation():
		nav_agent.target_position = target
	return false

func stop() -> void:
	_is_moving = false
	_move_dir = Vector3.ZERO

func is_moving() -> bool:
	return _is_moving

func get_move_direction() -> Vector3:
	return _move_dir

func physics_update(delta: float) -> void:
	if parent_body:
		parent_body.velocity.y -= gravity * delta
		parent_body.velocity.y = max(parent_body.velocity.y, -40.0)

	if not _is_moving:
		parent_body.velocity.x = 0.0
		parent_body.velocity.z = 0.0
		_move_dir = Vector3.ZERO
		return

	var dir: Vector3
	if has_navigation():
		var next_pos: Vector3 = nav_agent.get_next_path_position()
		dir = next_pos - parent_body.global_position
		dir.y = 0.0
		if dir.length_squared() < 0.0001:
			var to_target: Vector3 = _current_target - parent_body.global_position
			to_target.y = 0.0
			dir = to_target.normalized()
		else:
			dir = dir.normalized()
	else:
		var to_target: Vector3 = _current_target - parent_body.global_position
		to_target.y = 0.0
		if to_target.length() > 0.1:
			dir = to_target.normalized()
		else:
			parent_body.velocity.x = 0.0
			parent_body.velocity.z = 0.0
			_move_dir = Vector3.ZERO
			parent_body.move_and_slide()
			return

	_move_dir = dir
	parent_body.velocity.x = dir.x * _move_speed
	parent_body.velocity.z = dir.z * _move_speed
	parent_body.move_and_slide()

	var vel_flat = Vector2(parent_body.velocity.x, parent_body.velocity.z).length()
	if _is_moving and vel_flat < 0.2:
		_stuck_timer += delta
		if _stuck_timer > 0.5:
			stop()
			_stuck_timer = 0.0
	else:
		_stuck_timer = 0.0
