# Jumpscare System — As-Built (R26)

Implements `uploads/2026-09-12-creature-jumpscare-design.md` with the four field
decisions taken before implementation (hold-roar, functional default animation,
new CC0 stinger, VHS kept over the kill cam). Status: **built and tested**
(`tests/jumpscare_selftest.gd`, 17/17).

---

## 1. Flow (as implemented)

```
creature swipe/lunge
  → _tag_damage_source()          (nightmare_creature.gd, before each damage emit)
  → Events.player_damaged
  → rig health drops → Survival ("Survival" node) sees health01 <= 0
      ├─ last_damage_source == "creature":
      │    Events.player_killed_by_creature   ← emitted FIRST
      │      → JumpscareDirector._on_creature_kill():
      │          DeathOverlay.suppress_next()      (group "death_overlay")
      │          creature.jumpscare_hold = true    (freeze + no feeding)
      │          main cam off / CreatureKillCamera on
      │          Events.ui_wants_mouse = true      (locks MouseLook + Weapon)
      │          body process freeze
      │          stinger.play() + JumpscareAnim.play(anim_name)
      │    Events.player_died                     (overlay suppressed)
      │    → animation_finished (or respawn_timeout_sec)
      │      → _end_sequence(): cams/input/hold restored, respawn_requested
      └─ otherwise: classic death screen, R to respawn (unchanged)
```

## 2. Files

| File | Change |
|---|---|
| `autoload/events.gd` | + `player_killed_by_creature()` signal |
| `scenes/player/survival.gd` | + `last_damage_source`, routed emit, reset on respawn |
| `scenes/enemies/nightmare_creature.gd` | + `_tag_damage_source()` (swipe + lunge emits), + `jumpscare_hold` var, hold block in `_physics_process`, feeding gate in `_on_player_died`, hold clear in `_on_player_respawned` |
| `scenes/ui/death_overlay.gd` | + `_suppressed` flag, `suppress_next()`, group `death_overlay` (added in `_ready`) |
| `scenes/enemies/jumpscare_director.gd` | **new** — full controller |
| `scenes/enemies/nightmare_creature.tscn` | + `JumpscareDirector` subtree (kill cam, omni light, stinger player, AnimationPlayer) |
| `audio/sfx/jumpscare_stinger.wav` | **new** — CC0 sting (see CREDITS) |
| `tests/jumpscare_selftest.gd` | **new** — 17 checks |
| `tests/ai_selftest.gd` | P7 kill now clears `last_damage_source` first (its scenario is an *environmental* death; earlier creature hits in the session legitimately tag it) |

## 3. Deviations from the design doc (all deliberate)

1. **Input lock** uses `Events.ui_wants_mouse` (the gate `MouseLook` AND
   `WeaponSystem` already respect) plus a body process freeze. Process-flag
   locking alone would have left mouse-look and firing live during the scare.
   Previous value is saved and restored.
2. **Head bone** is an export (`head_bone_name = "Head_015"`); this rig has no
   bone called "Head". Fallbacks: any bone containing "Head", then fixed offset.
3. **Feeding is skipped on creature kills** (`jumpscare_hold` gate in
   `_on_player_died`). The per-frame feeding/gait selector would otherwise
   overwrite the scare pose next frame and film the eat animation into the kill
   cam. Environmental deaths still feed normally (ai_selftest P7 covers it).
4. **Default animation is built in code** at `_ready` when the library lacks
   `anim_name` (AnimationPlayer stores anims in libraries — the doc's
   `add_animation` call does not exist). Designer-authored animation of the same
   name in the .tscn always wins. Default: fov 90→`cam_fov` slam at 0.22 s,
   handheld shake keys 0.2–0.5 s, light 0→peak→decay→0, `request_roar()`
   method-track at 0.02 s (safe because `jumpscare_hold` freezes the selector
   that would overwrite it). Length 2.0 s.
5. **Track paths** in the default anim use `../CreatureKillCamera` etc. —
   AnimationPlayer paths are relative to the player node; cam/light are siblings.
   The method track targets `..` (the director).
6. **Survival node is named `Survival`**, not `SurvivalSystem` (the doc's lookup
   string); the tag helper and tests use the real name.
7. **Stinger**: `audio/sfx/jumpscare_stinger.wav` — TheTVBunny's
   "JumpscareSound_Remake_Freesound.wav" (Freesound 753746, CC0), trimmed to the
   1.95 s impact+decay, faded, peak-normalised to −3 dBFS mono, per the project's
   existing CC0-preview credits workflow. Row added to `README/CREDITS.md`.
8. **VHS stays on** over the kill-cam view (field decision): the scare reads as
   part of the tape.

## 4. Designer tuning surface

Inspector (on `JumpscareDirector`): `cam_offset`, `cam_fov`, `head_bone_name`,
`use_jumpscare_light`, `light_color`, `light_energy_peak`, `anim_name`,
`auto_respawn_on_finish`, `respawn_timeout_sec`, `stinger`,
`stinger_volume_db`.

Animation editor (on `JumpscareAnim`): everything timing-shaped — fov curve,
shake keys, light curve, bone poses, method calls (`request_roar`,
`_end_sequence` for custom respawn timing when `auto_respawn_on_finish = false`).

## 5. Test coverage vs design §10

| §10 item | Check |
|---|---|
| environmental death → death screen | J1, J1b |
| swipe/lunge kill → suppressed + kill cam + lock | J2, J2b–J2f, J5 |
| completes → control restored at spawn | J3, J3b–J3g |
| timeout → no softlock | J4 |
| heartbeat unaffected | buses untouched by design; stinger on its own player (J2f asserts assignment) |
| feeding parallel | intentionally changed: skipped on creature kills (see §3.3); environmental feeding covered by ai_selftest P7 |
| second kill ignored | `_active` guard (code review; first-kill-wins) |

## 6. Known pre-existing flake (NOT from this change)

`ai_selftest` P5/L2 fail on a deterministic attractor: the creature pins at the
**Door2 doorway from the hall side** (trace: `cre≈(±0.4, 0, −6.9)`, `vreal=0`,
3.1 s) waiting on the unstick/force-open ladder, so it never crosses into the
corridor inside the P5 window and never reaches the crawlspace-mouth prowl that
L2 expects. Evidence it predates R26: it appeared in runs before this system
existed, and removing the barrel collider (the only nav-affecting change since
the last clean run) does not clear it. None of R26's code is active before
death. Filed here so the next navigation pass has a reproduction trace; rerun
once before blaming any new system for a red P5/L2.


---

## 7. R26b hotfix (field report: "creature got stuck after jumpscare")

Two bugs from the first real-play session, both in the director:

1. **Unresolved animation tracks + `request_roar: Method not found`.**
   `AnimationMixer.root_node` defaults to the mixer's **parent** — here the
   director — so track paths are relative to the director, not to the
   AnimationPlayer. The original `../CreatureKillCamera` paths resolved one
   level too high (every value track warned "couldn't resolve") and the method
   track `..` landed on the creature root instead of the director. Fixed paths:
   `CreatureKillCamera:fov`, `CreatureKillCamera:position`,
   `JumpscareLight:light_energy`, method track `.` → `request_roar`.
   Regression check: J2g asserts the roar clip is actually playing mid-scare.

2. **Creature frozen forever after the scare.** The hold block sets
   `_bt_player.active = false` every frame; the creature's own re-enables only
   run on feeding-respawn (skipped for jumpscare deaths by design) or void
   reset. So after `_end_sequence()` released the hold, the behavior tree stayed
   dead and the creature stood motionless. Fix: `_release_bt()` in the director
   restores `_bt_player.active = _awake` whenever the hold is released
   (`_end_sequence` and the mid-scare respawn path). Regression check: J6.
   Note for the selftest: a *dormant* creature legitimately runs with an
   inactive tree, so the scenario now wakes the creature before the killing
   blow — matching real gameplay, where only an awake creature can swipe/lunge.


---

## 8. R26c — authored kill cam & light (field report: "camera in a weird place")

The original director fought the designer on two fronts, both now removed:

1. Per-frame bone tracking rewrote `CreatureKillCamera.global_position` from
   `cam_offset` in skeleton space (`look_at` the head each frame).
2. The default animation's shake track keyed **absolute** positions around
   `(0,0,0)`, teleporting the camera off wherever it had been placed.

Result: the scare filmed from a nonsense spot no matter what the designer did.

**New contract (what the user asked for):** the `CreatureKillCamera` and
`JumpscareLight` nodes in `nightmare_creature.tscn` are the single source of
truth. Move/rotate them, change fov, colour, energy, range in the editor — the
director only toggles `current` / `visible` and plays the animation. Removed
exports: `cam_offset`, `cam_fov`, `head_bone_name`, `light_color`,
`light_energy_peak` (kept: `use_jumpscare_light`). Removed code: skeleton
resolution and the per-frame tracking block.

The code-built default animation now **captures the authored values at build
time**: fov slam keys `min(authored_fov * 1.45, 120) → authored_fov`; shake keys
are `authored_position ± jitter`; light flash keys `0 → authored_energy →
decay → 0`. Delete those tracks in the animation editor for a static cam or a
steady light. Authored defaults: camera at `(0, 1.75, 1.1)` creature-local,
tilted ~5° down at the face, fov 65; light at `(0, 2.2, 0.9)`, energy 6,
warm red, range 3.

Regression checks: J7 (camera origin drift < 6 cm during the scare — shake
only), J8 (light colour untouched), J9 (`cam_offset` export gone). 22/22.


---

## 9. R26d — void-out, and three engine traps found while framing the scare

**Void-out (`void_darkness`, default 0.7).** The scare happens IN PLACE (the death
stays attached to the place it happened — that is what makes that place scary on
the next run), but the world visually ceases to exist: ambient, background and
sun energies ramp to ~5% and fog density lifts 85%, so all that remains is the
scare light on the creature's face — the "empty dark room" shot without any
teleport, extra content, or world-state juggling. 0.0 = corridor stays visible;
1.0 = pure void. Ramps both directions (no light pop), fully restored after
(J10/J11). Fog lifting matters: this level's fog density (~1.0) eats essentially
all light beyond ~1.5 m, so without lifting it the scare light cannot reach the
face at any usable framing.

**Trap 1 — .tscn comments swallow the next line.** Godot 4.7's tscn parser
silently DROPS the first line after a comment line inside a node block — whether
that line is a property (`transform = ...` vanished, mis-placing the kill cam
twice) or even a `[node]` header (a trailing comment deleted the light node and
merged its properties into the camera). Rule now: `nightmare_creature.tscn`
contains ZERO comment lines; all warnings live here. If you edit the tscn, keep
comments out of node blocks entirely.

**Trap 2 — a plain `Node` between Node3Ds breaks the transform chain.** The
director was `type="Node"`; its Camera3D child then resolved its 3D parent as
nothing and sat at world origin while the creature moved (the "weird place"
report). The director is now `Node3D` (script extends Node3D). Any future node
that must carry 3D children has to be a Node3D.

**Trap 3 — the head is not at the creature origin.** The head bone sits at
creature-local ≈ (0, 1.7, -0.95) (see the HULL rest positions in any creature
log). A kill cam placed "1 m in front of the creature" was therefore 15 cm from
the skull. Shipped default: 1.3 m standoff from the head bone, y 1.8, ~4 deg
down, fov 65; light raking from front-left at (0.4, 2.1, -1.9)-ish local.

**Polishing the framing (your loop, editor-side):** select `CreatureKillCamera`
in `nightmare_creature.tscn`, use the viewport's camera PREVIEW to see exactly
what it frames (static pose, full light), move/rotate/fov until the face fills
the frame the way you want; same for `JumpscareLight`. For motion/lighting checks
run `tests/jumpscare_selftest.gd` (24 checks) or trigger a real scare in-game and
die to it. Note: headless/software-GL captures are NOT a reliable reference for
this level's lighting (the world is designed pitch-dark without the flashlight;
llvmpipe adds its own artifacts) — judge the scare on your GPU.


---

## 10. R27 — head-welded kill cam + lunge-at-lens (the "fixed position" fix)

Field report: the scare played from a fixed spot in the level; when the kill
happened elsewhere the creature was not in frame ("wrong angle" variant:
creature visible but never a face shot). Root causes addressed:

1. **The camera is now welded to the HEAD BONE at runtime.** At `_ready` the
   director captures the edit-time relationship between the kill cam and the
   head bone (`Head_015`, export `head_bone_name`) and re-applies it every
   frame: `cam.global = head_now * captured_offset`. So wherever the creature
   is, whatever pose the head is in (roar tilt, lunge), the face stays framed
   exactly as you posed it in the editor. If the bone is missing it falls back
   to a body-relative weld. The light rides the body the same way. This makes
   the rig immune to scene-tree mistakes: mis-parented nodes, plain-Node
   directors, merged tscn edits - none can pin the camera to a fixed spot again
   (regression check J12 teleports the creature mid-scare and asserts the cam
   follows).
2. **Lunge-at-lens beat** (your choice): the default animation now calls
   `request_lunge()` at t=0.02 (plays `anim_attack_3` and charges the creature
   `charge_distance` = 0.8 m toward the lens at `charge_speed`) and
   `request_roar()` at t=0.60 (charge stops, roar pose held to the end). The
   face rushes the camera, then slams and holds. Both are method tracks on the
   director, so retime them freely in the animation editor.
3. **Your tscn edits are safe now.** `nightmare_creature.tscn` is NO LONGER
   shipped in fix zips. The canonical rig also exists as
   `scenes/enemies/jumpscare_rig.tscn`, and `nightmare_creature.gd` instances it
   at runtime if (and only if) the inline `JumpscareDirector` block is missing
   from your scene - so a merge can never silently delete the system, and your
   inline copy (with your camera/light placement) always wins when present.

Editor workflow unchanged: pose `CreatureKillCamera` / `JumpscareLight` in
`nightmare_creature.tscn` (or in `jumpscare_rig.tscn` if you prefer the instanced
rig); the editor pose becomes the head-relative offset at runtime. Tune the
beat via `charge_distance`, `charge_speed`, `lunge_anim_prop`, or by retiming
the two method keys in `JumpscareAnim`.

Checks: 26/26 (J2g lunge at cut, J2h roar held, J12 weld-follow, J7 now asserts
cam-rides-creature instead of a static position). ai_selftest 0 failures,
smoke pass.
