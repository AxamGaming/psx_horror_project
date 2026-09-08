extends Node3D
class_name PickupItem
## ============================================================================
## PICKUP ITEM — world-placed, fully inspector-configurable (no hardcoding).
##
## To place a new pickup in any level:
##   1. Instance scenes/level/pickup_item.tscn (or add a Node3D + this script).
##   2. Set `item_id` to a key from data/item_database.tres (that's where names,
##      weights and colors live — add new item types THERE).
##   3. Assign `mesh_scene` = ANY mesh/prop scene you want as its visual
##      (shotgun model, shell box, medkit...). Leave it null for the default
##      tinted crate (tint = the item's DB color).
##   4. Position/rotate/scale the visual with mesh_offset / mesh_rotation_deg /
##      mesh_scale. The root auto-snaps to the ground under it.
##
## Collision shapes inside assigned scenes are auto-disabled so pickups never
## block the player. Press E within take_distance -> Events.pickup_triggered.
## ============================================================================

@export var item_id: String = "shotgun"
@export var take_distance: float = 2.5
@export var mesh_scene: PackedScene = null                # assign any mesh here
@export var mesh_offset: Vector3 = Vector3.ZERO
@export var mesh_rotation_deg: Vector3 = Vector3.ZERO
@export var mesh_scale: float = 1.0

const ITEM_DB_RES: ItemDatabase = preload("res://data/item_database.tres")

var _taken: bool = false
var _db_color: Color = Color(0.45, 0.35, 0.22)   # crate tint, single source = DB


func _ready() -> void:
	# Resolution order: per-node override -> item database -> crate fallback.
	# Color for the fallback crate ALSO comes from the DB (single source).
	if mesh_scene == null:
		for entry in ITEM_DB_RES.items:
			var d: ItemData = entry as ItemData
			if d != null and d.id == item_id:
				mesh_scene = d.mesh
				_db_color = d.color
				break
	if mesh_scene != null:
		var inst: Node = mesh_scene.instantiate()
		add_child(inst)
		inst.position = mesh_offset
		inst.rotation_degrees = mesh_rotation_deg
		inst.scale = Vector3.ONE * mesh_scale
		# Pickups must never block movement: kill any collision they bring.
		for c in inst.find_children("*", "CollisionShape3D"):
			c.set_deferred("disabled", true)
	else:
		var mesh: MeshInstance3D = MeshInstance3D.new()
		var m: BoxMesh = BoxMesh.new()
		m.size = Vector3(0.45, 0.22, 0.7)
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = _db_color
		mat.roughness = 0.9
		mesh.material_override = mat
		mesh.mesh = m
		mesh.position = Vector3(0.0, 0.11, 0.0) + mesh_offset
		mesh.rotation_degrees = mesh_rotation_deg
		mesh.scale = Vector3.ONE * mesh_scale
		add_child(mesh)
	request_snap()


## Drop the item onto whatever ground is below it.
func request_snap() -> void:
	var world: World3D = get_world_3d()
	if world == null:
		return
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	if space == null:
		return
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0.0, 1.0, 0.0), global_position - Vector3(0.0, 3.0, 0.0)
	)
	var r: Dictionary = space.intersect_ray(q)
	if not r.is_empty():
		global_position = (r["position"] as Vector3) + Vector3(0.0, 0.02, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if _taken:
		return
	if InputMap.has_action("interact") and event.is_action_pressed("interact"):
		var cam: Camera3D = Events.main_camera
		if cam == null:
			return
		var player: Node = cam.get_parent().get_parent() if cam.get_parent() != null else null
		if player == null:
			return
		var flat: Vector3 = Vector3(
			global_position.x - player.global_position.x,
			0.0,
			global_position.z - player.global_position.z
		)
		if flat.length() <= take_distance:
			_taken = true
			visible = false
			Events.pickup_triggered.emit(item_id)
			# One press = one pickup: consume the input so siblings
			# (and doors) don't also trigger on the same E.
			get_viewport().set_input_as_handled()
