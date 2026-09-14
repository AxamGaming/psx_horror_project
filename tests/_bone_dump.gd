extends SceneTree
func _init():
	var ps: PackedScene = load("res://assets/models/nightmare_creature/nightmare_creature_1.glb")
	var n = ps.instantiate()
	_walk(n, 0)
	quit(0)
func _walk(n: Node, d: int):
	var pad = "  ".repeat(d)
	print(pad, n.get_class(), " : ", n.name)
	if n is Skeleton3D:
		var sk: Skeleton3D = n
		print(pad, "  bones=", sk.get_bone_count())
		for i in sk.get_bone_count():
			print(pad, "   [%d] %s parent=%d" % [i, sk.get_bone_name(i), sk.get_bone_parent(i)])
	if n is AnimationPlayer:
		print(pad, "  anims=", n.get_animation_list())
	for c in n.get_children():
		_walk(c, d+1)
