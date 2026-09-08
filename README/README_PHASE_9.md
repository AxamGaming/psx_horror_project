# Phase 9 Delivery — Environmental Triggers, Wall Slams, Surface Steps

**Design doc's last page.** Copy list:

| File | Action |
|---|---|
| `scenes/levels/test_graybox.tscn` | **REPLACE** — door assembly + crawlspace tunnel + wood surface tags + new spawn |
| `scenes/level/heavy_door.gd` | **NEW** |
| `scenes/level/crawlspace_zone.gd` | **NEW** |
| `scenes/player/movement.gd` | **REPLACE** — `external_crouch`, wall-slam detection |
| `scenes/player/camera_rig.gd` | **REPLACE** — `apply_nudge()`, wall-slam camera reaction |
| `scenes/player/footsteps.gd` | **REPLACE** — surface-tagged take pools (concrete/wood) |
| `autoload/audio_mgr.gd` | **REPLACE** — wall-slam thud, door-creak stream, hum removal |
| `autoload/events.gd` | **REPLACE** — `wall_hit` signal |
| `default_bus_layout.tres` | **REPLACE** — Hum bus removed |
| `scenes/player/flashlight_rig.gd` | **REPLACE** — hum removed (your call: flashlights don't hum) |
| `audio/sfx/footstep_wood_01/02.wav` | **NEW** — CC0 wood takes (CREDITS.md updated) |
| `audio/sfx/flash_hum.wav` | **DELETE** from your project |

Commit: `git commit -m "phase 9: environmental triggers, wall slams, surface steps"`.

## What's in the graybox now

- **Heavy door** (east side, x≈5): stand in its trigger, press **E**. Swings 100° on its hinge over 1.6 s (sine in-out = heavy), creak plays **positionally** through `play_world_sound()` (panned + distance-attenuated by the World bus pool), and the camera gets a small spring **nudge** — `apply_nudge()` is deliberately NOT `apply_impulse()`: no noise suppression, no FOV punch, so doors feel mechanical, not combat.
- **Crawlspace** (south tunnel, z≈9.5): 1.15 m ceiling. Entering the zone **forces crouch** and blocks standing (capsule physically can't rise); exiting restores control. The reverb probe **chokes automatically** — real tight geometry, no fake audio params.
- **Wood surfaces**: Platform + Ramp carry group `surface_wood`; footsteps ray straight down each heel-strike and swap the take pool (concrete ↔ wood). Tag any future collider the same way.
- **Wall slams**: sprint into anything at speed → positional low thud at the contact point (pitched down for mass) + camera nudge from the wall direction, 0.4 s cooldown. Emitted as `Events.wall_hit(position, strength)`.

## ✅ Acceptance test

- [ ] E at the door: heavy swing + positional creak + small camera thud; E again closes; can't re-trigger mid-swing.
- [ ] Walk into the crawlspace standing: auto-crouch on entry; C release does nothing inside; crouch-walk through; standing returns after exit.
- [ ] Inside the tunnel: room tone/reverb visibly drier (overlay unchanged, ears change); steps sound tighter.
- [ ] Walk on Platform/Ramp: wood takes; step off onto floor: concrete returns.
- [ ] Sprint into WallWest: thud at the wall + camera push-back; walking into it slowly: nothing.
- [ ] F flashlight: click only, no hum (as decided); beam still lags/swims.
- [ ] Everything prior still holds: bob feel, impacts, deafness, limp, focus modes.

## Knobs

HeavyDoor node: `open_angle_deg`, `swing_time`, `nudge_magnitude`, `creak_volume_db`.
CrawlZone node: `force_crouch`.
Movement: wall-slam speed gate is the `2.8` in `_detect_wall_slam` (export it if you want it inspector-live — say the word).
AudioMgr: `world_atten_db_per_meter`, `world_pan_amount`.

## Design doc status: COMPLETE 🎉

Every system in the original document now exists: hybrid gait camera, spring weight, impacts + daze, focus modes, inventory-weight mass, flashlight lag-sync, pixel-quantized retro pipeline, full audio stack (heel-strike sync, weight pitch, dynamic reverb, deafness/tinnitus), environmental triggers, surface steps. What remains is *content*, not systems: real levels, art (vertex-snap shader arrives with textured assets), inventory/health/enemy systems that call the already-wired APIs, and polish tuning.
