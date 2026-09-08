# Phase 5 FIX — SubViewport input + VHS shader swap

Two fixes in one delivery. **Copy list:**

| File | Action |
|---|---|
| `scenes/main.gd` | **REPLACE** — now forwards input into the SubViewport |
| `scenes/main.tscn` | **REPLACE** — VHS post layer added, old post material removed |
| `shaders/vhs_wiggle.gdshader` | **NEW** — the cyanone/hunterk VHS-with-wiggle shader |
| `shaders/psx_post.gdshader` | **DELETE** from your project (no longer referenced) |

`project.godot` and everything else: unchanged from Phase 5.

## Fix 1 — Mouse dead (my bug, root-caused)

In Godot 4, `_input` / `_unhandled_input` callbacks are **viewport-scoped**: nodes inside a SubViewport receive nothing from the window. Polling (`Input.is_action_pressed`) is global — which is exactly why your WASD/sprint/crouch worked but mouse look was dead. The shell now forwards every event: `main.gd::_input()` → `GameViewport.push_input(event)`. This revives MouseLook (motion, Esc, click-to-recapture) and the CameraRig debug keys (H, F3).

Known, documented side effects (all fine for this project):
- Mouse *position* inside the SubViewport isn't rescaled (640×360 vs window) — irrelevant because mouse look uses `relative` and horror-game interaction will use center-screen raycasts (Phase 9), never a world-space cursor.
- Phase 6 will gate the forwarding while the inventory UI owns the mouse (noted in `main.gd`).

## Fix 2 — Shader swap: colour-crush post → VHS with wiggle

My `psx_post.gdshader` (15-bit crush + Bayer dither) is **gone**. In its place: the shader you picked — cyanone's Godot port of hunterk's RetroArch VHS shader (original: ShaderToy `XlsczN`; credits preserved in the file header). It's a **screen-space** effect on `PostFX/VHS` (ColorRect, CanvasLayer **1**):

- samples the screen *after* the 640×360 nearest upscale → chunky pixels **plus** tape degradation: tracking wiggle, colour smear (YIQ-separated blur), brightness dip pulses.
- The game **UI layer sits at CanvasLayer 10 — above the VHS** — so future inventory/UI stays crisp, per the design doc.
- Tune live: Inspector → PostFX/VHS → Material → Shader Parameters.

| Param | Default | Notes |
|---|---|---|
| `wiggle` | 0.03 | tracking jitter amount |
| `wiggle_speed` | 25 | tape wobble rate |
| `smear` | 1.0 | colour-bleed strength |
| `blur_samples` | 15 | **lower this first if FPS drops** (smear quality degrades slightly) |

Note: the camera-side **snap filter is untouched** and stacks underneath the VHS layer (it quantizes actual camera motion; VHS degrades the final tape image). If the combo feels like too much, soften `wiggle`/`smear` first; `snap_enabled = false` on MainCamera if you want raw motion.

## ✅ Acceptance test

- [ ] Mouse look works; Esc releases, click recaptures.
- [ ] WASD/sprint/crouch/jump still fine; H = impact jolt; F3 = chunky overlay (inside the retro image, as designed).
- [ ] World has visible VHS character: occasional tracking wiggle, horizontal colour smear on bright edges, subtle brightness pulses.
- [ ] FPS acceptable (if not: `blur_samples` 15 → 8).
- [ ] Resize window → letterbox intact, VHS covers full screen.
- [ ] No red errors in Output.

## After this passes

**Phase 6 — gameplay hooks**: carry weight / stamina / health / focus modes driving the rig API, with a debug control panel on the crisp UI layer (first tenant of CanvasLayer 10 — it will render *above* the VHS, proving the crisp-UI architecture).
