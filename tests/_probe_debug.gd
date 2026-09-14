extends SceneTree
## Debug why the axis probe reported zero movement.
func _init():
	var ps: PackedScene = load("res://assets/models/nightmare_creature/nightmare_creature_1.glb")
	var model: Node = ps.instantiate()
	var root := Node3D.new()
	get_root().add_child(root)
	root.add_child(model)
	var skel: Skeleton3D = null
	for c in model.find_children("*", "Skeleton3D", true, true):
		skel = c
		break
	print("skeleton=", skel.name, " bones=", skel.get_bone_count())
	var head: int = skel.find_bone("Head_015")
	var jaw: int = skel.find_bone("Jaw_016")
	print("head idx=", head, " jaw idx=", jaw)
	print("skel.global_transform=", skel.global_transform)
	skel.reset_bone_poses()
	skel.force_update_all_bone_transforms()
	var b_head: Vector3 = skel.get_bone_global_pose(head).origin
	var b_jaw: Vector3 = skel.get_bone_global_pose(jaw).origin
	print("BASE head=", b_head, " jaw=", b_jaw)
	var rest_q: Quaternion = skel.get_bone_rest(head).basis.get_rotation_quaternion()
	print("head rest_q=", rest_q)
	skel.set_bone_pose_rotation(head, rest_q * Quaternion(Vector3(1, 0, 0), deg_to_rad(40.0)))
	print("after set: local rot=", skel.get_bone_pose_rotation(head))
	skel.force_update_all_bone_transforms()
	var a_head: Vector3 = skel.get_bone_global_pose(head).origin
	var a_jaw: Vector3 = skel.get_bone_global_pose(jaw).origin
	print("ROT  head=", a_head, " (delta ", a_head - b_head, ")")
	print("ROT  jaw =", a_jaw, " (delta ", a_jaw - b_jaw, ")")
	# also check the local pose (relative to parent) which is what animations key
	print("head local pose=", skel.get_bone_pose(head))
	print("jaw  local pose=", skel.get_bone_pose(jaw))
	print("DEBUG_DONE")
	quit(0)
