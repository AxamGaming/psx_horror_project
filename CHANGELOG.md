# CHANGELOG

Central index of delivery phases and fix rounds. Per-round detail lives in the
linked doc; this file is the map. Convention (STATE.md): every fix round gets
`docs/FIXES_R<num>_<short>.md` when the round closes — rounds marked
*(code-only)* never got one and are reconstructed from code comments,
`BUILD_TAG` and git history.

Format: newest first.

## R32 — Workspace cleanup round (2026-09-14)

Doc: `docs/FIXES_R32_cleanup_round.md`.
Self-test settings flake fixed (suite resets `Settings` on frame 1); heartbeat
asset-canonical policy (A8 bound follows the shipped 1.91 s `heartbeat.wav`);
this CHANGELOG added; `_task_tag` and `last_damage_source` migrated to enums;
`movement.gd` renamed to `player_movement.gd`; dead jumpscare doc archived;
`ui_draw_util.gd` extracted from the two trace widgets.

## R31 — Playtest fixes: ghost footsteps, rising kill start, heavy-object crash

Doc: `docs/FIXES_R31_footsteps_killstart_crashweight.md`.
Corpse no longer emits footsteps (`freeze_corpse()` + camera-rig death gate);
kill cam starts at the player's own view and FOV instead of the authored
scare pose; crash rebuilt as a thrown heavy object (bounce chain, tumble,
impact-scaled thuds); SETTLE/FADE armed by beats but entered by physics.
Kill self-test 35 → 43 checks.

## R30 — Kill sequence ("the kill, done properly")

Doc: `docs/KILL_SEQUENCE_R30.md`.
Replaced the R26–R29 jumpscare director with `KillDirector`: seven beats on
one warped clock, 12 fps stepped creature vs smooth camera, whip spring +
roll, three variants, 16-layer audio mix, CanvasLayer-4 screen FX, gore
particles/decals, accessibility dials (`Settings`), ~5 s cinematic.

## R29 — Repo repair: restored systems, pocket escape, kill-routing TTL

Doc: `docs/FIXES_R29_repo_repair_pocket_kill_routing.md`.
Restored systems lost in an earlier push; pocket-crawlspace escape routing;
TTL on kill routing so a stale kill cannot re-trigger.

## R26–R28 — Jumpscare rig era *(superseded)*

Doc: `docs/JUMPSCARE_SYSTEM.md` (archived at `docs/archive/` in R32 —
historical routing logic only; the rig itself was deleted in R30).
First directed jumpscare: `jumpscare_director.gd` + `jumpscare_anim.tres` +
`jumpscare_rig.tscn`, pocket-kill routing, self-test harness born here.
R26d: learned that Godot 4.7's tscn parser silently drops the first line
after a comment inside a node block — hence the no-comments-in-tscn rule.

## R24 — Prop trimesh collision lag

Doc: `docs/FIXES_R24_prop_trimesh_lag.md`.
"Whole game lags near that wall": props rebuilt from trimesh to simplified
collision (`PropStatic`), bake cost moved out of gameplay frames.

## R23 — Mid-chase nav rebake hitch

Doc: `docs/FIXES_R23_door_rebake_hitch.md`.
The "huge lag at the hallway wall": door-triggered nav rebakes hitched the
chase; rebake moved to `nav_baker.gd` with its own map + async probing.

## R22 — Creature build tag *(code-only)*

No dedicated doc. `NightmareCreature.BUILD_TAG` frozen at "R22"; detailed
bone-attached hull colliders and the downed/crawl chain stabilised here.

## R17 — Unstick escalation tuning *(code-only)*

No dedicated doc. `CreatureNavigator` backoff strafes lengthened
(`BACKOFF_DURATION` 0.45 → 0.6 s) after R16's unstick loop proved too twitchy.

## R16 — Creature AI / orientation / animation fix pass

Doc: `docs/FIXES_R16.md`.
The big AI rebuild: `CreatureNavigator` + `CreatureAwareness` replace the
deleted `movement_controller.gd` / `perception.gd` / `memory.gd` /
`awareness_state.gd`; orientation and gait-animation selection reworked;
self-test harness (`ai_selftest.gd`) introduced.

## R5 — Fix round 5: "nothing changed" killer + anti-burial

Doc: `README/README_FIX_ROUND5.md`.
Process round: made silent regressions visible (change-detection in tests)
and stopped fixes from being buried by later pushes.

## Delivery phases (oldest → newest)

| Phase | Doc | Delivered |
|---|---|---|
| 0–2 | `README/README_TESTING.md` | project + input map, `Events` bus, first-person movement, mouse look, graybox level |
| 3–4 | `README/README_PHASE_3_4.md` | Bob Engine v1 head-bob, spring/landing, impulse layer |
| 5 | `README/README_PHASE_5.md`, `README/README_PHASE_5_FIX.md` | PSX presentation: 640×360 SubViewport, snap filter, VHS shader; then the SubViewport input fix |
| — | `README/README_BOB_V2.md` | Bob v2: gait backbone + noise seasoning |
| — | `README/README_FOUND_FOOTAGE.md` | Bob v4: found-footage / VHS mode |
| 6 | `README/README_PHASE_6.md` | gameplay hooks, crisp debug panel |
| 7 | `README/README_PHASE_7.md` | impact system polish, damage pipeline end-to-end |
| 8 | `README/README_PHASE_8.md` | audio: footsteps, reverb probe, deafness/tinnitus, flashlight hum |
| 9 | `README/README_PHASE_9.md` | environmental triggers, wall slams, surface-aware steps |
| 10 | `README/README_PHASE_10.md` | corridor level + crisp-layer inventory |
| 11 | `README/README_PHASE_11.md` | survival loop + double-barrel shotgun |
| 12 | `README/README_PHASE_12.md`, `README/README_LIMBOAI.md` | the Nightmare Creature; then the LimboAI behaviour-tree rebuild |

Side docs (systems, not rounds): `docs/NOISE_METER.md`,
`docs/PROXIMITY_MONITOR_DESIGN.md`, `README/PROP_WORKFLOW.md`,
`README/CREDITS.md`.
