# R16 — Creature AI / Orientation / Animation Fix Pass

Everything below was validated headlessly on Godot 4.7.2 (the project's engine
version) with `tests/ai_selftest.gd`, a scripted 123-second scenario that boots
`corridor_level.tscn` with a virtual player and asserts each fix. Last run:
**22/22 PASS, 0 FAILURES** (4 consecutive clean runs).

Re-run the self-test any time with:

```
godot --headless --path . --fixed-fps 60 --quit-after 12000 -s res://tests/ai_selftest.gd
```

---

## 1. "It sees me when its back is turned / glides at me showing its backside"

**Two stacked root causes:**

1. **The GLB model faces +Z, but every AI system treats the body's −Z as
   forward** (FOV cone in `creature_awareness.gd`, steering, facing). The
   `ModelRoot` node was *documented* as carrying the orientation correction —
   but its transform was identity. So the creature visually faced **away**
   from everything it "looked at": it locked onto you while showing you its
   back, ignored you while apparently making eye contact, and moonwalked
   through chases.
2. **The yaw formula was inverted to compensate.** `rotation.y =
   atan2(dir.x, dir.z)` aligns the body's **+Z** with the travel direction —
   which made the mesh walk forwards but pointed the FOV cone *backwards*
   along the movement path. The creature literally perceived the world behind
   it.

**Fix** (`nightmare_creature.tscn` + `nightmare_creature.gd`):

- `ModelRoot` rotated 180° about Y → mesh face = body −Z = AI forward.
- Facing now uses `atan2(-dir.x, -dir.z)` so −Z (face **and** FOV) leads
  movement.
- **Combat facing**: while winding, lunging, feeding — or whenever the player
  is visually confirmed within `combat_face_range` (3.2 m) — the body turns
  toward the player instead of the steering direction. Swipes/bites now
  always face their target; the "glides in backwards, corrects only when it
  attacks" behavior is gone.
- Default `sight_fov_deg` raised 75° → 90°: with the mesh finally facing
  where it looks, 90° matches the visible head sweep (sneaking up behind it
  still works).

## 2. Head collider vs. doors ("now it can't go through the doors")

To answer the question directly: **no — the vision rays never used the head
collider.** LOS rays fire from four torso offsets (y 1.5/1.75, x ±0.2) and
exclude the creature's own body. The head `CollisionShape3D` was pure
*physics*, and moving it out to the visible head (z ≈ 1 m, y 1.72, r 0.32)
broke locomotion in two ways:

- Its top (1.718 + 0.32 = **2.039**) intersected every door **lintel
  (underside y = 2.0)** — the creature could physically never pass a doorway.
- The 1 m snout snagged door posts, corridor walls and the barrels whenever
  the body rotated (the collision hull became ~1.8 m long while nav baked for
  a 0.45 m radius).

**Fix** (`nightmare_creature.tscn` + `weapon_system.gd`):

- Head is now `HeadHitbox`, an **Area3D** (layer 2, mask 0, non-monitoring)
  at the mirrored head position `(−0.088, 1.718, −0.997)` — in front now that
  the model is flipped. It **blocks nothing** but keeps the head as a valid
  pellet target.
- Shotgun pellets now test areas too (`collide_with_areas`), with a bounded
  re-cast that skips non-damageable areas (door triggers, crawlspace zone) so
  invisible trigger volumes can never eat shots.

## 3. "Dumb" navigation around the wooden Stage (and the corridor barrels)

Three independent causes, all fixed:

1. **The Stage top (0.4 m) baked as a disconnected navmesh island**
   (`agent_max_climb` was 0.2). Any target on/beside the Stage became
   "unreachable": the goal snapped onto the island, the path ended at the
   Stage foot, and the steering fallback rammed the side forever.
   → `nav_baker.gd`: `agent_max_climb` **0.6** (0.4 hit float truncation in
   the voxel conversion and stayed disconnected — measured). The Stage now
   merges with the floor mesh; crates (1 m) and barrels (0.93 m) remain
   obstacles.
2. **The "is the lane clear" steering ray ran at chest height (y+0.7) and
   flew straight over the 0.4 m Stage** → "clear!" → full-speed body-check.
   → lowered to **y+0.3** in both `creature_navigator.gd` and
   `nightmare_creature.gd` (`clear_path`, also used by `CondCanLunge`).
3. **No physical way to climb 0.4 m** even when the path led over it.
   → new **step assist**: when a commanded move is wall-blocked and the
   obstacle is ≤ `step_height` (0.5 m) with landing headroom, the creature
   hops up (`jump` anim, physics parabola). It now climbs onto the Stage
   after you — and hop-attempts against too-tall geometry are rejected.

Plus navigator hardening:

- **Prowl mode**: when the travel goal is genuinely unreachable (player in
  the crawlspace/spawn room, on an unclimbable crate) and the body has
  arrived at the closest reachable point (the *cached end of the partial
  path* — flicker-proof), it circles that point at half speed, flipping
  direction every 2.8 s, instead of grinding face-first into geometry. After
  1.4 s of prowling, `travel_to()` reports *arrived*, so Investigate proceeds
  to its search-point/dwell/sniff phase (calm, creepy behavior at the
  crawlspace mouth) and Patrol skips the point — this kills the R15 log's
  Investigate↔Patrol↔SetAlert flip-flop churn. Prowling never counts as
  stuck/jammed/nav-failed, and vetoes lunges (`CondCanLunge`).
- **`held_dir` ratchet removed**: a stale held heading could only be reused
  while fresh (<0.5 s) *and* physically clear; otherwise the body now pushes
  toward the goal and lets `move_and_slide` scrub it along the wall into the
  gap (this is what made it surf into the hall corner instead of the doorway,
  and what now makes the closed-door case pin properly so `force_open`
  fires).
- **`_unstick_fails` reset bug fixed** (pre-existing): the ladder ended with
  `if not stuck: clear_t = 0`, which zeroed the recovery timer on *every
  healthy frame* — fails never decayed, so after ~4 lifetime fails every
  later episode jumped straight to fail=3→GIVEUP. Now 1.5 s of genuinely
  free movement clears the ladder.
- Always snap unreachable targets to the closest navmesh point (the old
  3 m gate left `_nav_reachable` paradoxically `true` for far-off targets and
  bypassed the whole give-up/prowl machinery), and arrival checks use flat
  distance (the 3D check never fired when the goal sat 0.4 m up on a ledge).
- `corridor_level.tscn`: both corridor barrels nudged 8 cm into their walls,
  widening the barrel/wall squeeze from ~0.23 m to ~0.31 m (the nav strip and
  the physical capsule window now match).

## 4. Lunge ↔ chase glitches

- **Distance-scaled lunge**: duration = `clamp((dist + 0.6) / 7.5, 0.22,
  0.55)` — no more 4.1 m dash overshooting a 2.2 m pounce and moonwalking
  back.
- **Early-out on contact** (+0.14 s follow-through) and **wall-block abort**
  (0.1 s of head-on wall contact ends the dash, half cooldown).
- **Animation chain**: `jump` plays during the dash; on contact it cuts to
  `bite`; a 0.35 s anim latch after landing lets clips finish instead of
  snapping to Run mid-frame. Facing follows the lunge direction.
- **No more machine-gunning**: a landed swipe now bumps the lunge cooldown
  (0.9 s) — the old code let knockback drop you at exactly lunge range for a
  free instant lunge every swipe (log: `SWIPE HIT dist=2.29` → `LUNGE START
  dist=2.34` 16 ms later); landing a lunge bumps the swipe cooldown (0.55 s).
- Depenetration is a **smooth push** (≤7 m/s) instead of a 1-frame teleport.

## 5. Attack animation glitch at point-blank

- Swipes strike **when the chosen swing clip actually ends** (0.83–1.04 s,
  `animation_finished`-driven) with a small safety cap, and a 0.3 s post-hit
  anim latch holds the follow-through pose — the clip is never cut mid-swing
  by the gait selector anymore.
- **Swipes randomize between `attack_1` / `attack_2` / `attack_3`.**
- Wake roar / recover roar / defence startle now **hold their clip** (the
  react latch also gates attacks — previously a point-blank wake started
  WINDUP *1 ms* into the roar and cut it after one frame).

## 6. All 22 GLB animations are now used

| Animation | Where it plays |
|---|---|
| `idle` | asleep |
| `walk` / `Run` | patrol / investigate / chase gaits (speed-scaled) |
| `battle_idle` | combat standoff, pinned, investigate dwell |
| `attack_1/2/3` | randomized swipe variants |
| `jump` | lunge dash **and** step-up ledge hops |
| `bite` | lunge contact chomp |
| `roar` | wake (70%), recover get-up |
| `defence` | wake startle (30%), downed flinch variant |
| `hit_1` / `hit_2` | downed flinch variants (played fast) |
| `death_1` / `death_2` | randomized knockdown |
| `state_to_crawl` | collapse into the downed crawl pose (also starts feeding) |
| `crawl_idol` | downed loop (no more blank/frozen AnimationPlayer for 20 s!) |
| `crawl_bite` | downed snap when you stand over it (scare, no damage, budgeted so it can never collide with the get-up) |
| `crawl_to_state` / `crawl_to_state_001` | randomized get-up before recover (note: the importer renames `.001` → `_001`; `_resolve()` now tolerates that) |
| `crawl` | crawls toward your body after killing you |
| `eating` | feeds on the body (loops) until you respawn |

Downed sequence: **flinch → death → state_to_crawl → crawl_idol loop (growls,
snaps) → crawl_to_state get-up timed to land exactly at `neutralize_time` →
recover roar → amnesiac patrol.**

Feeding sequence (new): on `Events.player_died` the BT parks, the creature
drops to all fours, crawls to the body and eats; `player_respawned` snaps it
out (amnesiac). Getting shot mid-feed cancels cleanly and re-arms the BT so
the neutralize/recover loop still works.

## 7. Other fixes found by the self-test

- **Deleted 5 stale PascalCase task duplicates** (`CondSeesPlayer.gd`,
  `ActChase.gd`, `ActInvestigate.gd`, `CondHasAlert.gd`,
  `CondHearsPlayer.gd`) that shadowed the real snake_case files' `class_name`
  registrations and called a removed API (`get_memory()`). On
  case-insensitive file systems (Windows/macOS) git silently merged each pair
  into one file — a checkout-order landmine; on Linux the *stale* copy won
  registration and the entire combat branch died. The snake_case files are
  now the single canonical copies (each carries a marker comment so
  case-insensitive pulls re-materialize them correctly).
- `_clamp_to_ground()` no longer teleports the body **0.9 m into the air**
  (the body origin is at the feet; the old `gp.y + 0.9` snap would have fired
  on every stage hop) and never fires during an intentional hop/ascent.
- Amnesia startle: the post-recover 5 s daze ignored you even at biting
  distance ("walks right past me"); now proximity + LOS within
  `proximity_range * 0.75` ends the daze early (`startle()`).
- `player.tscn`: fixed the stale `footsteps.gd` UID (pre-existing import
  warning).

## Tunables added (inspector, on the creature)

`step_height` (0.5), `combat_face_range` (3.2), `downed_snap_range` (1.7),
`feed_speed` (1.6), plus exports for every new animation clip name.

---

# R17 — post-playtest pass (from the first real-play creature_log)

The R16 playtest log confirmed everything mechanical (stage hops, door
force-opens, downed snaps, full feed cycles, zero NAV DEAD / void resets) and
exposed the remaining "animation state changing glitches". Five fixes, one of
them fundamental:

## THE BIG ONE: the NavigationAgent was never on the baker's map
`creature_navigator.gd` bound the agent with
`NavigationServer3D.agent_set_map()` — a **server-side-only** call. The node's
cached map RID (`get_navigation_map()`, used by every path query the agent
makes) stayed on the **empty default world map**. Result:
`get_current_navigation_path()` was always `[]` and `get_next_path_position()`
always returned the agent's own feet — the creature never followed a nav path
at all; every "navigation" behavior since R13 was the straight-line/held-dir/
unstick fallback compensating (this is also what R13's "frozen waypoint"
investigation was circling).
→ Fixed with `_nav.set_navigation_map(baker.get_map_rid())` (sets server
binding **and** node cache). Real waypoint steering, honest
`is_target_reachable()`, real closest-point snaps and prowl centres followed
immediately — the STEERDBG telemetry (new, 1 Hz while pinned) shows `wp` ≠
`pos` and stable reachability for the first time.

## Animation transition glitches (the playtest report)
- **Blank/frozen pose while running** (`anim=` lines at 4.6 m/s): the flat
  0.3 s post-swipe latch held *nothing* because the strike fires exactly at
  clip end. The latch is now the clip **remainder** (0 when the clip already
  finished), and a **blank-anim watchdog** re-starts the correct gait the
  instant nothing owns the AnimationPlayer.
- **battle_idle at full sprint**: the pinned→battle_idle conversion now
  requires the body to actually be near-stationary (`real_hspd < 0.6`), and
  prowl hysteresis (below) keeps the jam/pinned detectors from poisoning it.
- **Recover roar cut by battle_idle ~0.3 s in**: the react latch used to allow
  "non-locomotion" swaps; ActChase's point-blank standoff swapped the roar
  out. The startle telegraph now holds its clip against *everything*.
- **Hard cuts everywhere**: every clip switch crossfades over 0.12 s
  (`AnimationPlayer.play(res, ANIM_BLEND)`) — jump→Run, attack→battle_idle,
  walk→Run all blend now.

## Prowl stability + telemetry
- **Hysteresis**: enter immediately, leave only after the entry condition has
  been false for 0.45 s straight (reachability and the 1.7 m gate both flutter
  frame-to-frame near mesh edges — the playtest log had 2228 PROWL lines; now
  ~5 per session).
- Log rate-limited to 1 per 3 s, and `stop()` no longer resets that cooldown
  (it re-spammed once per swipe cycle).
- Blocked orbits (crawlspace mouth) now **face the unreachable point** instead
  of the tangent — it watches the hole you vanished into.

## Doorway pocket escape (deterministic regression test added)
The playtest + flaky runs showed the creature wedging between the **open**
Door2 blade tip and PostA (0.4 m west of the walkable strip), oscillating on
fixed right/left strafes. Fixes:
- Unstick strafe is now **direction-aware**: both flanks are ray-sampled and
  it strafes toward the OPEN side first (mirror on fail 2); fail 3 peels off
  along the **wall contact normal** instead of the heading; strafes lengthened
  0.45 s → 0.6 s (≈1.3 m — enough to clear the pocket).
- `force_open()` is no longer "attempted" on an already-open door (it silently
  no-oped while consuming the whole unstick attempt and arming the 4 s door
  cooldown).
- Waypoint steering skips path points within 0.35 m of the body — with real
  paths now flowing, priority-1 corner steering aims at the doorway strip
  instead of collapsing to a straight push into the post corner.
- `tests/ai_selftest.gd` now teleports the creature into the exact pocket at
  t=60 every run (deterministic repro), and P5 asserts the real requirements:
  unwedge → come through Door2 → search the corridor side, max stall < 3 s.

**Validation:** 7 consecutive headless runs, 0 failures (22/22 each).

---

# Debug Fly / Noclip (F key)

- The `debug_fly` input action toggles free-flight noclip. (Shipped as F with
  the flashlight on G; the project has since been **rebound by AxamGaming to
  fly = G, flashlight = F** — everything keys off the action, so rebinding in
  Project Settings → Input Map always works.)
- While flying: **WASD** moves along the camera axes (full 3D, pitch
  included), **SPACE** rises, **C/CTRL** descends, **SHIFT** boosts
  (8 m/s → 20 m/s). Exports on the Player body: `fly_speed`,
  `fly_sprint_multiplier`, `fly_acceleration`.
- True noclip: `collision_mask` drops to 0 and the body integrates position
  directly (no `move_and_slide`) — you can hover inside walls/the Stage and
  nothing pushes you. Toggling off restores the mask and normal physics; if
  you're inside geometry, Godot's depenetration expels you (tested: parking
  inside the Stage pops you onto its top).
- Observer mode: while flying you are silent (`noise_level = 0`), emit no
  footsteps, drain no stamina — the creature can still SEE you (useful for
  testing its FOV/vision from odd angles). Dying mid-flight restores
  collisions so the corpse settles instead of falling through the world.
- Lives inside `movement.gd` on purpose (single-writer rule: only that script
  writes player position/velocity). Debug panel (F2) shows `PLY ... FLY`.
- Verified by `tests/fly_selftest.gd` (5/5, incl. a real injected F keypress,
  in-Stage noclip parking, and mask restore/expulsion on exit):
  `godot --headless --path . --fixed-fps 60 --quit-after 900 -s res://tests/fly_selftest.gd`

---

# R18 — sound/animation sync pass (from playtest logs 2–4)

Diagnosed from the attached session logs:

- **Roar out of sync** — the real culprit: `creature_roar.wav` was **10.54 s**
  (quiet 2 s build, main vocal peaking at 3–5 s, long tail) while the roar
  *animation* is 1.875 s. The big roar was audibly landing while the creature
  was already walking/patrolling/attacking — on wake, on recover, AND on every
  lunge. → Trimmed in place to a **1.85 s** clip (vocal rise → peak → decay,
  5 ms fade-in / 300 ms fade-out) whose envelope now matches the animation
  beat-for-beat. The original 10.5 s file is preserved in git history
  (baseline commit) if you ever want it back.
- **Roar voice can never outlive the roar pose** — a generic guard stops the
  Roar player the instant the animation moves on (recover roar cut by a second
  shot, etc.). Mid-lunge the roar is a battle cry over the jump→bite combo, so
  it gets a 1.2 s grace window after the dash instead of an instant cut.
- **Roar/defence startle poses now hard-cut (blend 0)** — the 0.12 s crossfade
  delayed the mouth ~7 frames behind the audio. Locomotion transitions keep
  the smooth blend.
- **"Weird animation change when it's shot"** — knockdown flinches played at
  1.4×/2.2× speed (twitchy). Now natural speed: hit_1/hit_2 0.62 s, defence
  1.25 s. The 25 s down window absorbs the slower chain fine.
- **Footsteps follow the actual clip**: run ≈0.38 s/footfall, walk ≈0.6 s,
  crawl (feeding approach) ≈0.42 s, each divided by the anim speed scale.

Full SFX↔state audit (all verified against the wav envelopes):
| Sound | Fires with | Sync |
|---|---|---|
| roar (1.85 s) | wake pose, recover get-up pose, lunge launch | attack at ~0.05 s = anim start; guard-cut at pose end |
| growl (0.73 s, onset 0.0) | windup start, swipe contact, lunge contact, downed snap, downed idle (4–7 s), feeding | one-shot, synced at trigger frame |
| screech (1.92 s, onset 0.0) | taking the shot (flinch start) | intentional tail through the collapse |
| step (0.45 s) | footfall cadence per gait | cadence table above |

- **Vertical attack gates** (from log 2: 14 lunges / 0 hits against a
  debug-flying player): swipes and lunges now require |Δy| < ~1.6 m — the
  creature no longer swings or dash-rams at targets hovering far above it; it
  prowls below instead. Stage-height (0.4 m) combat and jumps are unaffected.

Log health from your sessions: no NAV DEAD, no VOID RESET, no engine errors
(only the intentional SELFTEST warning line), downed-chain timing exact
(GETUP at 23.7 s, RECOVER at 25.0 s, snap budget respected), STEERDBG entries
transient (normal cornering), door force-opens working.

**Validation:** fly suite 5/5, AI suite now 24 assertions (incl. P6f roar
voice-during-pose and P6g voice-cut-after-pose), 5 consecutive 0-failure runs.

---

# R19 — point-blank animation glitches (from the kiting-combat playtest log)

Three distinct close-range glitches, all visible in the session log
(`ActSwipe vreal=2.17`, `LUNGE START 8290 → WINDUP 8457`, 2.2 m/s jitter
while net displacement ~1.3 m/s):

1. **Skating swings** — `start_windup()` called `nav.stop()`, but the
   velocity watchdog deliberately skipped winding frames, so *nobody* zeroed
   velocity.x/z: the chase (or unstick-backoff) speed bled through the entire
   ~1 s attack pose and the creature slid across the floor mid-swing.
   → Windup now plants the feet (velocity zeroed at start *and* cancelled),
   and the watchdog no longer exempts winding (lunges still own their
   velocity — they are agent-driven animation physics).
2. **Jump→attack snap on an aborted lunge** — a one-frame vision flicker
   mid-dash aborted the lunge, and `cancel_lunge()` charged no attack lockout
   and no anim hold, so the very next tick insta-wound-up: jump pose cut to a
   swing 0.16 s in. → Aborted lunges now hold the jump/landing pose 0.35 s
   and lock the swing out for 0.45 s.
3. **Standoff flapping** — at point-blank the distance oscillates around
   `attack_standoff` (depenetration pushes + knockback + a kiting player),
   and ActChase's hard `dist <= 1.35` test flipped `stop+battle_idle` ↔
   `run+Run` every tick. → Hysteresis: enter standoff at 1.35 m, leave only
   past 1.70 m.

New continuous harness detectors (run over the WHOLE scenario, not windows):
- **P9**: any frame with commanded horizontal velocity while `is_winding()`
  is a violation — 0 tolerated. (Pre-fix logs would trip this constantly.)
- **P10**: animation flip-rate while awake within 1.8 m of the player must
  stay < 5/s (flapping measured ~0.5/s post-fix; the bug regime is ~30/s).

Validation: ai_selftest 26/26 × 3 runs, fly_selftest 5/5, import clean.

---

# R20 — hull accuracy + the crawlspace-lip wall-stare (from playtest log)

## "Faces the wall, rotates, glitches, then sorts itself out"
Captured red-handed in STEERDBG: 15 s pinned at the crawlspace mouth
(`pos=(-0.13,-0.45) dir=(0,1) onwall=true reach=true tgt=(-0.13,3.58)`)
while the player crouched SOUTH of the tunnel. Three stacked bugs:
1. **Cross-island reachability lie**: when the target sits ON navmesh but on a
   disconnected island, `map_get_closest_point` returns the target itself →
   `snapped == target` → the old `_nav_reachable = not snapped` heuristic said
   "reachable" → no prowl, just face-plant the lip. Reachability now comes
   from the agent's own `is_target_reachable()`.
2. **Knee-height rays pass UNDER low ceilings**: the 0.3 m "lane clear" ray
   flew under the 1.15 m crawlspace slab while the 1.9 m body could not.
   `clear_path` (navigator + lunge gate) now casts **two** rays: 0.3 m (low
   obstacles — Stage) and 1.6 m (overhangs — still fits 2.0 m lintels).
3. **Prowl spin-in-place**: when the partial path collapses to the agent's
   feet, the orbit centre is now a virtual point 1.2 m toward the goal — the
   creature circles/scan-faces the hole instead of pirouetting on its axis.

## Body parts clipping through walls → bone-attached convex hull
A **trimesh is not an option** on a CharacterBody3D: Godot refuses concave
shapes for character movement (they're static/area-only), and a skinned-mesh
trimesh can't follow bones without re-baking every frame. The standard
animated-character answer is implemented instead: **convex spheres riding the
actual bones** via BoneAttachment3D, built at runtime in
`_build_detailed_hull()` (no fragile .tscn paths into the GLB):
- `Head_015` sphere r=0.22 at the measured skull centre (rest top y=1.90)
- `spine_5` sphere r=0.26 covering the hunched neck/upper chest (top 1.88)
- `Hand.L/R` spheres r=0.13 — **exported but OFF by default**: hands widen
  the hull to 1.42 m and the 1.8 m corridor's barrel squeeze would become
  impassable. Enable per-level if your geometry is roomy.
- The shootable `HeadHitbox` area is reparented onto the head bone, so
  pellets track the animated skull instead of a fixed point.
- Every piece is logged at spawn (`HULL ...` lines with rest position + top
  height) so misplacement is visible in creature_log.txt immediately.
- Inspector toggles on the creature: `hull_enabled`, `hull_head`,
  `hull_neck`, `hull_hands`.

## Playtesting (as requested — colliders in wrong places is the classic fail)
- New continuous detector **P11**: navigator `_pinned_t` peak over the whole
  scenario < 4 s (it counts ONLY commanded-but-not-moving; dwells/roars/
  windups don't count). Result: **max 1.6–2.3 s** across 3 runs — the tight
  spots (doorway lintel with 0.10 m head clearance, open-door blade pocket,
  barrel squeeze, Stage hops, crawlspace mouth) all clear without the hull
  catching. The user's log had a 15 s pin; pre-R17 sessions had worse.
- Full suite: 27/27 × 3 runs, fly 5/5, import clean.
- `tests/_inspect_skeleton.gd`: dev probe that dumps bone names + rest
  positions in body space (used to place the hull pieces; keep for future
  hull tuning).
- BUILD_TAG bumped to **R20** so future logs self-identify.

### R20.1 — hull tuning (owner playtest: "hands and head still clip a bit")
- Hands ship **ON** by default now, shrunk to **r=0.10** and pulled 2 cm
  inward (±0.56) onto the finger mass → the corridor barrel-squeeze alignment
  window grows from ~0.107 m to ~0.21 m. (Owner accepted that fingertips may
  still graze walls in the 1.8 m corridor — physical limit of that gap.)
- **New muzzle sphere** on the Jaw bone (r=0.16 @ y1.57, z−1.06, top 1.73):
  the visible snout/jaw extends ~0.25 m past a single skull sphere — that
  overhang was the residual head clipping.
- Skull sphere 0.22 → **0.24** (rest top 1.93 — the lintel budget limit with
  walk-bob margin; doorways re-tested 3/3 runs).
- Playtest: 27/27 assertions × 3 runs with this exact config, incl. doorway
  passage (0.07 m lintel clearance), barrel squeeze transit, Stage hops,
  door-blade pocket; max continuous pinned 1.6–2.3 s (P11).
