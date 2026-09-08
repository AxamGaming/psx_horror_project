# Phase 12 REBUILD — LimboAI Creature

The hand-rolled state machine is **gone**. The creature now runs on
**LimboAI v1.8.1** (MIT), the Behavior Tree + HSM GDExtension you picked,
installed per its docs as a GDExtension addon (`addons/limboai/`, Linux
binaries included, `compatibility_minimum = 4.2` → works on your 4.7.1).

## Copy list

| Path | Action |
|---|---|
| `addons/limboai/` | **NEW** — the whole addon (GDExtension, editor + template .so) |
| `scenes/enemies/tasks/*.gd` | **NEW** — 13 custom BT tasks |
| `scenes/enemies/nightmare_creature.gd` | **REPLACE** — now a LimboAI agent |
| `scenes/enemies/nightmare_creature.tscn` | **REPLACE** — adds the `BTPlayer` node |
| `CREDITS.md` | **REPLACE** |

No `project.godot` change needed: GDExtension auto-loads via
`addons/limboai/bin/limboai.gdextension`; the BT editor UI appears in the
editor once it scans the addon.

## Architecture

- **`BTPlayer` node** on the creature executes a `BehaviorTree` resource that
  the agent builds in code at `_ready` (`_build_tree()`), with
  `BTPlayer.agent = self` so every task reaches the agent via `agent`.
- **Blackboard** carries shared data: `alert_pos` (investigation target, set
  by gunshots/hearing) and `see_t` (sight-confirmation timer).
- **Custom tasks** (GDScript, `@tool`, extend `BTCondition`/`BTAction`,
  `_tick(delta) -> Status`) live in `scenes/enemies/tasks/` and call agent
  methods — senses, movement, combat resolution, animation names.
- **Agent** (`nightmare_creature.gd`) keeps: exports (patrol points, ranges,
  damages, cooldowns, neutralize window, anim names), FOV+LOS sight with
  confirm time, noise-scaled hearing, 2.5D pan-bus audio, animation
  resolver + loop forcing, take_damage/neutralize/recover rules.

## The tree (as built)

```
BTSelector
├─ Sequence [ CondNeutralized, ActRecover ]        # down 25 s -> rise amnesiac
├─ Sequence [ CondSeesPlayer(confirmed),
│             Selector [ Seq[CondInSwipeRange, ActSwipe],
│                        Seq[CondCanLunge,  ActLunge],
│                        ActChase ] ]
├─ Sequence [ CondHearsPlayer, ActSetAlert ]       # noise -> alert_pos
├─ Sequence [ CondHasAlert, ActInvestigate ]       # go sniff, dwell, forget
└─ ActPatrol                                       # walk your patrol points
```

Dormant = `BTPlayer.active = false` + idle anim; first gunshot (or point-blank
sight) wakes it (`active = true`, roar, alert_pos = shot position).

## Editing the tree visually

The tree is code-built at runtime, so to *see/edit* it in LimboAI's BT editor:
run once, then in the editor select the BTPlayer → its `behavior_tree` can be
saved to a `.tres` (Resource → Save As) and edited visually from then on;
assign the saved resource back to `behavior_tree` to make it authorative.
All behavior knobs remain exports on the creature instance either way.

## Test route (same as before, now LimboAI-driven)

1. Silent walk: it patrols its ring (inspector `Patrol Points`).
2. Fire once: roar + investigate the shot point, dwell, forget, patrol.
3. Sprint near it: hears (noise × radius), investigates your position.
4. Let it confirm sight (0.4 s): chase → swipe windup tell → swipe; or lunge
   from mid-range. Damage/knockback/deafness/limp chain unchanged.
5. Empty both barrels: screech, stagger-knock, collapse at 0 hp; 25 s later it
   rises at full health and patrols with amnesia.
6. LimboAI visual debugger: editor → debugger panel shows the live tree
   execution while the game runs.
