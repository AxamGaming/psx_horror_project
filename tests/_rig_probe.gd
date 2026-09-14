extends SceneTree
## RIG PROBE — dumps everything needed to author kill poses BY HAND:
##   * rest pose of all 92 bones (pos/rot/scale) as JSON
##   * sampled poses from the shipped animations (bite / roar / attack_3 /
##     eating / battle_idle) so authored kills can be built on real poses
##   * an empirical axis probe: rotate bone X by +25 deg around each local axis
##     and report where the hand/head moves, so the axis convention is known
##     instead of guessed.
## Output: user://rig_dump.json
var _frame: int = 0


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_run()
	quit(0)
	return true


func _run() -> void:
	var ps: PackedScene = load("res://assets/models/nightmare_creature/nightmare_creature_1.glb")
	var model: Node = ps.instantiate()
	var root := Node3D.new()
	get_root().add_child(root)
	root.add_child(model)
	var skel: Skeleton3D = null
	var ap: AnimationPlayer = null
	for c in model.find_children("*", "Skeleton3D", true, true):
		skel = c
		break
	for c in model.find_children("*", "AnimationPlayer", true, true):
		ap = c
		break
	var out := {}

	# ── 1. rest poses + hierarchy ────────────────────────────────────────────
	var bones := {}
	for i in skel.get_bone_count():
		var r: Transform3D = skel.get_bone_rest(i)
		var q: Quaternion = r.basis.get_rotation_quaternion()
		bones[skel.get_bone_name(i)] = {
			"idx": i,
			"parent": skel.get_bone_parent(i),
			"parent_name": (skel.get_bone_name(skel.get_bone_parent(i)) if skel.get_bone_parent(i) >= 0 else ""),
			"pos": [r.origin.x, r.origin.y, r.origin.z],
			"rot": [q.x, q.y, q.z, q.w],
			"scale": [r.basis.get_scale().x, r.basis.get_scale().y, r.basis.get_scale().z],
		}
	out["rest"] = bones
	out["bone_order"] = []
	for i in skel.get_bone_count():
		out["bone_order"].append(skel.get_bone_name(i))

	# ── 2. sampled poses from shipped animations ─────────────────────────────
	var samples := {}
	var want := {
		"Creature_armature|bite": [0.0, 0.2, 0.4, 0.6, 0.83],
		"Creature_armature|roar": [0.0, 0.3, 0.6, 0.9, 1.2],
		"Creature_armature|attack_3": [0.0, 0.15, 0.3, 0.45, 0.6],
		"Creature_armature|eating": [0.0, 0.4, 0.8],
		"Creature_armature|battle_idle": [0.0, 0.5],
		"Creature_armature|attack_1": [0.0, 0.2, 0.4],
		"Creature_armature|idle": [0.0],
	}
	for aname in want:
		if not ap.has_animation(aname):
			continue
		var a: Animation = ap.get_animation(aname)
		var tracks := {}
		for i in a.get_track_count():
			var pn: NodePath = a.track_get_path(i)
			var s: String = String(pn)
			var bone: String = s.get_slice(":", 1) if ":" in s else ""
			if bone == "":
				continue
			tracks[bone] = {"type": a.track_get_type(i), "node": s.get_slice(":", 0), "keys": []}
			for k in a.track_get_key_count(i):
				var t: float = a.track_get_key_time(i, k)
				var v = a.track_get_key_value(i, k)
				var vv
				if v is Quaternion:
					vv = [v.x, v.y, v.z, v.w]
				elif v is Vector3:
					vv = [v.x, v.y, v.z]
				else:
					vv = [v]
				tracks[bone]["keys"].append([t, vv])
		samples[aname] = {"length": a.length, "tracks": tracks}
	out["anims"] = samples

	# ── 3. empirical axis probe ─────────────────────────────────────────────
	# Baseline global positions of the "watch" bones, then rotate one bone at a
	# time and report the delta. Tells me which local axis opens the jaw,
	# raises an arm, twists the spine.
	var watch := ["Head_015", "Jaw_016", "Hand.R_037", "Hand.L_020", "spine_5_013", "Upper_arm.R_035"]
	var widx := {}
	for w in watch:
		widx[w] = skel.find_bone(w)
	skel.reset_bone_poses()
	skel.force_update_all_bone_transforms()
	var base := {}
	for w in watch:
		base[w] = skel.get_bone_global_pose(widx[w]).origin
	var probe := {}
	var targets := ["Jaw_016", "Head_015", "Neck_014", "Upper_arm.R_035", "Bottom_arm.R_036",
		"Hand.R_037", "Clavicle.R_034", "spine_3_011", "spine_5_013", "Hips_ctrl_08",
		"Upper_arm.L_018", "Bottom_arm.L_019"]
	for tb in targets:
		var ti: int = skel.find_bone(tb)
		if ti < 0:
			continue
		var rest_q: Quaternion = skel.get_bone_rest(ti).basis.get_rotation_quaternion()
		probe[tb] = {}
		for axis_i in 3:
			for sign in [1.0, -1.0]:
				var ax := Vector3.ZERO
				ax[axis_i] = sign
				skel.reset_bone_poses()
				skel.set_bone_pose_rotation(ti, rest_q * Quaternion(ax, deg_to_rad(25.0)))
				skel.force_update_all_bone_transforms()
				var deltas := {}
				for w in watch:
					var d: Vector3 = skel.get_bone_global_pose(widx[w]).origin - base[w]
					if d.length() > 0.002:
						deltas[w] = [float(snappedf(d.x, 0.001)), float(snappedf(d.y, 0.001)), float(snappedf(d.z, 0.001))]
				var key := "%s%d" % ["XYZ".substr(axis_i, 1), int(sign)]
				probe[tb][key] = deltas
	skel.reset_bone_poses()
	out["probe"] = probe
	out["probe_base"] = {}
	for w in watch:
		out["probe_base"][w] = [base[w].x, base[w].y, base[w].z]

	var f := FileAccess.open("user://rig_dump.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("WROTE user://rig_dump.json  bones=", bones.size(), " anims=", samples.size(), " probe=", probe.size())
	print("PROBE_DONE")
