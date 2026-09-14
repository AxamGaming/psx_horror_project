# PSX Horror Camera Systems

A Godot 4 horror prototype built around a cramped corridor, a stalking creature, and a survival loop driven by noise, sight, and tension. The project leans into low-resolution PSX presentation, first-person dread, and reactive enemy behavior rather than a fully polished production pipeline.

## What is live in the prototype

- Retro presentation with a low-res viewport, nearest-neighbor scaling, and VHS-style overlay treatment
- First-person player controller with movement, sprinting, crouching, jumping, and mouse look
- Flashlight-driven exploration and a shotgun-based combat loop
- Creature AI built on LimboAI with patrol, investigate, chase, lunge, and recover logic
- Noise meter, proximity monitor, survival HUD, inventory, and debug UI overlays
- Positional audio and sound pressure for footsteps, roars, gunfire, impacts, and threat escalation
- Corridor-focused test environment designed for experimentation and horror pacing

## Core loop

The player traverses a dim hallway while monitoring sound, sightlines, and creature pressure. The enemy is not static: it reacts to movement, noise, proximity, and gunfire. The intended loop is simple but tense:

- move carefully to avoid detection
- use the flashlight and visual cues to track the threat
- fire only when the shot is worth the attention spike
- survive the chase windows and escape the creature’s pressure cycle

## Current systems

This repository contains a substantial working prototype layer, including:

- camera rig, movement controller, and first-person player states
- shared autoload event bus and audio manager
- weapon and reload systems tied to inventory and survival flow
- nightmare creature logic with awareness, navigation, kill timing, and damage routing
- UI overlays for HUD, noise pressure, proximity, settings, and inventory
- self-tests for AI, noise, fly behavior, and proximity checks
- documentation covering design decisions, fixes, and project history

## Controls

| Action | Input |
|---|---|
| Move | W / A / S / D |
| Sprint | Shift |
| Crouch | C |
| Jump | Space |
| Flashlight | F |
| Aim | Right Mouse |
| Fire | Left Mouse |
| Reload | R |
| Interact | E |
| Inventory | Tab / I |
| Release mouse | Esc |
| Debug panel | F2 |

Additional debug and self-test inputs are defined in the project input map for editor playtesting.

## Requirements

- Godot 4.7.x
- Forward+ rendering
- Linux-tested prototype setup for desktop playtesting

## Running the project

1. Open Godot 4.7.x
2. Open the project root and import the project.godot file
3. Press Play in the editor or run the main scene from the project tree

For headless regression checks, use the commands documented in STATE.md.

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
├── CHANGELOG.md
├── STATE.md
├── default_bus_layout.tres
├── project.godot
├── README.md
└── ...
```

## Key folders

- addons/limboai: behavior-tree support and plugin integration
- autoload/: global event bus, settings, and audio manager
- scenes/player/: camera, movement, weapon, flashlight, and survival systems
- scenes/enemies/: creature awareness, navigation, and nightmare AI logic
- scenes/ui/: inventory, HUD, debug overlays, noise meter, and proximity systems
- docs/: design notes, fix logs, and milestone documentation
- README/: historical milestone and phase documentation
- tests/: self-tests and capture scripts for AI, noise meter, and proximity behavior

## Important project docs

Start here for the current project state and the latest design notes:

- STATE.md
- CHANGELOG.md
- docs/FIXES_R32_cleanup_round.md
- docs/NOISE_METER.md
- docs/PROXIMITY_MONITOR_DESIGN.md
- README/README_LIMBOAI.md
- README/CREDITS.md

## Status

This is an active horror prototype and design playground rather than a finished commercial game. The repository is organized around experimentation with low-res presentation, AI behavior, audio feedback, and survival tension in a compact corridor environment.

## Credits and licensing

The project combines custom code, community assets, and the LimboAI plugin. Review the included credits and documentation before redistribution or reuse, especially for audio, model, font, or third-party content sourced externally.
