extends StaticBody3D
class_name PropStatic
## ============================================================================
## PROP STATIC — the placement contract for every mesh prop in the game.
##
## Usage (editor): instance a prop scene (scenes/props/*) OR drag any imported
## mesh scene under a StaticBody3D with this script. Two exports do the work:
##   surface_tag  -> joins group "surface_<tag>"; the footstep raycast reads
##                   these groups to pick step sounds (wood/metal/...).
##   auto_collide -> generates trimesh collision from the mesh at runtime if
##                   the prop has no CollisionShape child (zero editor chores).
##
## Props are StaticBody3D: free physics, free raycast targets, no tick cost.
## ============================================================================

@export var surface_tag: String = ""
@export var auto_collide: bool = true


func _ready() -> void:
	if surface_tag != "":
		add_to_group("surface_" + surface_tag)
	if auto_collide and not _has_collision():
		var mi: MeshInstance3D = _find_mesh(self)
		if mi != null and mi.mesh != null:
			mi.create_trimesh_collision()


func _find_mesh(n: Node) -> MeshInstance3D:
	for c in n.get_children():
		var m: MeshInstance3D = c as MeshInstance3D
		if m != null:
			return m
		var r: MeshInstance3D = _find_mesh(c)
		if r != null:
			return r
	return null


func _has_collision() -> bool:
	for c in get_children():
		if c is CollisionShape3D:
			return true
	return false
