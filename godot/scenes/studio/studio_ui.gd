extends CanvasLayer

const SPEEDS: Array[float] = [0.25, 0.5, 1.0, 2.0]

var _play_btn: Button
var _pause_btn: Button
var _speed_buttons: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	VfxBridge.playback_changed.connect(_on_playback_changed)
	_on_playback_changed(get_tree().paused, Engine.time_scale)


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

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	margin.offset_top = -92.0
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 18)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(margin)

	var bar := PanelContainer.new()
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	margin.add_child(bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)

	_play_btn = _make_button("Play", _on_play)
	_pause_btn = _make_button("Pause", _on_pause)
	row.add_child(_play_btn)
	row.add_child(_pause_btn)
	row.add_child(_make_button("Restart", _on_restart))
	row.add_child(_make_separator())

	var speed_label := Label.new()
	speed_label.text = "Speed"
	speed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(speed_label)

	for speed in SPEEDS:
		var label := _speed_label(speed)
		var btn := _make_button(label, _on_speed.bind(speed))
		btn.toggle_mode = true
		btn.button_pressed = is_equal_approx(speed, 1.0)
		_speed_buttons[speed] = btn
		row.add_child(btn)

	row.add_child(_make_separator())
	row.add_child(_make_button("Reset Camera", _on_reset_camera))


func _make_button(text: String, handler: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_ALL
	btn.pressed.connect(handler)
	return btn


func _make_separator() -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(12, 0)
	return spacer


func _speed_label(speed: float) -> String:
	if speed == 0.25:
		return "0.25x"
	if speed == 0.5:
		return "0.5x"
	if speed == 1.0:
		return "1x"
	return "2x"


func _on_play() -> void:
	VfxBridge.play()


func _on_pause() -> void:
	VfxBridge.pause()


func _on_restart() -> void:
	VfxBridge.restart()


func _on_speed(scale: float) -> void:
	VfxBridge.setSpeed(scale)


func _on_reset_camera() -> void:
	var rig := get_parent().get_node_or_null("CameraRig")
	if rig and rig.has_method("reset_view"):
		rig.reset_view()


func _on_playback_changed(is_paused: bool, time_scale: float) -> void:
	if _play_btn:
		_play_btn.disabled = not is_paused
	if _pause_btn:
		_pause_btn.disabled = is_paused
	for speed in _speed_buttons:
		var btn: Button = _speed_buttons[speed]
		btn.set_pressed_no_signal(is_equal_approx(float(speed), time_scale))
