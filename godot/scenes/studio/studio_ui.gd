extends CanvasLayer

const SPEEDS: Array[float] = [0.25, 0.5, 1.0, 2.0]
const ICON_SIZE := Vector2(36, 36)

var _play_btn: Button
var _slider: HSlider
var _time_label: Label
var _speed_btn: Button
var _speed_menu: PanelContainer
var _speed_items: Array[Button] = []
var _bar: PanelContainer
var _blocker: ColorRect
var _dragging := false
var _studio: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_studio = get_parent()
	_build()
	VfxBridge.playback_changed.connect(_on_playback_changed)
	VfxBridge.effect_changed.connect(func(_id: String) -> void: _refresh_transport())
	_on_playback_changed(get_tree().paused, Engine.time_scale)
	if _play_btn:
		_play_btn.grab_focus()


func _process(_delta: float) -> void:
	if _dragging:
		return
	_refresh_transport()


func _unhandled_input(event: InputEvent) -> void:
	if not _speed_menu or not _speed_menu.visible:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_close_speed_menu()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = preload("res://ui/studio_theme.tres")
	add_child(root)

	var vignette := ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vignette_mat := ShaderMaterial.new()
	vignette_mat.shader = preload("res://shaders/vignette.gdshader")
	vignette.material = vignette_mat
	root.add_child(vignette)

	var holder := MarginContainer.new()
	holder.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	holder.offset_top = -80.0
	holder.offset_bottom = -18.0
	holder.add_theme_constant_override("margin_left", 20)
	holder.add_theme_constant_override("margin_right", 20)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holder)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(center)

	_bar = PanelContainer.new()
	_bar.custom_minimum_size = Vector2(640, 56)
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_bar)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	_bar.add_child(row)

	_play_btn = _icon_button(preload("res://ui/icons/play.svg"), _on_toggle_play, "Play")
	row.add_child(_play_btn)
	row.add_child(_icon_button(preload("res://ui/icons/replay.svg"), _on_restart, "Restart"))

	var slider_slot := Control.new()
	slider_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider_slot.custom_minimum_size = Vector2(220, 28)
	row.add_child(slider_slot)

	_slider = HSlider.new()
	_slider.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.01
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.add_theme_icon_override("grabber", preload("res://ui/icons/grabber.svg"))
	_slider.add_theme_icon_override("grabber_highlight", preload("res://ui/icons/grabber.svg"))
	_slider.add_theme_icon_override("grabber_disabled", preload("res://ui/icons/grabber.svg"))
	_slider.drag_started.connect(func() -> void: _dragging = true)
	_slider.drag_ended.connect(_on_seek_ended)
	slider_slot.add_child(_slider)

	_time_label = Label.new()
	_time_label.custom_minimum_size = Vector2(84, 0)
	_time_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_time_label.text = "0.0 / 0.0"
	row.add_child(_time_label)

	_speed_btn = Button.new()
	_speed_btn.custom_minimum_size = Vector2(78, 36)
	_speed_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_speed_btn.text = "1x"
	_speed_btn.icon = preload("res://ui/icons/chevron.svg")
	_speed_btn.expand_icon = true
	_speed_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_btn.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_btn.add_theme_constant_override("icon_max_width", 14)
	_speed_btn.tooltip_text = "Speed"
	_speed_btn.focus_mode = Control.FOCUS_ALL
	_speed_btn.pressed.connect(_toggle_speed_menu)
	row.add_child(_speed_btn)

	_blocker = ColorRect.new()
	_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blocker.color = Color(0, 0, 0, 0.0)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_blocker.visible = false
	_blocker.gui_input.connect(_on_blocker_input)
	root.add_child(_blocker)

	_speed_menu = PanelContainer.new()
	_speed_menu.visible = false
	_speed_menu.theme_type_variation = &"SpeedMenu"
	_speed_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	_speed_menu.custom_minimum_size = Vector2(92, 0)
	root.add_child(_speed_menu)

	var items := VBoxContainer.new()
	items.add_theme_constant_override("separation", 2)
	_speed_menu.add_child(items)
	for i in SPEEDS.size():
		var item := Button.new()
		item.theme_type_variation = &"SpeedItem"
		item.text = _speed_label(SPEEDS[i])
		item.alignment = HORIZONTAL_ALIGNMENT_CENTER
		item.focus_mode = Control.FOCUS_ALL
		item.pressed.connect(_on_speed_selected.bind(i))
		items.add_child(item)
		_speed_items.append(item)


func _icon_button(texture: Texture2D, handler: Callable, label: String) -> Button:
	var btn := Button.new()
	btn.icon = texture
	btn.expand_icon = true
	btn.custom_minimum_size = ICON_SIZE
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.tooltip_text = label
	btn.focus_mode = Control.FOCUS_ALL
	btn.pressed.connect(handler)
	return btn


func _speed_label(speed: float) -> String:
	if is_equal_approx(speed, 0.25):
		return "0.25x"
	if is_equal_approx(speed, 0.5):
		return "0.5x"
	if is_equal_approx(speed, 1.0):
		return "1x"
	return "2x"


func _toggle_speed_menu() -> void:
	if _speed_menu.visible:
		_close_speed_menu()
	else:
		_open_speed_menu()


func _open_speed_menu() -> void:
	_highlight_speed(Engine.time_scale)
	_speed_menu.visible = true
	_blocker.visible = true
	await get_tree().process_frame
	var btn_rect := _speed_btn.get_global_rect()
	var menu_size := _speed_menu.get_combined_minimum_size()
	_speed_menu.global_position = Vector2(
		btn_rect.position.x + btn_rect.size.x - menu_size.x,
		btn_rect.position.y - menu_size.y - 8.0
	)


func _close_speed_menu() -> void:
	_speed_menu.visible = false
	_blocker.visible = false


func _on_blocker_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_close_speed_menu()


func _on_toggle_play() -> void:
	if get_tree().paused:
		VfxBridge.play()
	else:
		VfxBridge.pause()


func _on_restart() -> void:
	VfxBridge.restart()


func _on_speed_selected(index: int) -> void:
	if index >= 0 and index < SPEEDS.size():
		VfxBridge.setSpeed(SPEEDS[index])
	_close_speed_menu()


func _on_seek_ended(_changed: bool) -> void:
	_dragging = false
	if _studio and _studio.has_method("seek_playback"):
		_studio.seek_playback(_slider.value)


func _on_playback_changed(is_paused: bool, time_scale: float) -> void:
	if _play_btn:
		_play_btn.icon = (
			preload("res://ui/icons/play.svg") if is_paused else preload("res://ui/icons/pause.svg")
		)
		_play_btn.tooltip_text = "Play" if is_paused else "Pause"
	_highlight_speed(time_scale)


func _highlight_speed(time_scale: float) -> void:
	if _speed_btn:
		_speed_btn.text = _speed_label(time_scale) if SPEEDS.has(time_scale) else "1x"
	for i in _speed_items.size():
		var active := is_equal_approx(SPEEDS[i], time_scale)
		_speed_items[i].modulate = Color(1, 1, 1, 1) if active else Color(0.78, 0.78, 0.78, 1)
		if active:
			_speed_items[i].add_theme_stylebox_override(
				"normal", _speed_items[i].get_theme_stylebox("pressed", &"SpeedItem")
			)
		else:
			_speed_items[i].remove_theme_stylebox_override("normal")


func _refresh_transport() -> void:
	if _bar:
		var view_w := get_viewport().get_visible_rect().size.x
		_bar.custom_minimum_size.x = minf(640.0, maxf(360.0, view_w - 40.0))
	if _studio == null or _slider == null:
		return
	var length := 0.0
	var time := 0.0
	if _studio.has_method("get_playback_length"):
		length = _studio.get_playback_length()
	if _studio.has_method("get_playback_time"):
		time = _studio.get_playback_time()
	_slider.max_value = maxf(length, 0.001)
	_slider.set_value_no_signal(clampf(time, 0.0, _slider.max_value))
	_slider.editable = length > 0.0
	_time_label.text = "%.1f / %.1f" % [time, length]
