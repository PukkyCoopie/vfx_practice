extends PanelContainer

signal hide_requested

const CARD_SEP := 10
const FRAME_HEIGHT := 118

var _group := ButtonGroup.new()
var _frames: Dictionary = {}
var _titles: Dictionary = {}
var _buttons: Dictionary = {}


func _ready() -> void:
	theme_type_variation = &"GalleryPanel"
	custom_minimum_size = Vector2(236, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_group.allow_unpress = false
	_build()
	if not VfxBridge.effect_changed.is_connected(_on_effect_changed):
		VfxBridge.effect_changed.connect(_on_effect_changed)
	_on_effect_changed(VfxBridge.get_current_id())


func _build() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)

	var title := Label.new()
	title.text = "Gallery"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.theme_type_variation = &"GalleryTitle"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title)

	var hide_btn := Button.new()
	hide_btn.icon = preload("res://ui/icons/panel_hide.svg")
	hide_btn.expand_icon = true
	hide_btn.custom_minimum_size = Vector2(32, 32)
	hide_btn.tooltip_text = "Hide gallery"
	hide_btn.focus_mode = Control.FOCUS_ALL
	hide_btn.pressed.connect(func() -> void: hide_requested.emit())
	head.add_child(hide_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", CARD_SEP)
	scroll.add_child(list)

	for effect in VfxBridge.get_effects():
		if effect is Dictionary:
			list.add_child(_make_card(effect as Dictionary))


func _make_card(effect: Dictionary) -> Button:
	var effect_id := String(effect.get("id", ""))
	var title_text := String(effect.get("title", effect_id))
	var card := Button.new()
	card.toggle_mode = true
	card.button_group = _group
	card.theme_type_variation = &"ThumbCard"
	card.focus_mode = Control.FOCUS_ALL
	card.tooltip_text = title_text
	card.custom_minimum_size = Vector2(0, FRAME_HEIGHT + 28)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.clip_contents = true
	card.pressed.connect(_on_card_pressed.bind(effect_id))

	var inner := VBoxContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 4
	inner.offset_top = 4
	inner.offset_right = -4
	inner.offset_bottom = -4
	inner.add_theme_constant_override("separation", 6)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(inner)

	var frame := PanelContainer.new()
	frame.theme_type_variation = &"ThumbFrame"
	frame.custom_minimum_size = Vector2(0, FRAME_HEIGHT)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.clip_contents = true
	inner.add_child(frame)

	frame.add_child(_make_thumb_view(effect))

	var label := Label.new()
	label.text = title_text
	label.theme_type_variation = &"ThumbTitle"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(label)

	_buttons[effect_id] = card
	_frames[effect_id] = frame
	_titles[effect_id] = label
	return card


func _make_thumb_view(effect: Dictionary) -> TextureRect:
	var frames := _atlas_frames(effect)
	var fps := float(effect.get("thumb_fps", 12))
	if frames.size() > 1:
		var anim := ThumbAnim.new()
		anim.setup(frames, fps)
		return anim
	var tex := TextureRect.new()
	_style_thumb_rect(tex)
	if not frames.is_empty():
		tex.texture = frames[0]
	return tex


func _atlas_frames(effect: Dictionary) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	var thumb_path := VfxBridge.thumb_path_for(String(effect.get("thumb", "")))
	if thumb_path.is_empty() or not ResourceLoader.exists(thumb_path):
		return frames
	var sheet := load(thumb_path) as Texture2D
	if sheet == null:
		return frames
	var frame_count := maxi(int(effect.get("thumb_frames", 1)), 1)
	if frame_count <= 1:
		frames.append(sheet)
		return frames
	var cols := maxi(int(effect.get("thumb_columns", 1)), 1)
	var rows := maxi(int(ceili(float(frame_count) / float(cols))), 1)
	var fw := float(sheet.get_width()) / float(cols)
	var fh := float(sheet.get_height()) / float(rows)
	for i in frame_count:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.filter_clip = true
		atlas.region = Rect2((i % cols) * fw, floori(float(i) / float(cols)) * fh, fw, fh)
		frames.append(atlas)
	return frames


func _style_thumb_rect(tex: TextureRect) -> void:
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE


class ThumbAnim extends TextureRect:
	var _frames: Array[Texture2D] = []
	var _fps := 12.0
	var _t := 0.0

	func _ready() -> void:
		expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		process_mode = Node.PROCESS_MODE_ALWAYS

	func setup(frames: Array[Texture2D], fps: float) -> void:
		_frames = frames
		_fps = maxf(fps, 1.0)
		_t = 0.0
		texture = _frames[0] if not _frames.is_empty() else null
		set_process(_frames.size() > 1)

	func _process(delta: float) -> void:
		if _frames.size() < 2:
			return
		_t += delta
		var span := float(_frames.size()) / _fps
		_t = fmod(_t, span)
		texture = _frames[int(_t * _fps) % _frames.size()]


func _on_card_pressed(effect_id: String) -> void:
	if effect_id == VfxBridge.get_current_id():
		return
	VfxBridge.select(effect_id)


func _on_effect_changed(effect_id: String) -> void:
	for id in _buttons:
		var card := _buttons[id] as Button
		var active: bool = String(id) == effect_id
		card.set_pressed_no_signal(active)
		var frame := _frames[id] as PanelContainer
		frame.theme_type_variation = &"ThumbFrameActive" if active else &"ThumbFrame"
		var label := _titles[id] as Label
		label.theme_type_variation = &"ThumbTitleActive" if active else &"ThumbTitle"
