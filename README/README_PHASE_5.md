# Phase 5 Delivery — PSX Presentation (640×360 SubViewport + snap filter)

> ⚠️ **SUPERSEDED by `README_PHASE_5_FIX.md`** — the colour-crush post shader was replaced with the user-chosen VHS-with-wiggle shader, and the SubViewport input isolation bug (dead mouse look) was fixed via `push_input` forwarding. Use the FIX readme.

## Files to copy

| File | Action |
|---|---|
| `scenes/main.tscn` | **NEW** — the shell scene (now the main scene) |
| `scenes/main.gd` | **NEW** — wires SubViewport → TextureRect in code |
| `shaders/psx_post.gdshader` | **NEW** — 15-bit colour crush + ordered Bayer dither |
| `scenes/player/camera_rig.gd` | **REPLACE** — adds the Retro Quantization snap filter |
| `project.godot` | **REPLACE** — main scene → `main.tscn`, letterbox clear colour → black |

Commit before/after: `git commit -m "phase 5: PSX presentation pipeline"`.

## Architecture (what changed structurally)

```
Main (main.gd)
├─ GameViewport (SubViewport 640×360, UPDATE_ALWAYS)
│   └─ TestGraybox (your level, instanced UNCHANGED — player/camera live inside)
├─ ViewportDisplay (TextureRect, nearest filter, keep-aspect-centered, PSX post material)
└─ UI (CanvasLayer, full resolution)   ← crisp inventory UI lands here in Phase 6+
```

- The world renders at **640×360** and is upscaled nearest-neighbour: at the default 1280×720 window that's a **pixel-perfect 2×** (every retro pixel = a crisp 2×2 block).
- Resize the window → letterboxed black bars, never stretched or cropped.
- `mouse_filter = IGNORE` on the display: mouse-look + click-to-recapture work exactly as before (input callbacks propagate scene-tree-wide; only *Control GUI* interaction would need the root layer — which is exactly where the Phase 6 inventory goes).
- The camera rig's debug overlay now renders **inside** the 640×360 target — it'll look chunky. That's expected (and proof the pipeline is live). Game UI will stay crisp on the root UI layer.

## The doc's "Retro-Quantized Movement Buffer" — now live

Camera offsets/rotations are rounded to render-scale steps *before* the single transform write (`snap_position_step` 0.5 cm ≈ 0.6 low-res px at 2 m; `snap_rotation_step_deg` 0.05°). Organic movement locks to the pixel grid instead of shimmering sub-pixel.

**PSX pixel-clamping on impact:** during `noise_suppress` (after H / hits), the grid **coarsens ×4** — the jolt literally steps across the screen in jagged discrete increments, then smooths back out as the wobble decays. That's the design doc's exact "brutal, crisp, digital" impact behaviour.

## PSX post shader (on ViewportDisplay → Material → Shader Parameters)

| Param | Default | Meaning |
|---|---|---|
| `color_bits` | 5 | PSX 15-bit colour. 4 = chunkier banding+dither; 8 = off |
| `dither_strength` | 1.0 | Classic ordered Bayer 4×4 dither, computed in *viewport* pixels so it locks to the retro grid |
| `effect_amount` | 1.0 | 0 = bypass the whole effect |

## ✅ Acceptance test

- [ ] F5 → world renders chunky; debug overlay text is visibly low-res (pipeline live).
- [ ] At 1280×720: pixels are sharp squares — no blur, no shimmer while walking.
- [ ] Colour gradients (floor lighting near walls) show fine dither pattern + 15-bit banding, not smooth ramps.
- [ ] Resize window to odd sizes → black letterbox bars, image stays 16:9 and sharp.
- [ ] Mouse look, Esc/click capture, WASD/sprint/crouch/jump: all identical to before.
- [ ] Walk: bob motion reads pixel-locked; idle breathing steps in tiny increments.
- [ ] **H impact: the jolt is visibly jagged/chunky mid-slam, then smooths as it recovers.**
- [ ] Landings/roll/wander unchanged in feel (snap is subtle by default).
- [ ] No new errors in Output; performance same or better.

## Tuning

| Want | Knob |
|---|---|
| Chunkier world | `GameViewport.size` → 480×270 or 320×180 (everything else adapts; snap steps can stay) |
| More/less snap on camera | `snap_position_step` (0.005), `snap_rotation_step_deg` (0.05), or `snap_enabled = false` |
| Harder impact pixel-clamp | `snap_impact_mult` ↑ (3 → 6) |
| Heavier colour crush | `color_bits` → 4 |
| No post effect | `effect_amount` → 0 |

**Deferred on purpose (documented so it's not forgotten):** the vertex-snap *geometry jitter* shader (classic PSX texture warping) needs textured art to be visible — pointless on flat-colour graybox. It arrives with your first real assets, along with import presets (nearest filtering, mipmaps off for world textures).

## Next

Pass → **Phase 6: gameplay hooks** — carry weight / stamina / health / focus modes wired to the rig's public API, with a debug control panel (on the crisp UI layer — first real use for it) so we can fake inventory weight and injury states before those systems exist.
