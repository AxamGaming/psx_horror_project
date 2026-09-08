# Fix Round 5 (build tag R5) — "nothing changed" killer + anti-burial

Round 4 changed real things but produced no visible difference in your playtest.
Two possible reasons: (a) the files on your machine were stale, (b) the fixes
aimed at the wrong cause. Round 5 makes both impossible to confuse again.

## 1. Proof-of-life: BUILD_TAG
- `nightmare_creature.gd` has `const BUILD_TAG := "R5"`.
- Debug panel (F2) line 5 (magenta) starts with that tag: `CRE R5 ...`.
- `user://creature_log.txt` line 1: `=== spawn build=R5 ...`.
- If your playtest shows anything other than `R5`, the copy step missed files.
  Full stop — no more guessing.

## 2. Telemetry (the thing we never had)
- `user://creature_log.txt` (truncated per run) gets:
  - 1 Hz state line while the game runs: awake/neutralized/pos/hspeed/on_floor/
    stuck/anim/dist-to-player,
  - events: WAKE, DAMAGE, NEUTRALIZED, RECOVER, VOID RESET, GROUND CLAMP,
    WINDUP, SWIPE HIT, LUNGE START/HIT,
  - **engine errors/warnings** captured via a `Logger` subclass registered with
    `OS.add_logger()` (Godot 4.5+ API, verified against the 4.7 class reference;
    callbacks are threaded -> mutex-buffered, drained on the main thread).
    The debugger's mystery "Errors (2)" will finally appear in text form.
- Linux path: `~/.local/share/godot/app_userdata/PSX Horror Camera Systems/creature_log.txt`

## 3. Anti-burial, three belts
- **Ground clamp**: every physics frame a down-ray from above the capsule
  centre; if the first ground hit is ABOVE the centre (body inside a slab) it
  pops back on top and logs `GROUND CLAMP`.
- **Neutralized freeze**: while down, velocity is fully zeroed and
  `move_and_slide()` is skipped — a corpse can no longer slide/sink into
  geometry during the death anim.
- **Void reset** (from R4) stays, now logged.

## 4. Behaviour fixes
- Footsteps only while `_want_move and is_on_floor() and awake and moving`
  (no steps while down, sliding, lunging, stuck-sliding).
- Facing lerp separated from footstep gating (turns during lunge too).
- Point-blank proximity wake implemented in the agent (design rule: wakes on
  first gunshot OR point-blank). Previously only the gunshot wake existed,
  because the BT is dormant while asleep and `CondSeesPlayer` never ticked.
- `ActPatrol` stuck-skip now calls `clear_stuck()`; before, the hot stuck flag
  chain-skipped every patrol point on consecutive ticks.

## 5. DebugBeacon (scene node, export-toggled)
- Magenta unlit sphere at the creature BODY (y+1.8), `debug_beacon` export.
- Read a screenshot like this:
  - orb visible where the creature should be, model missing  -> mesh/anim/cull
    problem (body is fine),
  - orb under/inside the floor -> body burial (clamp log will say which push),
  - orb nowhere near patrol points -> teleport/void logic misfired (log says).

## Test protocol for this round
1. Copy the whole `psx_horror_project/` over your copy (don't merge by hand).
2. Run, press F2: magenta line must read `CRE R5`.
3. Walk to the hall, shoot it once, watch it drop, wait 26 s, watch it rise.
4. Try to reproduce the burial (shoot near walls/platform, lure it to the ramp).
5. Quit. Send `creature_log.txt` + one F2 screenshot showing the magenta lines.
