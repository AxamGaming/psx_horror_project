extends Node
## ============================================================================
## EVENTS — global signal bus (autoload, registered as "Events").
## Systems EMIT here, listeners SUBSCRIBE here; no direct node references.
## The ignore block wraps ONLY the signal declarations: bus signals are used
## by OTHER classes by design, so the analyzer's unused-signal warning is a
## false alarm there.
## ============================================================================

@warning_ignore_start("unused_signal")

## Player touches floor after a fall. energy 0..1 (1 = brutal).
signal hard_landed(energy: float)
## Any damage source. direction = world direction the blow came FROM.
signal player_damaged(amount: float, direction: Vector3)
## Inventory open/closed (camera focus mode follows).
signal inventory_toggled(is_open: bool)
## A world pickup was taken.
signal pickup_triggered(item_id: String)
## Inventory USE pressed (weapon listens for "shotgun").
signal item_used(item_id: String)
## Weapon asks inventory for ammo; inventory answers with what it gave.
signal shells_requested(count: int)
signal shells_granted(count: int)
## Toast feed: successful add / drop.
signal item_picked_up(item_id: String)
signal item_dropped(item_id: String)
## Body slammed geometry hard enough to matter. position = contact point.
signal wall_hit(position: Vector3, strength: float)
## Death / respawn loop (SurvivalSystem owns the state).
signal player_died()
## R26: emitted ADDITIONALLY and FIRST when the killing blow is confirmed as
## the creature's (swipe or lunge). JumpscareDirector listens; the death overlay
## is suppressed for these deaths. Environmental deaths never emit this.
signal player_killed_by_creature()
signal player_respawned()
signal respawn_requested()
## Weapon fired — position of the shot. Wakes/investigates the creature.
signal gun_fired(position: Vector3)


## Set by UI systems (debug panel, inventory) while they need the cursor.
var ui_wants_mouse: bool = false

## Registered by CameraRig in _ready; used by AudioMgr's reverb probe and
## anything else that needs the eyes without coupling to the player scene.
var main_camera: Camera3D = null
