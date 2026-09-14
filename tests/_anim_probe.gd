extends SceneTree
func _init():
	var ps: PackedScene = load("res://assets/models/nightmare_creature/nightmare_creature_1.glb")
	var n = ps.instantiate()
	var ap: AnimationPlayer = null
	var sk: Skeleton3D = null
	for c in n.find_children("*", "AnimationPlayer", true, true): ap = c
	for c in n.find_children("*", "Skeleton3D", true, true): sk = c
	print("AP=", ap.get_path(), " root_node=", ap.root_node, " mixer_root_default=", ap.get_node(ap.root_node).get_path() if ap.has_node(ap.root_node) else "?")
	var lib := ap.get_animation_library_list()
	print("libs=", lib)
	var a: Animation = ap.get_animation("Creature_armature|bite")
	print("bite len=", a.length, "tracks=", a.get_track_count())
	for i in range(mini(a.get_track_count(), 8)):
		print("  track %d type=%d path=%s keys=%d" % [i, a.track_get_type(i), a.track_get_path(i), a.track_get_key_count(i)])
	# rest poses of the interesting bones
	var want := ["_rootJoint","Base_bone_01","Hips_ctrl_08","spine_1_09","spine_3_011","spine_5_013","Neck_014","Head_015","Jaw_016","Clavicle.L_017","Upper_arm.L_018","Bottom_arm.L_019","Hand.L_020","Clavicle.R_034","Upper_arm.R_035","Bottom_arm.R_036","Hand.R_037"]
	var out := {}
	for w in want:
		var idx := sk.find_bone(w)
		if idx < 0: print("MISSING BONE ", w); continue
		var r: Transform3D = sk.get_bone_rest(idx)
		out[w] = {"idx": idx, "pos": [r.origin.x, r.origin.y, r.origin.z], "rot": [r.basis.get_rotation_quaternion().x, r.basis.get_rotation_quaternion().y, r.basis.get_rotation_quaternion().z, r.basis.get_rotation_quaternion().w], "scale": [r.basis.get_scale().x, r.basis.get_scale().y, r.basis.get_scale().z]}
		print("REST ", w, " pos=", r.origin, " rotq=", r.basis.get_rotation_quaternion(), " scale=", r.basis.get_scale())
	var f := FileAccess.open("user://anim_probe.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	# sample a bite pose at a mid key so we know the authored pose style
	var ti := 0
	for i in range(a.get_track_count()):
		if String(a.track_get_path(i)).contains("Hand.R") or String(a.track_get_path(i)).contains("Jaw"):
			print("SAMPLE ", a.track_get_path(i), " keys:", a.track_get_key_time(i, 0), a.track_get_key_value(i, 0), " | ", a.track_get_key_time(i, int(a.track_get_key_count(i)/2)), a.track_get_key_value(i, int(a.track_get_key_count(i)/2)))
	print("PROBE_DONE")
	quit(0)
