# PSX Horror Camera Systems

A Godot 4 horror prototype focused on a brutal, low-resolution survival loop: move through a claustrophobic corridor, keep your light on, watch the creature, and survive long enough to escape the nightmare.

This project blends PSX-style presentation, first-person movement, stealth tension, and a stalking enemy driven by a behavior tree. The result is a compact horror sandbox meant to feel like a prototype for a larger game or a short playable demo.

## What this project includes

- PSX-inspired visual treatment with a low-resolution viewport, nearest-neighbor scaling, and VHS-style screen effects
- First-person exploration with movement, crouch, sprint, jumping, and flashlight control
- A hostile creature that patrols, investigates noise, reacts to sight and sound, and can lunge or strike when close
- LimboAI-based enemy behavior setup with patrol, chase, investigate, and recovery logic
- Inventory and HUD layers for a horror-game feel
- Audio-driven tension using footsteps, creature roars, growls, impacts, and reactive sound cues
- A modular structure suited for iterative horror prototyping and level experimentation

## Core gameplay loop

The player explores a dim corridor environment while managing attention, proximity, and sound. The creature is not just a static enemy: it reacts to player movement, gunfire, and noise. Sprinting, crouching, flashlight use, and combat all change the threat profile.

The tension comes from:

- hearing the creature before you see it
- watching the light as a limited tool
- surviving repeated attacks while the AI adapts to your behavior
- experiencing the PSX-style camera and post-processing as part of the horror language

## Screens and systems

This project includes several core systems and scenes:

- gameplay shell and camera rig
- flashlight and weapon logic
- enemy awareness, perception, navigation, and behavior tasks
- UI for debugging, inventory, and horror overlays
- audio manager and event-driven game hooks
- level composition for a corridor-based test environment

## Controls

The project uses a standard FPS-style control scheme:

- W/A/S/D: move
- Shift: sprint
- C: crouch
- Space: jump
- F: flashlight
- Right mouse: aim
- Left mouse: fire
- R: reload / respawn
- Esc: capture or release mouse
- F2: debug panel

## Recommended setup

- Godot 4.7.x
- Forward+ rendering
- Linux tested; project is also suitable for desktop playtesting

## Running the project

1. Open Godot 4.7.x
2. Import the project by selecting the project.godot file in this folder
3. Press Play in the editor or run the main scene

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

## Notes

This repository is a prototype and a learning project as much as a game. The code and content are organized around experimentation with horror pacing, enemy behavior, camera systems, and retro presentation rather than a polished commercial production pipeline.

## Credits and references

The project incorporates third-party assets and tooling, including:

- LimboAI for behavior-tree style enemy logic
- community asset sources referenced in the project docs and credits
- retro shader and PSX-style presentation ideas adapted for Godot

See the files under the README and documentation folders for implementation notes, fix logs, phase summaries, and asset attribution.

## License

This project is a personal game prototype and may include assets or code from third-party sources. Please check the included documentation and asset attribution files before redistribution or reuse.
