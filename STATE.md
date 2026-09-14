# STATE — [BUILD_TAG]

> Last updated: [YYYY-MM-DD]
> Updated by: [round number + short description]

## Current build

- **BUILD_TAG**: [R31]
- **Engine**: Godot [4.7.1].stable.arch_linux
- **Main scene**: `res://scenes/main.tscn` (boots `corridor_level.tscn`)
- **Test level for regression**: `res://scenes/levels/test_graybox.tscn` (F6 in editor)

## What's live

- Player: movement, mouse look, camera rig (gait + spring + VHS), flashlight, footsteps, survival, weapon (double-barrel shotgun)
- Creature: `NightmareCreature` on LimboAI, `CreatureAwareness`, `CreatureNavigator`, kill rig (`KillDirector` R30/R31)
- Level: `corridor_level.tscn` (spawn → door1 → corridor → crawl → door2 → hall → stage)
- UI: noise meter, proximity monitor, survival HUD, crosshair, inventory, item toast, death overlay, debug panel, settings menu
- Post: VHS shader (layer 2), kill FX (layer 4), UI crisp (layer 10)
- Audio: AudioMgr with bus panners, positional world sounds, deafness/tinnitus
- Nav: `nav_baker.gd` with own map, cell 0.15/0.2, agent_max_climb 0.6

## What's dead (deleted, safe to ignore)

- `movement_controller.gd`, `perception.gd`, `memory.gd`, `awareness_state.gd` — deleted [date], superseded by CreatureNavigator/CreatureAwareness since R16. Do not re-add.
- `jumpscare_director.gd`, `jumpscare_anim.tres`, `jumpscare_rig.tscn` — R26–R29 rig, replaced by `kill_director.gd` in R30. Docs kept in `JUMPSCARE_SYSTEM.md` for historical routing logic only.

## Known flakes (rerun once before bisecting)

- `ai_selftest.gd` P5/L2 — seed-flaky ~25-40%. Not a code bug. Rerun once if red.
- `jumpscare_selftest.gd` K3 — fails if `user://settings.cfg` has `camera_shake=0.0`. Delete the cfg or check the setting.
- `proximity_selftest.gd` A8 — expects heartbeat.wav length 0.5–1.2 s; current file is 1.91 s. Either restore the short wav or update the test bound.

## Known-benign exit noise

- `RID allocations of type '8NavMap3D' were leaked at exit`
- `ObjectDB instances were leaked at exit`
- `resources still in use at exit`
- `R16 SELFTEST _log_error path` warning
- `NAVBAKE #1 DEGENERATE -- retrying (1/2)`

All expected. Ignore.

## What's next (agenda)

1. [ ] Fix `settings.cfg` flake — have `jumpscare_selftest.gd` call `Settings.set_camera_shake(1.0)` at test start.
2. [ ] Decide heartbeat.wav: keep 1.91 s (update test) or re-trim to 0.75 s.
3. [ ] `CHANGELOG.md` — extract R-numbers and ROUND-numbers from inline comments into one file; reference `#R24` instead of retelling.
4. [ ] Enum migration: `_task_tag: String` → enum, `last_damage_source: String` → enum.
5. [ ] Rename `movement.gd` → `player_movement.gd` (matches `class_name PlayerMovement`).
6. [ ] Move `JUMPSCARE_SYSTEM.md` to `docs/archive/`.
7. [ ] Extract `_rounded_points` / `_closed` from `noise_meter_bar.gd` + `proximity_trace.gd` into shared `ui_draw_util.gd`.

## Test suites

| Suite | Expect | Command |
|---|---|---|
| jumpscare | 43 / 43 | `godot --headless --path . --fixed-fps 60 --quit-after 1600 -s res://tests/jumpscare_selftest.gd` |
| noise_meter | 47 / 47 | `godot --headless --path . --fixed-fps 60 --quit-after 8000 -s res://tests/noise_meter_selftest.gd` |
| proximity | 23 / 23 | `godot --headless --path . --fixed-fps 60 --quit-after 8000 -s res://tests/proximity_selftest.gd` |
| ai | 0 failures | `godot --headless --path . --fixed-fps 60 --quit-after 12000 -s res://tests/ai_selftest.gd` |
| fly | 5 / 5 | `godot --headless --path . --fixed-fps 60 --quit-after 900 -s res://tests/fly_selftest.gd` |

## Key docs (in order of usefulness)

- `docs/STATE.md` — this file
- `docs/FIXES_R31_*.md` — most recent fixes
- `docs/FIXES_R29_*.md` — repo repair + pocket escape + kill routing
- `docs/KILL_SEQUENCE_R30.md` — the kill system as-built
- `docs/NOISE_METER.md` — noise meter + hearing tiers
- `docs/PROXIMITY_MONITOR_DESIGN.md` — proximity monitor
- `docs/PROP_WORKFLOW.md` — how to add props
- `CREDITS.md` — every asset, every license

## Conventions (do not violate)

- **Single-writer rules**: CameraRig owns camera local transform; CreatureNavigator owns creature velocity.x/z; MouseLook owns HeadPivot pitch + body yaw; PlayerMovement owns position/velocity.
- **UI de-hardcoded**: all UI is `.tscn` scenes; scripts hold functionality only.
- **Signals via `Events` autoload**: no direct cross-system references.
- **Self-tests read live exports**: retuning in inspector changes what's asserted, doesn't break the test.
- **R-numbered docs**: each fix gets a `FIXES_R<num>_<short>.md` when the round is done.
- **No AI-generated comments in .tscn files**: Godot 4.7's tscn parser silently drops the first line after a comment inside a node block (R26d trap).

## Current questions open to Qwen

- [What's the next thing you want to build or fix? Write one line here.]
