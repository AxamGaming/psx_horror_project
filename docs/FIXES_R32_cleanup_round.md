# R32 — Cleanup round: flakes, enums, renames, dedupe

Round 32 is the STATE.md agenda executed end to end. No gameplay behaviour
changed except where noted; every item lands with its regression guard or a
suite run that proves it.

Test totals after this round: **kill 43/43, noise 47/47, proximity 23/23,
ai 0 failures, fly 5/5 — all five green in one pass** (proximity was
permanently red on A8 before this round).

---

## 1. The settings.cfg flake is dead

**Symptom.** `jumpscare_selftest.gd` K3 failed on machines where a previous
session left `camera_shake=0.0` in `user://settings.cfg`.

**Root cause.** K10 (phase 6) drives `camera_shake`/`kill_fx` to 0 and restores
them only in phase 7. Settings persist on every change, so a run killed inside
K10 — or a player who saved shake 0 — leaves a cfg that zeroes the whip before
K3 executes on the next run.

**Fix.** Phase 0 frame 1 resets all four dials (`set_camera_shake(1.0)`,
`set_kill_fx(1.0)`, `set_gore(1.0)`, `set_reduce_flashes(false)`). The setters
save, so the suite is self-healing: a bad cfg is overwritten on boot.

**Guard.** K3/K10 themselves: with the reset, K3's whip+flash assertions can
no longer see a stale zero, and K10 still proves the gating works from a
known-good baseline.

## 2. Heartbeat policy: the asset is canonical

**Decision (asked, answered).** Keep the shipped 1.9087 s `heartbeat.wav`;
update the test. A8 now asserts `1.5 < dur < 2.2` ("~1.9 s lub-dub").
`docs/PROXIMITY_MONITOR_DESIGN.md`'s troubleshooting note, which quoted the
earlier 0.75 s trim, now quotes the shipped length and this policy.

**Guard.** A8 itself, green at 1.91 s.

## 3. CHANGELOG.md

New root file: every delivery phase (0–12) and fix round (R5, R16, R17, R22,
R23, R24, R26–R31, R32) with a one-paragraph summary and a pointer to its doc.
Code-only rounds (R17, R22) are marked as reconstructed from `BUILD_TAG`,
code comments and git history.

## 4. Enum migration (with a wire-compatibility rule)

- `NightmareCreature.TaskTag {NONE, PATROL, INVESTIGATE, CHASE, SWIPE, LUNGE,
  RECOVER, SET_ALERT, FEEDING}` replaces the free String tag.
- `SurvivalSystem.DamageSource {NONE, CREATURE}` replaces `"creature"` / `""`.

**Wire-compatibility rule (new convention).** Human-readable surfaces keep
their historical strings: `TASK_TAG_LABELS` + `task_tag_name()` feed the
creature log, `debug_state()["task"]`, the debug panel and `ai_selftest`'s
`task.begins_with("Act")` probes, so nothing downstream of a `%s` changed.
An enum printed with `%s` is its int — every log reader goes through
`task_tag_name()`.

**Callers updated.** 7 BT `act_*` tasks, `CreatureNavigator` comparisons and
logs, the combat-window check, `_tag_damage_source()`, survival's death
router and respawn reset, `debug_state()`.

**Guard.** `ai_selftest` P-probes read the labels every frame; the full ai
suite is green.

### 4b. The `-s` compile-order trap (found by this migration)

Naming `SurvivalSystem` inside `ai_selftest.gd` (to pass
`DamageSource.NONE`) added `survival.gd` to the suite's compile-time
dependencies. Under `-s`, dependency chains compile **before autoloads are
registered**, so `survival.gd`'s bare `Events` identifier failed
(`Compile Error: Identifier not found: Events … survival.gd:51`) and the whole
suite died — surfacing as bogus `P7a/P7b` feeding failures while every other
phase "passed" from a half-booted harness.

**Rule added to conventions:** self-tests run via `-s` must not reference
autoload-dependent classes at compile time; pass enum values **by value**
with a comment (`sv.set("last_damage_source", 0)  # DamageSource.NONE`).

## 5. `movement.gd` → `player_movement.gd`

`git mv` of the script and its `.uid` (uid unchanged: `uid://bu6nqad5fsfn4`),
`player.tscn` ext_resource path refreshed, live code/doc comments updated.
Historical round logs keep the old name as a record of their round.

**Gotcha worth remembering:** a renamed script leaves the staged `.godot`
uid-cache pointing at the old path, which silently drops the player at boot
in headless runs. The workspace test runner now runs `--import` after every
sync; in the editor a rescan does the same.

## 6. Jumpscare doc archived

`docs/JUMPSCARE_SYSTEM.md` → `docs/archive/JUMPSCARE_SYSTEM.md` with an
R32 banner above the title pointing at the live `KILL_SEQUENCE_R30.md`.

## 7. `ui_draw_util.gd`

`_rounded_points()` / `_closed()` existed byte-identical in
`noise_meter_bar.gd` and `proximity_trace.gd`. Both now live in
`UiDrawUtil` (static funcs, `class_name UiDrawUtil`); the widgets call
`UiDrawUtil.rounded_points()` / `UiDrawUtil.closed()` and keep their own
`_draw()`, so the UI-de-hardcoded convention is untouched.

**Guard.** noise 47/47 and proximity 23/23 exercise both widgets' draw paths
every frame of their capture windows.

---

## Files touched

| File | Change |
|---|---|
| `tests/jumpscare_selftest.gd` | Settings reset at phase 0; `set`/`set2` locals renamed `stg`/`stg2` (gdtoolkit rejects `set` as an identifier) |
| `tests/proximity_selftest.gd` | A8 bound 1.5–2.2 s |
| `tests/ai_selftest.gd` | damage-source tag cleared by value (4b) |
| `scenes/enemies/nightmare_creature.gd` | `TaskTag` enum + `TASK_TAG_LABELS` + `task_tag_name()`; all tag sites |
| `scenes/enemies/creature_navigator.gd` | enum comparisons, `task_tag_name()` in logs |
| `scenes/enemies/tasks/act_*.gd` (7) | `set_task_tag(NightmareCreature.TaskTag.*)` |
| `scenes/player/survival.gd` | `DamageSource` enum, router + reset |
| `scenes/player/player_movement.gd` | renamed from `movement.gd` (+ `.uid`) |
| `scenes/player/player.tscn` | ext_resource path refreshed |
| `scenes/ui/ui_draw_util.gd` | new shared draw helpers |
| `scenes/ui/noise_meter_bar.gd`, `scenes/ui/proximity_trace.gd` | local helpers deleted, calls rewired |
| `CHANGELOG.md` | new |
| `docs/archive/JUMPSCARE_SYSTEM.md` | moved + banner |
| `docs/PROXIMITY_MONITOR_DESIGN.md` | heartbeat length note |
| `STATE.md` | R32 bump |

No assets, scenes or resources changed beyond the rename; nothing to
re-import except what the rename itself invalidates (uid cache, see §5).
