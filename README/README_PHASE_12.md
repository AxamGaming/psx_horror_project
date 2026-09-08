# Phase 12 Delivery — The Nightmare Creature

## Copy list

| File | Action |
|---|---|
| `assets/models/nightmare_creature/nightmare_creature_1.glb` | **NEW** (your GitHub source, skinned, 22 anims) |
| `audio/sfx/creature_roar/growl/step/screech.wav` | **NEW** (CC0) |
| `scenes/enemies/nightmare_creature.gd` + `.tscn` | **NEW** |
| `scenes/levels/corridor_level.tscn` | **REPLACE** (creature placed in hall + patrol ring) |
| `scenes/player/movement.gd` | **REPLACE** (`noise_level`, `apply_knockback`, "player" group) |
| `scenes/player/weapon_system.gd` | **REPLACE** (pellets call `take_damage`, emits `gun_fired`) |
| `autoload/events.gd` | **REPLACE** (`gun_fired` signal) |
| `CREDITS.md` | **REPLACE** |

## Behavior (your design answers, implemented)

**State machine:** `DORMANT → PATROL → INVESTIGATE → CHASE → WINDUP/LUNGE → NEUTRALIZED → PATROL...`

- **DORMANT** at the hall's far end, idle animation. **Wakes on the first gunshot** (`Events.gun_fired`, heard to 40 m) or point-blank sight (<2.5 m). Waking = roar + investigate the shot.
- **PATROL** walks the exported `patrol_points` ring. **Hears you**: hearing radius × your `noise_level` (sprint 1.0 / walk 0.5 / crouch 0.15 / still 0.03) — crouch-walk past it and you're a ghost; sprint and it knows from 14 m.
- **INVESTIGATE** runs to the last noise, dwells 3 s turning/sniffing, then resumes patrol. Sees you during either and **confirms over 0.4 s** (FOV cone 75° + line-of-sight ray) → **CHASE** with a roar.
- **CHASE**: runs at you, updates last-seen position; lose line-of-sight for 6 s and it falls back to investigating where you were. In swipe range: **WINDUP** (attack anim + growl tell, 0.55 s) then a 25-dmg swipe + small knockback. From 2.2–6.5 m with cooldown ready: **LUNGE** (bite anim, 7.5 m/s dash, 35 dmg + heavy knockback on contact).
- **NOT killable, per your rule**: pellets do 12 each (8-pellet cone, range-falloff by nature); at 0 health it **collapses (death anim + screech) for 25 s**, then rises at full health and resumes PATROL with **no memory of you** — your escape window. Shots also stagger-knock it 0.25 m each.
- Attacks damage you through the existing `Events.player_damaged` → impulse, daze, limp, deafness, HUD, death overlay all react for free. Knockback shoves your body via `movement.apply_knockback`.

## Audio presence

Positional 3D players on the creature: roar (wake/chase/lunge), growl (attack tells), heavy steps (cadence follows walk/run, pitched variance), screech (hurt/neutralize). You hear it hunt through the same reverb/pan bus stack as everything else.

## Test route

1. Spawn: silence. Walk the corridor — nothing (it's dormant, hall far end).
2. Fire the shotgun once → roar echoes from the hall → it investigates the shot point. Hide in the crawl or press against a corner: it dwells, turns, leaves.
3. Sprint in its earshot → it locks and chases; break line-of-sight 6 s → it gives up to your last position.
4. Let it reach you: windup tell → swipe → damage/deafness/limp chain. Get lunged: heavy knockback.
5. Empty both barrels into it: screeches, staggers, collapses; **watch the 25 s window** — run; it rises patrolling, amnesiac.
6. Crouch-walk beside it while patrolling: hearing radius ~2 m — the stealth layer works.

## Tuning (all exports on the placed instance)

**Patrol points (your walk points):** select the `Creature` node in the level
scene → inspector → `Patrol Points` array → add/edit Vector3 entries freely
(per instance!). Leave it empty and the creature auto-builds a 4-point ring
of `auto_patrol_radius` around its spawn, so patrol never dead-ends.

Speeds, hearing/sight ranges, confirm/giveup times, damages, cooldowns, `neutralize_time` (your 20–30 s window), and **every animation name** (swap `anim_attack` to `attack_2/3`, `anim_bite`, `defence`, crawl states...) — the glb's 22 animations are all reachable by string, and names now resolve even if the importer mangles them.

## Known limits (honest)

- No navmesh: straight-line seek + wall sliding. The corridor/hall geometry is simple enough; complex future levels may need NavigationRegion3D + `NavigationAgent3D` (swap is contained in `_seek`).
- Single creature instance; spawning more = place more nodes (all state is per-instance).
- No ragdoll; neutralized = death anim + amnesia timer.
