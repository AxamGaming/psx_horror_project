@tool
extends SceneTree
## ============================================================================
## R30 KILL ANIMATION BUILDER — beats.json -> the two .tres libraries.
##
##   godot --headless --path . -s res://tools/build_kill_anims.gd
##
## Why a builder and not hand-written .tres text: Godot's ResourceSaver writes
## canonical, editor-round-trippable text, so the result stays editable in the
## animation panel AND cannot drift from the engine's own format. The authored
## poses live in audio_work/gen_kill_beats.py; this script only serialises them.
##
## Writes:
##   res://scenes/enemies/kill_anim.tres      — the creature BODY performance
##   res://scenes/enemies/kill_staging.tres   — the sequence clock: method calls
##                                              (audio/FX beats) + light flash
## ============================================================================

const BEATS_PATH := "res://tools/beats.json"
const BODY_OUT := "res://scenes/enemies/kill_anim.tres"
const STAGING_OUT := "res://scenes/enemies/kill_staging.tres"
const BONE_NODE := "Skeleton3D"          # track paths are "<this>:<BoneName>"
const HIPS := "Hips_ctrl_08"

## Staging timeline. The director's segment table (kill_director.gd) maps the
## creature animation onto this clock; these method calls are what fire the
## audio and the effects, so THEY are the frame-accurate beat, and they are
## designer-movable in the animation panel.
const STAGING_LENGTH := 4.50
## name -> [time, method]
const STAGING_CALLS := {
	"kill_grab": [
		[0.00, "beat_impact"],
		[0.16, "beat_grab"],
		[0.62, "beat_gape"],
		[1.15, "beat_bite"],
		[1.55, "beat_slowmo_end"],
		[1.95, "beat_thrash"],
		[2.65, "beat_drop"],
		[3.15, "beat_settle"],
		[4.00, "beat_fade"],
	],
	"kill_swipe": [
		[0.00, "beat_impact"],
		[0.30, "beat_grab"],
		[0.75, "beat_gape"],
		[1.15, "beat_bite"],
		[1.55, "beat_slowmo_end"],
		[1.95, "beat_thrash"],
		[2.65, "beat_drop"],
		[3.15, "beat_settle"],
		[4.00, "beat_fade"],
	],
	"kill_slam": [
		[0.00, "beat_impact"],
		[0.16, "beat_grab"],
		[0.62, "beat_lift"],
		[1.15, "beat_bite"],
		[1.55, "beat_slowmo_end"],
		[1.95, "beat_thrash"],
		[2.65, "beat_drop"],
		[3.15, "beat_settle"],
		[4.00, "beat_fade"],
	],
}

var _frame := 0


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	_run()
	quit(0)
	return true


func _run() -> void:
	var f := FileAccess.open(BEATS_PATH, FileAccess.READ)
	if f == null:
		push_error("build_kill_anims: cannot open %s" % BEATS_PATH)
		return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	if data.is_empty():
		push_error("build_kill_anims: beats.json failed to parse")
		return
	var meta: Dictionary = data["meta"]
	var bones: Array = meta["bones"]
	var hips_rest: Array = meta["hips_rest"]
	var length: float = float(meta["length"])

	# ── body library ────────────────────────────────────────────────────────
	var body := AnimationLibrary.new()
	for aname in data["anims"]:
		var beats: Array = data["anims"][aname]
		var a := Animation.new()
		a.length = length
		a.loop_mode = Animation.LOOP_NONE
		# The kill must NOT snap back to the rest pose when it ends: the
		# creature stays looming over the body through the fade.
		a.set("reset_on_save", false)
		for bone in bones:
			var ti := a.add_track(Animation.TYPE_ROTATION_3D)
			a.track_set_path(ti, NodePath("%s:%s" % [BONE_NODE, bone]))
			# THE PSX LOOK: stepped keys. Nearest interpolation holds each pose
			# until the next beat instead of easing into it, and the beats sit
			# on a 12 fps grid, so the monster moves at a lower frame rate than
			# the (smooth) camera. That mismatch is the 1998 read.
			a.track_set_interpolation_type(ti, Animation.INTERPOLATION_NEAREST)
			for b in beats:
				var rv: Array = b["rot"][bone]
				a.track_insert_key(ti, float(b["t"]), Quaternion(rv[0], rv[1], rv[2], rv[3]))
		# Hips position track: the lift / slam / pull-in beats move the root.
		var tp := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(tp, NodePath("%s:%s" % [BONE_NODE, HIPS]))
		a.track_set_interpolation_type(tp, Animation.INTERPOLATION_LINEAR)
		var base := Vector3(hips_rest[0], hips_rest[1], hips_rest[2])
		a.track_insert_key(tp, 0.0, base)
		var last := base
		for b in beats:
			if b.has("hips"):
				var h: Array = b["hips"]
				last = base + Vector3(h[0], h[1], h[2])
			a.track_insert_key(tp, float(b["t"]), last)
		# Hold the final pose to the end of the timeline.
		a.track_insert_key(tp, length, last)
		body.add_animation(aname, a)
		print("  body  %-12s %d beats, %d rotation tracks, len=%.2f" % [aname, (data["anims"][aname] as Array).size(), bones.size(), length])
	var err := ResourceSaver.save(body, BODY_OUT)
	print("  wrote %s  err=%d" % [BODY_OUT, err])

	# ── staging library ─────────────────────────────────────────────────────
	var staging := AnimationLibrary.new()
	for aname in STAGING_CALLS:
		var a := Animation.new()
		a.length = STAGING_LENGTH
		a.loop_mode = Animation.LOOP_NONE
		a.set("reset_on_save", false)
		# Method track on the director itself (mixer root = the AnimationPlayer's
		# parent = the director, so "." is correct — the R26b lesson).
		var tm := a.add_track(Animation.TYPE_METHOD)
		a.track_set_path(tm, NodePath("."))
		for call in STAGING_CALLS[aname]:
			a.track_insert_key(tm, float(call[0]), {"method": call[1], "args": []})
		# Scare-light flash curve (the node keeps its authored colour/energy).
		var tl := a.add_track(Animation.TYPE_VALUE)
		a.track_set_path(tl, NodePath("JumpscareLight:light_energy"))
		a.track_set_interpolation_type(tl, Animation.INTERPOLATION_LINEAR)
		a.track_insert_key(tl, 0.00, 0.0)
		a.track_insert_key(tl, 0.05, 9.0)
		a.track_insert_key(tl, 0.35, 3.2)
		a.track_insert_key(tl, 1.15, 7.5)
		a.track_insert_key(tl, 1.60, 2.6)
		a.track_insert_key(tl, 2.70, 4.0)
		a.track_insert_key(tl, 3.60, 1.4)
		a.track_insert_key(tl, 4.30, 0.0)
		staging.add_animation(aname, a)
		print("  stage %-12s %d calls, len=%.2f" % [aname, (STAGING_CALLS[aname] as Array).size(), STAGING_LENGTH])
	err = ResourceSaver.save(staging, STAGING_OUT)
	print("  wrote %s  err=%d" % [STAGING_OUT, err])
	print("BUILD_DONE")
