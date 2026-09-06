extends CanvasLayer

const SPEEDS: Array[float] = [0.25, 0.5, 1.0, 2.0]
const ICON_SIZE := Vector2(36, 36)

var _play_btn: TextureButton
var _slider: HSlider
var _time_label: Label
var _speed: OptionButton
var _bar: PanelContainer
var _dragging := false
var _studio: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_studio = get_parent()
	_build()
	VfxBridge.playback_changed.connect(_on_playback_changed)
	VfxBridge.effect_changed.connect(func(_id: String) -> void: _refresh_transport())
	_on_playback_changed(get_tree().paused, Engine.time_scale)


func _process(_delta: float) -> void:
	if _dragging:
		return
	_refresh_transport()


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

	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	holder.offset_top = -78.0
	holder.offset_bottom = -16.0
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holder)

	_bar = PanelContainer.new()
	_bar.custom_minimum_size = Vector2(640, 56)
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.add_child(_bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_bar.add_child(row)

	_play_btn = _icon_button(preload("res://ui/icons/play.svg"), _on_toggle_play, "Play")
	row.add_child(_play_btn)
	row.add_child(_icon_button(preload("res://ui/icons/replay.svg"), _on_restart, "Restart"))

	_slider = HSlider.new()
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.custom_minimum_size = Vector2(240, 28)
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.01
	_slider.drag_started.connect(func() -> void: _dragging = true)
	_slider.drag_ended.connect(_on_seek_ended)
	row.add_child(_slider)

	_time_label = Label.new()
	_time_label.custom_minimum_size = Vector2(88, 0)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_time_label.text = "0.0 / 0.0"
	row.add_child(_time_label)

	row.add_child(_icon_view(preload("res://ui/icons/speed.svg")))
	_speed = OptionButton.new()
	_speed.custom_minimum_size = Vector2(84, 32)
	for speed in SPEEDS:
		_speed.add_item(_speed_label(speed))
	_speed.select(2)
	_speed.item_selected.connect(_on_speed_selected)
	row.add_child(_speed)

	row.add_child(_icon_button(preload("res://ui/icons/camera.svg"), _on_reset_camera, "Reset Camera"))


func _icon_view(texture: Texture2D) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(20, 20)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _icon_button(texture: Texture2D, handler: Callable, label: String) -> TextureButton:
	var btn := TextureButton.new()
	btn.texture_normal = texture
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.custom_minimum_size = ICON_SIZE
	btn.tooltip_text = label
	btn.focus_mode = Control.FOCUS_ALL
	btn.modulate = Color(0.92, 0.92, 0.92, 1)
	btn.mouse_entered.connect(func() -> void: btn.modulate = Color(1, 1, 1, 1))
	btn.mouse_exited.connect(func() -> void: btn.modulate = Color(0.92, 0.92, 0.92, 1))
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


func _on_reset_camera() -> void:
	var rig := get_parent().get_node_or_null("CameraRig")
	if rig and rig.has_method("reset_view"):
		rig.reset_view()


func _on_seek_ended(_changed: bool) -> void:
	_dragging = false
	if _studio and _studio.has_method("seek_playback"):
		_studio.seek_playback(_slider.value)


func _on_playback_changed(is_paused: bool, time_scale: float) -> void:
	if _play_btn:
		_play_btn.texture_normal = (
			preload("res://ui/icons/play.svg") if is_paused else preload("res://ui/icons/pause.svg")
		)
		_play_btn.tooltip_text = "Play" if is_paused else "Pause"
	if _speed:
		var idx := SPEEDS.find(time_scale)
		if idx >= 0:
			_speed.select(idx)


func _refresh_transport() -> void:
	if _bar:
		var view_w := get_viewport().get_visible_rect().size.x
		_bar.custom_minimum_size.x = minf(640.0, maxf(360.0, view_w - 32.0))
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
