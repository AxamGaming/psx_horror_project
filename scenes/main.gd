extends Node
## ============================================================================
## MAIN SHELL — Phase 5/6: PSX/VHS presentation + gameplay-hooks wiring.
##
##   GameViewport    (SubViewport 640x360) <- world + player + camera
##   ViewportDisplay (TextureRect)         <- nearest-neighbour upscale
##   PostFX/VHS      (CanvasLayer 1)       <- screen-space VHS shader (world only)
##   UI/DebugPanel   (CanvasLayer 10)      <- crisp UI ABOVE post FX
##
## The viewport texture is wired in CODE, not serialized: hand-written
## ViewportTexture paths in .tscn are a classic load-order trap, while
## get_texture() in _ready() is bulletproof.
##
## CRITICAL (learned the hard way): in Godot 4, input callbacks are
## VIEWPORT-SCOPED. Nodes inside a SubViewport receive NO _input /
## _unhandled_input from the window — polling (Input.is_action_pressed)
## still works, which is why WASD lived but mouse look died. The shell
## therefore forwards every event into the SubViewport with push_input().
## ============================================================================

@onready var _game_viewport: SubViewport = get_node("GameViewport") as SubViewport
@onready var _display: TextureRect = get_node("ViewportDisplay") as TextureRect
## NOTE: find_child() does NOT reach into instanced level subtrees the way you'd
## expect (ownership semantics), so we use the registration path that already
## works everywhere else: CameraRig._ready() sets Events.main_camera, and
## children _ready() before this node, so it's populated by now.
@onready var _rig: CameraRig = Events.main_camera as CameraRig

## Internal render resolution of the retro pipeline. Change here, in the
## inspector, or from code at runtime — everything downstream (upscale,
## letterbox, snap-filter scale references) adapts automatically.
@export var retro_resolution: Vector2i = Vector2i(640, 360)


func _ready() -> void:
	assert(_game_viewport != null, "Main: GameViewport (SubViewport) missing.")
	assert(_display != null, "Main: ViewportDisplay (TextureRect) missing.")
	_game_viewport.size = retro_resolution
	_display.texture = _game_viewport.get_texture()
	assert(_rig != null, "Main: CameraRig not found under GameViewport.")


func _input(event: InputEvent) -> void:
	# Feed the world viewport: this revives MouseLook (motion + ui_cancel +
	# click-to-recapture) and the CameraRig debug keys (H / F3).
	# NOTE: mouse POSITION inside the SubViewport isn't rescaled (640x360 vs
	# window) — irrelevant for captured mouse-look (uses `relative`) and for
	# center-screen interaction raycasts; world GUI must never live inside.
	# While the debug panel (or later the inventory) owns the mouse, the
	# forwarding still happens harmlessly: motion is capture-gated and
	# click-to-recapture respects Events.ui_wants_mouse.
	if _game_viewport != null:
		_game_viewport.push_input(event)
