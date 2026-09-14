extends Control
class_name SettingsMenu
## ============================================================================
## SETTINGS / PAUSE MENU (R30) — home of the accessibility dials.
##
##   F1 or Esc  open/close (pauses the tree while open)
##
## Built in CODE on purpose: four sliders and a checkbox are 100% behaviour,
## and a .tscn of anchored containers for that is 140 lines of noise nobody
## edits. The values live in the Settings autoload (persisted), so this menu
## is just a view onto them — open it, drag, close, done.
##
## Refuses to open during the kill cutscene (group "kill_active"): pausing
## mid-scare would freeze the director with camera authority, which is a
## softlock factory.
## ============================================================================

const FONT_PATH := "res://assets/fonts/SpecialElite-Regular.ttf"

var _open: bool = false
var _was_captured: bool = false
var _sliders: Dictionary = {}     # key -> HSlider
var _flash_check: CheckButton = null
var _font: FontFile = null


func _ready() -> void:
	# Escape while paused still has to reach us.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build_ui()
	_sync_from_settings()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("open_settings") or event.is_action_pressed("ui_cancel"):
		if _open:
			close_menu()
			get_viewport().set_input_as_handled()
			return
		open_menu()
		get_viewport().set_input_as_handled()


func open_menu() -> void:
	if _open:
		return
	# Never pause mid-scare: the director owns camera authority and pausing it
	# parks the player in a frozen kill cam (softlock factory).
	if get_tree().get_first_node_in_group("kill_active") != null:
		return
	_open = true
	_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	visible = true
	Events.ui_wants_mouse = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	_sync_from_settings()


func close_menu() -> void:
	if not _open:
		return
	_open = false
	visible = false
	get_tree().paused = false
	Events.ui_wants_mouse = false
	if _was_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Settings.save_settings()


func _build_ui() -> void:
	_font = load(FONT_PATH) as FontFile
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(430, 0)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.04, 0.04, 0.94)
	st.border_color = Color(0.45, 0.08, 0.06, 1.0)
	st.set_border_width_all(2)
	st.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", st)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	vbox.add_child(_label("SETTINGS", 26))
	vbox.add_child(_label("the tape remembers", 13, Color(0.6, 0.5, 0.45)))

	_sliders["camera_shake"] = _slider(vbox, "Camera Shake", Settings.camera_shake)
	_sliders["kill_fx"] = _slider(vbox, "Kill Screen FX", Settings.kill_fx)
	_sliders["gore"] = _slider(vbox, "Gore / Blood", Settings.gore)

	_flash_check = CheckButton.new()
	_flash_check.text = "Reduce Flashes (photosensitivity)"
	_flash_check.button_pressed = Settings.reduce_flashes
	_flash_check.toggled.connect(_on_reduce_flashes)
	_style_button(_flash_check)
	vbox.add_child(_spaced(_flash_check))

	var resume := Button.new()
	resume.text = "RESUME"
	resume.pressed.connect(close_menu)
	_style_button(resume)
	vbox.add_child(_spaced(resume))


func _slider(parent: Node, text: String, value: float) -> HSlider:
	var vbox := parent as VBoxContainer
	vbox.add_child(_label(text, 15))
	var h := HSlider.new()
	h.min_value = 0.0
	h.max_value = 1.0
	h.step = 0.05
	h.value = value
	h.custom_minimum_size = Vector2(0, 24)
	h.value_changed.connect(_on_slider.bind(text))
	vbox.add_child(h)
	return h


func _on_slider(v: float, text: String) -> void:
	match text:
		"Camera Shake":
			Settings.set_camera_shake(v)
		"Kill Screen FX":
			Settings.set_kill_fx(v)
		"Gore / Blood":
			Settings.set_gore(v)


func _on_reduce_flashes(v: bool) -> void:
	Settings.set_reduce_flashes(v)


func _sync_from_settings() -> void:
	if _sliders.is_empty():
		return
	(_sliders["camera_shake"] as HSlider).set_deferred("value", Settings.camera_shake)
	(_sliders["kill_fx"] as HSlider).set_deferred("value", Settings.kill_fx)
	(_sliders["gore"] as HSlider).set_deferred("value", Settings.gore)
	if _flash_check != null:
		_flash_check.set_deferred("button_pressed", Settings.reduce_flashes)


func _label(text: String, size: int, col: Color = Color(0.86, 0.8, 0.74)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if _font != null:
		l.add_theme_font_override("font", _font)
	return l


func _spaced(c: Control) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 6)
	m.add_child(c)
	return m


func _style_button(b: BaseButton) -> void:
	if _font != null:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", Color(0.88, 0.82, 0.75))
