class_name ItemData
extends Resource
## One inventory item definition. Instances live in data/item_database.tres —
## edit names/weights/colors/MESHES THERE (inspector), never in code.
## `mesh` = the world visual for pickups & drops of this item (any mesh/prop
## scene). Per-place overrides still possible via PickupItem.mesh_scene.
@export var id: String = ""
@export var item_name: String = ""
@export var weight: float = 0.1
@export var color: Color = Color(1, 1, 1, 1)
@export var mesh: PackedScene = null
