extends SceneTree
## Verifies that an AnimationPlayer whose root_node points at a Skeleton3D can
## drive bone poses with "<BoneName>:rotation" tracks. The whole R30 authored
## kill-animation plan rests on this assumption.
func _init():
	var ps: PackedScene = load("res://assets/models/nightmare_creature/nightmare_creature_1.glb")
	var model: Node = ps.instantiate()
	var root := Node3D.new()
	root.name = "Root"
	get_root().add_child(root)
	root.add_child(model)
	var skel: Skeleton3D = null
	for c in model.find_children("*", "Skeleton3D", true, true):
		skel = c
		break
	print("skel path from root: ", root.get_path_to(skel))
	var holder := Node3D.new()
	holder.name = "Director"
	root.add_child(holder)
	var ap := AnimationPlayer.new()
	ap.name = "KillAnim"
	holder.add_child(ap)
	ap.root_node = ap.get_path_to(skel.get_parent())   # mixer resolves "Skeleton3D:Bone" from the skeleton PARENT
	print("root_node set to: ", ap.root_node)
	# What does the imported glTF animation actually use as its track path/property?
	var ref_ap: AnimationPlayer = null
	for c in model.find_children("*", "AnimationPlayer", true, true):
		ref_ap = c
		break
	var ref: Animation = ref_ap.get_animation("Creature_armature|bite")
	for i in range(ref.get_track_count()):
		var pn: NodePath = ref.track_get_path(i)
		if String(pn).contains("Jaw_016"):
			print("REF TRACK nodepath=", pn, "  names=", pn.get_name_count(), " subnames=", pn.get_subname_count(), " type=", ref.track_get_type(i))
			for si in pn.get_subname_count():
				print("    subname[", si, "]=", pn.get_subname(si))
			for ni in pn.get_name_count():
				print("    name[", ni, "]=", pn.get_name(ni))
			break
	print("ref_ap.root_node=", ref_ap.root_node)
	var names: Array[String] = []
	for m in ClassDB.class_get_method_list("Skeleton3D", true):
		var nm := String(m.get("name"))
		if nm.contains("update") or nm.contains("dirty") or nm.contains("clear") or nm.contains("physical") or nm.contains("reset"):
			names.append(nm)
	names.sort()
	print("Skeleton3D relevant methods: ", names)

	var a := Animation.new()
	a.length = 0.4
	a.loop_mode = Animation.LOOP_NONE
	var rest_q := Quaternion(0.222978, 0.0, 0.0, 0.974823)
	var open_q := Quaternion(0.939693, 0.0, 0.0, 0.342020)
	var ti: int = a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(ti, NodePath("Skeleton3D:Jaw_016"))
	a.track_insert_key(ti, 0.0, rest_q)
	a.track_insert_key(ti, 0.2, open_q)
	a.track_insert_key(ti, 0.4, rest_q)
	var hips: int = skel.find_bone("Hips_ctrl_08")
	var rest_p: Vector3 = skel.get_bone_rest(hips).origin
	var tj: int = a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(tj, NodePath("Skeleton3D:Hips_ctrl_08"))
	a.track_insert_key(tj, 0.0, rest_p)
	a.track_insert_key(tj, 0.4, rest_p + Vector3(0, 0.4, 0))
	var lib := AnimationLibrary.new()
	lib.add_animation("test_kill", a)
	ap.add_animation_library("", lib)

	var jaw: int = skel.find_bone("Jaw_016")
	var before: Quaternion = skel.get_bone_pose_rotation(jaw)
	print("BEFORE jaw local rot = ", before)
	ap.play("test_kill")
	ap.advance(0.2)
	skel.force_update_all_bone_transforms()
	var after: Quaternion = skel.get_bone_pose_rotation(jaw)
	print("AT 0.2 jaw local rot = ", after)
	ap.advance(0.2)
	skel.force_update_all_bone_transforms()
	var gp: Vector3 = skel.get_bone_global_pose(hips).origin
	print("AT 0.4 hips global = ", gp, " rest-origin=", rest_p)
	var ok: bool = absf(after.x - open_q.x) < 0.01
	print("autoplay='", ref_ap.autoplay, "' current='", ref_ap.current_animation, "' playing=", ref_ap.is_playing())
	print(ok and "TRACKS_RESOLVE_OK" or "TRACKS_FAILED")
	print("TEST_DONE")
	quit(0)
