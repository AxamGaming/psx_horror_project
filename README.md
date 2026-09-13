# PSX Horror Camera Systems

A Godot 4 horror prototype built around a cramped corridor, a stalking creature, and a brittle survival loop. The project focuses on low-resolution PSX presentation, first-person tension, and  enemy behavior rather than a polished commercial production pipeline.

## What is in this prototype

- Retro game shell with a low-res subviewport, nearest-neighbor scaling, and VHS-style screen treatment
- First-person movement with walking, sprinting, crouching, jumping, and mouse look
- Flashlight and weapon systems built around a tense survival loop
- A hostile creature driven by LimboAI with patrol, investigate, chase, and combat states
- A shotgun with reload flow tied to inventory-based ammo
- Inventory, HUD, noise meter, and proximity monitor layers for horror feedback
- Audio cues for footsteps, roars, impacts, weapon fire, and creature pressure
- A corridor-based test environment for enemy experimentation and horror pacing

## Core gameplay loop

The player moves through a dim, claustrophobic hall while managing movement noise, line of sight, and threat pressure. The creature does not merely wait in place: it reacts to gunfire, proximity, hearing, and the player’s movement patterns.

The intended tension loop is:

- move carefully to avoid being heard
- use the flashlight and your eyes to track danger
- fire only when the shot is worth the attention spike
- survive the creature’s chase and attack windows long enough to escape the horror cycle

## Current systems

This repository already includes a substantial prototype layer:

- movement, camera, and focus states for exploration, aiming, and inventory use
- autoload signal bus for global events like damage, gunfire, and inventory toggles
- shotgun weapon system with recoil and reload behavior
- nightmare creature AI with patrol, investigate, chase, lunge, swipe, neutralize, and recover logic
- noisy player state with movement-based audio and threat scaling
- UI overlays for survival HUD, inventory, noise meter, and proximity monitor
- event-driven design to keep systems decoupled and easier to iterate on

## Controls

The project uses a standard FPS control scheme:

- W/A/S/D: move
- Shift: sprint
- C: crouch
- Space: jump
- F: flashlight
- RMB: aim
- LMB: fire
- R: reload / respawn
- E: interact
- Tab / I: inventory
- Esc: release mouse
- F2 / related debug inputs: debug panel and test toggles

## Requirements

- Godot 4.7.x
- Forward+ rendering
- Linux-tested prototype setup, desktop playtesting expected

## Running the project

1. Open Godot 4.7.x
2. Import the project by opening the project.godot file in this folder
3. Press Play in the editor or run the main scene from the project tree

## Project structure

```text
.
├── addons/
│   └── limboai/
├── assets/
│   ├── fonts/
│   ├── models/
│   └── textures/
├── audio/
│   └── sfx/
├── autoload/
├── data/
├── docs/
├── README/
├── scenes/
│   ├── enemies/
│   ├── level/
│   ├── levels/
│   ├── player/
│   ├── props/
│   └── ui/
├── shaders/
├── tests/
├── default_bus_layout.tres
├── project.godot
├── README.md
└── ...
```

## Key folders

- addons/limboai: behavior tree support and plugin integration
- autoload/: global event bus and audio manager
- scenes/player/: camera, movement, weapon, flashlight, and survival systems
- scenes/enemies/: creature awareness, navigation, and nightmare AI logic
- scenes/ui/: inventory, debug overlays, noise meter, proximity monitor, and HUD
- docs/: design notes, fix logs, and milestone documentation
- README/: milestone and phase documentation from the project’s development history
- tests/: self-tests and capture scripts for AI, noise meter, and proximity behavior

## Documentation and references

This project includes substantial design notes and milestone summaries in the repo. Useful starting points include:

- docs/NOISE_METER.md
- docs/PROXIMITY_MONITOR_DESIGN.md
- README/README_LIMBOAI.md
- README/README_PHASE_11.md
- README/README_PHASE_12.md
- README/CREDITS.md

These files explain the behavior design and implementation decisions behind the current prototype.

## Status

This is an active horror prototype and design playground rather than a finished game. The codebase is organized around experimentation with low-res presentation, AI behavior, audio feedback, and survival tension in a compact corridor environment.

## Credits and licensing

The project uses a mix of custom code and third-party assets, including LimboAI and community asset sources. Review the included credits and docs before redistribution or reuse, especially for any audio, model, or font content sourced externally.
