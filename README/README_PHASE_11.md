# Phase 11 Delivery — Survival Loop + Weapon

> **11-FIX-3 (current, asset + feel pass):**
> - **Shotgun blast re-derived from the original recording**: previous trim chopped the natural decay (that was the "weird cutoff"); now cut exactly at the true shot→pump gap (2.51 s) with only a 60 ms anti-click tail fade — full bloom and room tail intact.
> - **Wood footstep 01** re-derived from source: strongest single step isolated via segment-local energy analysis (old file had 6 steps in it).
> - **Crosshair replaced** with downloaded CC0 marks (LoneCoder's 64-pack, split): bare dot = normal, ring+dot = aiming (swaps live with focus mode), bone-warm tint, scene-editable.
> - **70/30 shader blend**: crosshair renders TWICE — full under the VHS (HUD layer) + a 70%-alpha crisp copy on the UI layer — so it reads as ~30% shader-affected (exported `alpha_mix` per instance). **ItemToast is FULLY crisp** (single instance on the UI layer, per playtest #4: "completely off the shader"). Stamina/health HUD untouched (fully under the tape). Selection highlight = overbright modulate tint (StyleBoxTexture has no border props).
> - **Inventory restyled for horror**: Poly Haven CC0 `decrepit_wallpaper` panel + `brown_leather` slots/buttons (StyleBoxTexture, per-slot leather tinted by item color), Special Elite typewriter font (Apache-2.0) across inventory/toast/death screens. All styles in scenes, per the no-hardcode rule.
> - Everything credited in CREDITS.md.

> **11-FIX-2 (current):** shotgun blast re-surgically trimmed — waveform energy analysis found the real shot→pump gap at 1.04 s; blast now keeps its NATURAL decay (old version had an artificial 0.55 s fade chopping the body — that was the "weird fade"). Only a 25 ms anti-click micro-fade remains. Added scene-built **ItemToast** ("Picked up / Dropped", event-driven) and **SurvivalHUD** (contextual stamina/health bars: hidden by default, fade in while stamina moves / after damage, fade out after delays; `always_visible` export for classic-HUD fans; all styles in the scene).
> - **Warnings cleared**: events.gd signals wrapped in `@warning_ignore_start/end("unused_signal")` (bus signals are used by *other* classes by design); `_on_wall_hit` param renamed (shadowed `Node3D.position`); dead `_fade` var removed.
> - **Death is now a real state**: damage pipeline (rig impulse, impact sound, deafness/tinnitus) is gated while dead — that's why sounds "repeated" on the corpse (arrow presses kept re-triggering them). Respawn stops ALL mid-play audio (clean slate) and resets spring/daze/suppress. **Look is locked on death** (was half-intentional corpse-cam; now locked per feedback) until respawn.
> - **footstep_concrete_03 removed** (file + code).
> - **Drops become world pickups**: tinted crate, ground-snapped, re-pickupable — nothing vanishes. **Shell pickups** placed in corridor + hall.
> - **Shotgun realism**: blast swapped to a real **Mossberg 500A recording** (trimmed to the shot), per-shot pitch variance, 8-pellet cone trace, breach breaks open when both barrels empty, breach closes over fresh shells on reload, heavier recoil kick.

## Copy list

| File | Action |
|---|---|
| `scenes/player/survival.gd` | **NEW** — stamina drain/recovery, exhaustion gate, death/respawn |
| `scenes/player/weapon_system.gd` | **NEW** — double-barrel shotgun: equip/aim/fire/reload |
| `scenes/ui/death_overlay.tscn` + `.gd` | **NEW** — scene-built YOU DIED overlay |
| `scenes/player/player.tscn` | **REPLACE** — Survival + Weapon nodes |
| `scenes/main.tscn` | **REPLACE** — DeathOverlay on the crisp layer |
| `autoload/events.gd` | **REPLACE** — 6 new loop signals |
| `scenes/player/movement.gd` | **REPLACE** — `exhausted` + `dead` gates |
| `scenes/player/camera_rig.gd` | **REPLACE** — aim zoom (`aim_fov`, `set_aim_zoom`) |
| `scenes/ui/inventory_ui.gd` | **REPLACE** — USE equips shotgun, Shell ammo pool |
| `project.godot` | **REPLACE** — `fire` (LMB), `reload` (R), `respawn` (R) |
| `audio/sfx/shotgun_blast/pump/gun_dry.wav` | **NEW** — CC0 (CREDITS updated) |

## The loop, end to end

1. **Find** the shotgun on the hall stage (E within 2.5 m) → lands in a slot, weight hits the carry meter.
2. **Tab → USE** equips it (item stays — it *is* your gun; info line teaches the keys).
3. **Hold RMB**: focus mode AIMING (steadied gait from Phase 6) + **−12° zoom** + held-breath stamina drain; at low stamina the rig's tremble kicks in — the doc's "held breath, shaking hands".
4. **LMB**: positional blast (reverb/pan by location), recoil nudge up-back with random lateral, 60 ms muzzle-flash light. Two barrels.
5. **R**: pump sound, 1.4 s, consumes **Shell items from the inventory** through `shells_requested/granted` — the inventory IS the ammo pool. No shells → dry click.
6. **Sprint** drains stamina (~7 s from full); recovery starts 1.5 s after exertion; at ~0 the `exhausted` gate refuses sprint and the gasping heave (Phase 8) takes over. Aiming drains slower.
7. **Die** (4 arrow hits): health ≤ 0 → movement freezes, overlay fades in over 1.2 s → **R** → respawn at spawn with full health/stamina.

Debug panel sliders still work for everything (stamina/health are rig values the systems mutate, not private mirrors).

## ✅ Test route

- [ ] Sprint until empty: sprint refuses at 0, gasp heave audible/visible, recovers after ~1.5 s rest.
- [ ] Pickup shotgun → Tab → USE → info line; RMB: zoom + steadied bob; stamina ticks down while aiming.
- [ ] LMB ×2: blasts + recoil + flash; 3rd LMB: dry click. R with shells: reload consumes Shell items (watch inventory + weight). R with no shells: dry click.
- [ ] Fire in the hall vs the corridor: reverb difference on the blast.
- [ ] Arrow-hit ×4: limp builds, then death overlay; R: respawn clean (gait/health/stamina reset, overlay gone).
- [ ] While dead: no movement, no fire; look still works.
- [ ] Regression: bob/impacts/doors/crawl/inventory jolt all unchanged.

## Knobs

Survival node: drain/recover rates, recover_delay. Weapon node: barrels, reload_time, recoil_nudge, flash_time. Rig: `aim_fov` (−12). All inspector-live.

## Next

**Phase 12 = the first enemy**: a stalker that hears you (sprint/footstep energy via the existing signals), closes distance, and emits `Events.player_damaged(amount, direction)` on contact — so every system you just tested (impulse, daze, limp, deafness, death) becomes its attack. The shotgun's `_trace_shot()` ray is already waiting to kill it.
