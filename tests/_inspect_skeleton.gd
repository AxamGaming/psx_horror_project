extends SceneTree
## Dev probe: dump skeleton bone names + rest positions (creature-body space,
## with ModelRoot's 180 deg applied) to place bone-attached hull colliders.
func _init() -> void:
	var cre: Node3D = (load("res://scenes/enemies/nightmare_creature.tscn") as PackedScene).instantiate()
	root.add_child(cre)
	# let one frame pass so ModelRoot transform applies
	await physics_frame
	var skel: Skeleton3D = null
	var stack: Array[Node] = [cre]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is Skeleton3D:
			skel = n
			break
		for c in n.get_children():
			stack.append(c)
	if skel == null:
		print("NO SKELETON"); quit(1); return
	print("skeleton path: ", cre.get_path_to(skel))
	print("bone count: ", skel.get_bone_count())
	var wanted := ["Head", "Jaw", "spine_3", "spine_4", "spine_5", "Hand.L", "Hand.R", "Neck", "Clavicle", "Upper_arm", "Bottom_arm"]
	for i in range(skel.get_bone_count()):
		var nm := skel.get_bone_name(i)
		for w in wanted:
			if String(nm).begins_with(w):
				var gt: Transform3D = skel.get_bone_global_pose(i)
				var local: Vector3 = skel.global_transform * gt.origin
				var body_space: Vector3 = cre.to_local(skel.global_transform * gt.origin)
				print("%-18s boneLocal=(%6.2f,%6.2f,%6.2f)  BODY=(%6.3f,%6.3f,%6.3f)" % [nm, gt.origin.x, gt.origin.y, gt.origin.z, body_space.x, body_space.y, body_space.z])
				break
	# also dump the HeadHitbox area position for cross-check
	var hb: Node3D = cre.get_node_or_null("HeadHitbox")
	if hb != null:
		print("HeadHitbox (user-matched visual head) BODY=(", hb.position.x, ",", hb.position.y, ",", hb.position.z, ")")
	quit(0)
