#!/usr/bin/env python3
"""verify_r16.py -- proof that Round 16 landed. Run from the project root."""
import os, re, sys
fails = []
def ok(c, l, h=""):
    if c: print("  PASS  %s" % l)
    else:
        print("  FAIL  %s%s" % (l, ("\n          -> " + h) if h else "")); fails.append(l)
def read(p): return open(p, encoding="utf-8").read() if os.path.exists(p) else None
cre = read("scenes/enemies/nightmare_creature.gd")
inv = read("scenes/enemies/tasks/act_investigate.gd")
ok(cre and inv, "R16 files present")
if not (cre and inv): sys.exit(1)
mtp = cre[cre.index("func move_toward_point("):cre.index("## What is directly in front of us")]
phys = cre[cre.index("func _physics_process("):]
print("\n[R16-1] version")
ok(re.search(r'const BUILD_TAG := "R16"', cre) is not None, "BUILD_TAG = R16")
print("\n[R16-2] one steering core (reference pattern)")
ok("velocity.x =" not in mtp, "move_toward_point no longer writes velocity",
   "ten velocity writers was the root of the glitching; tasks now only set a target")
ok("_nav_finished = _nav.is_navigation_finished()" in phys
   and "var wp: Vector3 = _nav.get_next_path_position()" in phys,
   "physics steers from the current path waypoint every frame")
ok("_want_move and _nav_finished and (_nav_goal - global_position).length() < 1.0" in mtp,
   "arrival = distance OR navigation finished near the (snapped) goal")
ok("set_physics_process(false)" in cre and "await get_tree().physics_frame" in cre,
   "first move waits for the navigation map to synchronise (reference _ready)")
print("\n[R16-3] vision is a physical eye ray")
ok("_eye_ray = RayCast3D.new()" in cre and "_eye_ray.force_raycast_update()" in cre,
   "eye RayCast3D with force_raycast_update")
ok("_eye_ray.collision_mask = 17" in cre, "eye ray mask 17 (world+doors, player excluded)")
print("\n[R16-4] anim/hit sync + search")
ok("_attack_anim_done or _windup_t >= windup_time * 2.0" in cre
   and "func _on_anim_finished(" in cre, "windup ends on animation_finished")
ok("func search_point_near(" in cre and "_search_left" in inv,
   "investigate sweeps search points around last-known position (reference Searching)")
print("\n[R16-5] arrived-standing is not 'stuck'")
ok("not _nav_finished and (_real_hspd < 0.2 or _jammed)" in cre, "stuck/unstick ignore arrival")
ok("not _nav_finished and (_real_hspd < 0.1 or _jammed)" in cre, "pinned ignores arrival")
print("\n[R16-6] nothing eaten by the restructure")
for fn in ["func hears_player(", "func clear_path(", "func _forward_collider(",
           "func stop_move(", "func _try_unstick(", "func play_gait(",
           "func is_amnesiac(", "func forget_player(", "func search_point_near(",
           "func _on_anim_finished(", "func dist_to_player(", "func player_pos("]:
    ok(fn in cre, "%s still present" % fn.strip()[:-1],
       "R16's span replacements must not delete neighbouring functions")
print("\n[R16-7] earlier rounds intact")
ok("_jam_t" in cre, "R13 jam detector")
ok("_eye_ray.collision_mask = 17" in cre, "door-aware LOS")
ok("baker_ok" in cre, "R15 fail-ladder gate")
ok("NavigationServer3D.map_create()" in read("scenes/level/nav_baker.gd"), "R14 dedicated map")
funcs = re.findall(r"^func (\w+)\(", cre, re.M)
ok(not [f for f in set(funcs) if funcs.count(f) > 1], "no duplicate funcs")
print("\n" + "=" * 66)
if fails:
    print("%d CHECK(S) FAILED:" % len(fails)); [print("   - %s" % f) for f in fails]
    print("=" * 66); sys.exit(1)
print("ALL R16 CHECKS PASS")
print("Next log: expect far fewer diag/unstick lines; investigate shows 2-3 short")
print("hops (search points) then a dwell; swipes land exactly when attack_1 ends.")
print("=" * 66)
