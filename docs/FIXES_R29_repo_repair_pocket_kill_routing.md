# R29 — Repo repair: restored systems, pocket escape, kill-routing TTL

Round 29. The GitHub push (`821f317 "updated"`) contained a partial merge of the
R26–R28f jumpscare work: some files arrived intact, some were rolled back to
pre-R26 versions, and one script was left in a state that **did not compile**.
This round restored the broken systems *without touching the author's own newer
edits*, then fixed two real bugs the restored code exposed.

---

## 1. What was broken in the push (and what was done)

| File | State in `821f317` | Action |
|---|---|---|
| `scenes/enemies/nightmare_creature.gd` | **Did not compile** — called `_tag_damage_source()` (2 call sites) but the definition, `jumpscare_hold`, the R27 rig fallback and the R26 hold blocks were missing. The creature (and therefore the whole game) could not run. | Restored the full R28f version (the pushed copy was verifiably the backup minus exactly those blocks — zero author-only edits inside the file). |
| `scenes/enemies/jumpscare_director.gd` | R28e — missing the R28f duplicate-director guard. | Restored R28f (diff was exactly the 15-line guard). |
| `scenes/enemies/creature_awareness.gd` | Pre-noise-meter single-tier hearing; `noise_meter_selftest` calls `heard_quietly()` on it → suite could not pass. | Rebuilt the two-tier `_hearing_check()` + `heard_quietly()` exactly per `docs/NOISE_METER.md` §3 and the selftest's A1–A10b spec (LOUD: `dist < hear_radius * noise` above `hear_noise_floor`; QUIET: `dist < crouch_hear_range`, 0 disables). 47/47 green. |
| `scenes/enemies/jumpscare_anim.tres` | Author re-keyed in the editor (light keys 0/0.2/0.5/**0.833**, fov 94.25→65 start) and **intentionally deleted the `request_roar` method key at 0.6 s** — the lunge pose holds the face slam, no roar beat. | **R29b: author confirmed the deletion was intentional — the key stays deleted and the file is byte-identical to HEAD.** Selftest J2h was repurposed from "roar held" to "lunge charge expired" so the suite still guards the one thing `request_roar()` used to do besides the pose: `_charging = false`. (The charge also expires on its own via `_charge_left` ~0.32 s at defaults, so nothing can run away.) The director's procedural *fallback* anim (used only when no scene library is wired) still inserts `request_roar@0.60`; that path is inactive here. |

### Audit correction — `libraries/ = ExtResource(...)` is VALID

An earlier audit called the inline `JumpscareAnim` line

```
libraries/ = ExtResource("9_lib")
```

"corrupt". **It is not.** It is Godot 4.5+ editor property-path serialization
for the dictionary entry `libraries[&""]` — verified by loading
`jumpscare_rig.tscn` headless: `libs=[&""] anims=["jumpscare"]`, identical to
the long-form `libraries = { &"": ExtResource(...) }`. Do **not** "fix" this
line; both forms load the same. (This is also why the inline director needs no
`anim_name` line: the script default is `"jumpscare"` and the library key
matches.)

### Author edits deliberately preserved (flagged, not reverted)

- `prop_barrel.tscn`: `CylinderShape3D` (matches the original R24 fix text).
- `prop_static.gd`: convex-hull fallback instead of trimesh + comment trim.
- `prop_medbox.tscn`: explicit `BoxShape3D` — the R24 "known follow-up", done.
- `nightmare_creature.tscn` / `jumpscare_rig.tscn`: kill-cam `fov = 94.25`,
  light moved to the face `(−0.06, 0.99, −1.05)`, `light_energy = 0.0` scene
  default (the anim track drives 0→8→2→0 during the scare; the director also
  toggles `visible`), editor `unique_id`/`uid` attributes.
- `proximity_monitor.tscn`: `require_awake = false` + layout. The selftest was
  adapted to assert the gate MECHANISM against the authored value (asleep →
  stays lit when the gate is off) and to assert the shipped default against the
  script, not the scene. 23/23 green.
- `jumpscare_rig.tscn`: `anim_name = "jumpscare"` (explicit; equals default).

---

## 2. Bug: Door2 pocket pin became near-deterministic (P5/L2)

### Symptom

With the pushed prop colliders, `ai_selftest` P5 failed every run
(`crossed=false frac=0.00`) and L2 (crawlspace-mouth PROWL) with it. Control
run at `cf62ee1` (pre-push): 0 failures. Historical docs called P5/L2 a 25–40%
seed flake; it had become ~100%.

### Diagnosis (evidence chain)

1. Bisect over prop files: old trimesh-generated barrel colliders → P5 passes;
   primitive (cylinder OR capsule) colliders → fails. Door rebake
   (`rebake_on_door_change`) ON/OFF makes no reliable difference, and NAVBAKE
   #2 vs #3 are identical — R23's "rebake is pure cost" claim still holds.
2. The nav bake itself is non-deterministic run-to-run (229/230/231 polys with
   identical inputs). The prop collider change merely shifted WHICH partition
   comes out, and with it the path end (`_prowl_center`) the steering fallback
   walks toward: `(0.00,−0.47)` (bad seed) vs `(−1.18,−0.47)` (good seed).
3. Collision probe at the pin: the creature presses the **flat south face of
   the east door post** (`normal=(0,0,−1)`) — a head-on flat contact cancels
   all forward drive (slide has no deflection to give). The 1.8 m mouth leaves
   only ≈±0.25 m of lateral slack for the ~1 m hull; a straight-line approach
   from x≈+0.38 clips the post every time.
4. The unstick ladder then made it worse: fixed order *strafe-right →
   strafe-left → backoff*, right being the closed side here, each strafe only
   0.6 s, then steering re-pinned the same corner. After fail 4, GIVEUP
   **cleared the investigate alert** → patrol → creature wandered away → P5
   window expired with `frac=0`.

### Fix (`scenes/enemies/creature_navigator.gd::_try_unstick`)

Clearance-aware strafe: probe both tangents with the existing `_clear_path()`
(knee + shoulder rays, 1.2 m) and commit to the side that is actually open;
fail=2 flips sides, falling back to whichever tangent has clearance so lateral
offset keeps accumulating instead of re-pinning. No exports changed, no level
changed, props stay as authored.

### Result

P5 `max_stall` = 1.6 s on every run (was 2.4–3.1 s + never crossing);
`crossed=true frac≈0.48–0.66`; L2 PROWL green; **3/3 runs, 0 failures**
(previously the flake was documented at 25–40% even in the best era — it is
now more reliable than any recorded baseline).

---

## 3. Bug: stale kill-source tag routed environmental deaths into the jumpscare (P7a/P7b)

### Symptom

P7 (scripted `player_damaged(999)` = environmental death → creature must crawl
to the body and feed) failed: probe showed at the kill instant
`last_damage_source='creature'`, `jumpscare_hold=true` at t=107–108,
`feed_phase=0` throughout. The kill ran the JUMPSCARE instead (roar at t=108,
auto-respawn, combat resumed), so feeding never engaged.

### Cause

`_tag_damage_source()` stamps `last_damage_source="creature"` on **every**
swipe. The tag was only cleared on respawn. Any survived swipe left the tag
armed indefinitely, so a later NON-creature death (fall, the test's 999 event)
emitted `player_killed_by_creature` → jumpscare → kill cam welded to a
creature that did not land the killing blow. In-game this is the "I fell to my
death and got jumpscared by a creature across the map" bug. The survival
comment even states the intent ("so a later fall doesn't inherit an old tag")
— it was only implemented for respawns.

### Fix

- `scenes/player/survival.gd`: `last_damage_stamp_ms` + exported
  `kill_source_window = 2.0` s. The router emits `player_killed_by_creature`
  only while the tag is FRESH (a lethal blow lands within frames of its tag;
  2 s is generous). Respawn clears both fields.
- `scenes/enemies/nightmare_creature.gd::_tag_damage_source()`: stamps
  `Time.get_ticks_msec()`.
- `tests/ai_selftest.gd` P7: clears the tag before the scripted kill — the
  probe asserts the environmental-death path, and a swipe <2 s earlier is a
  legitimately fresh tag, so the scenario has to be set up honestly.

Jumpscare selftest still 26/26 (creature kills stamp fresh → route correctly;
J1 environmental death untouched).

---

## 4. Verification (all headless, Godot 4.7.2-stable)

| Suite | Result |
|---|---|
| `ai_selftest.gd` × 3 | **0 failures** each (P5 crossed frac 0.48–0.66, stall 1.6 s; L2 PROWL; P7a/P7b feeding) |
| `jumpscare_selftest.gd` | 26/26 |
| `noise_meter_selftest.gd` | 47/47 (incl. all 15 two-tier hearing probes A1–A10b) |
| `proximity_selftest.gd` | 23/23 (authored `require_awake=false` direction) |
| `smoke_test.sh` | PASS — booted, LimboAI, navmesh baked, no script errors |
| Scene loads | `nightmare_creature.tscn` instantiates; director logs `'jumpscare' from scene-wired library — panel edits ACTIVE` |

Known-benign exit noise unchanged: ObjectDB/RID leak lines at quit,
`R16 SELFTEST _log_error path`, `NAVBAKE #1 DEGENERATE -- retrying`.

## 5. Notes for the author

- **Resolved (R29b):** removing `request_roar` from `jumpscare_anim.tres` WAS
  intentional — the key stays deleted. Selftest J2h now asserts the lunge
  charge expires instead of the roar pose. If you ever want the roar beat
  back, re-add a method key → `request_roar` at any time in the panel; the
  director function is still there and honours panel edits.
- `kill_source_window` (SurvivalSystem) is the tuning knob for the
  creature-kill routing; 2.0 s only needs to cover "lethal blow → death check".
- The P5 pocket is now escaped deterministically, but the mouth remains tight
  (±0.25 m slack). If future level edits add geometry near Door2's south face,
  rerun `ai_selftest` (P5 catches it by design).
