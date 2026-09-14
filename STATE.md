# STATE — R32

> Last updated: 2026-09-14
> Updated by: R32 — cleanup round: flakes, enums, renames, dedupe (agenda from R31 fully executed)

## Current build

- **BUILD_TAG**: R32
- **Engine**: Godot 4.7.x (authored on 4.7.1.stable.arch_linux; verified headless on 4.7.2.stable in the sandbox workspace)
- **Main scene**: `res://scenes/main.tscn` (boots the corridor test loop)
- **Test level for regression**: `res://scenes/levels/test_graybox.tscn` (F6 in editor)

## What's live

- Player: `player_movement.gd` (renamed from `movement.gd` in R32), mouse look, camera rig (gait + spring + VHS), flashlight, footsteps, survival, weapon (double-barrel shotgun)
- Creature: `NightmareCreature` on LimboAI, `CreatureAwareness`, `CreatureNavigator`, kill rig (`KillDirector` R30/R31); task tags and damage sources are enums since R32
- Level: `corridor_level.tscn` (spawn → door1 → corridor → crawl → door2 → hall → stage)
- UI: noise meter, proximity monitor, survival HUD, crosshair, inventory, item toast, death overlay, debug panel, settings menu; shared draw helpers in `ui_draw_util.gd` (R32)
- Post: VHS shader (layer 2), kill FX (layer 4), UI crisp (layer 10)
- Audio: `AudioMgr` with bus panners, positional world sounds, deafness/tinnitus
- Nav: `nav_baker.gd` with its own map; cell 0.15/0.2; `agent_max_climb` 0.6

## Recent status

R32 executed the whole R31 agenda: the settings.cfg self-test flake is fixed
(suites reset `Settings` on frame 1), the heartbeat policy is settled (the
1.91 s asset is canonical, A8 follows it), `CHANGELOG.md` centralizes round
history, `_task_tag`/`last_damage_source` are enums with a wire-compatibility
label rule, `movement.gd` is now `player_movement.gd`, the dead jumpscare doc
is archived, and the duplicated rounded-rect helpers live in `ui_draw_util.gd`.
**All five self-test suites are green in one pass for the first time**,
proximity included. Full write-up: `docs/FIXES_R32_cleanup_round.md`.

## What's dead (deleted, safe to ignore)

- `movement_controller.gd`, `perception.gd`, `memory.gd`, `awareness_state.gd` — deleted in earlier rounds, superseded by `CreatureNavigator` / `CreatureAwareness` since R16. Do not re-add.
- `jumpscare_director.gd`, `jumpscare_anim.tres`, `jumpscare_rig.tscn` — R26–R29 rig, replaced by `kill_director.gd` in R30. Its doc lives in `docs/archive/JUMPSCARE_SYSTEM.md` for historical routing logic only.
- `scenes/player/movement.gd` — renamed to `player_movement.gd` in R32 (uid unchanged). Old path in notes/logs refers to the same script.

## Known flakes (rerun once before bisecting)

- `ai_selftest.gd` P5/L2 — seed-flaky around 25–40%. Not a code bug; rerun once if red.

Resolved in R32 (do not re-investigate): the `jumpscare_selftest.gd`
settings.cfg boot flake, and `proximity_selftest.gd` A8 (policy: asset
canonical, bound widened).

## Known-benign exit noise

- `RID allocations of type '8NavMap3D' were leaked at exit`
- `ObjectDB instances were leaked at exit`
- `resources still in use at exit`
- `R16 SELFTEST _log_error path` warning
- `NAVBAKE #1 DEGENERATE -- retrying (1/2)`

All expected. Ignore.

## What's next (agenda)

1. [ ] Bump or retire `NightmareCreature.BUILD_TAG` (still "R22" — six rounds stale).
2. [ ] Continue the low-noise quality pass carried from R31's open question.
3. [ ] Document the `audio_work/` gap: `tools/beats.json` + `build_kill_anims.gd` reference pose/audio python sources that are not in the repo; note where they live or vendor them.
4. [ ] Add the headless self-test commands (see table below) to `CONTRIBUTING.md`, which still says "test in the editor".

## Test suites

| Suite | Expect | Command |
|---|---|---|
| jumpscare | 43 / 43 | `godot --headless --path . --fixed-fps 60 --quit-after 1600 -s res://tests/jumpscare_selftest.gd` |
| noise_meter | 47 / 47 | `godot --headless --path . --fixed-fps 60 --quit-after 8000 -s res://tests/noise_meter_selftest.gd` |
| proximity | 23 / 23 | `godot --headless --path . --fixed-fps 60 --quit-after 8000 -s res://tests/proximity_selftest.gd` |
| ai | 0 failures | `godot --headless --path . --fixed-fps 60 --quit-after 12000 -s res://tests/ai_selftest.gd` |
| fly | 5 / 5 | `godot --headless --path . --fixed-fps 60 --quit-after 900 -s res://tests/fly_selftest.gd` |

## Key docs (in order of usefulness)

- `STATE.md` — this file
- `CHANGELOG.md` — phase/round map (new in R32)
- `docs/FIXES_R32_cleanup_round.md` — most recent round
- `docs/FIXES_R31_*.md` — footsteps / kill-start / crash weight
- `docs/KILL_SEQUENCE_R30.md` — the kill system as-built
- `docs/NOISE_METER.md` — noise meter + hearing tiers
- `docs/PROXIMITY_MONITOR_DESIGN.md` — proximity monitor
- `README/PROP_WORKFLOW.md` — how to add props
- `README/CREDITS.md` — every asset, every license

## Conventions (do not violate)

- **Single-writer rules**: `CameraRig` owns camera local transform; `CreatureNavigator` owns creature velocity.x/z; `MouseLook` owns `HeadPivot` pitch + body yaw; `PlayerMovement` owns position/velocity.
- **UI de-hardcoded**: all UI is `.tscn` scenes; scripts hold functionality only.
- **Signals via `Events` autoload**: no direct cross-system references.
- **Self-tests read live exports**: retuning in the inspector changes what is asserted without breaking the test.
- **R-numbered docs**: each fix gets a `FIXES_R<num>_<short>.md` when the round is done.
- **No AI-generated comments in .tscn files**: Godot 4.7's `tscn` parser silently drops the first line after a comment inside a node block (R26d trap).
- **Enum wire-compatibility (R32)**: cross-system tags are enums (`TaskTag`, `DamageSource`); anything human-readable (logs, debug panel, test probes) goes through `TASK_TAG_LABELS` / `task_tag_name()`, never `%s` on the enum.
- **`-s` self-tests pass enum values by value (R32)**: naming an autoload-dependent class in a `-s` script compiles it before autoloads exist and breaks its bare `Events` identifier (see FIXES_R32 §4b).
- **After renames, re-import before headless runs**: stale uid caches silently drop nodes (R32 §5).

## Current question for the next pass

- Next target: the low-noise quality pass (carried from R31), starting from
  agenda item 1 (BUILD_TAG hygiene) so round tags stop lying.
