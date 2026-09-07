class_name StudioSeekBar
extends Control

signal drag_started
signal drag_ended(value_changed: bool)

const TRACK_H := 4.0
const GRABBER_R := 6.0
const GRABBER_R_ACTIVE := 7.0

var min_value := 0.0
var max_value := 1.0:
	set(v):
		max_value = maxf(v, min_value)
		queue_redraw()
var value := 0.0
var editable := true:
	set(v):
		editable = v
		mouse_default_cursor_shape = (
			Control.CURSOR_POINTING_HAND if editable else Control.CURSOR_ARROW
		)
		queue_redraw()

var _dragging := false
var _hover := false
var _track_style: StyleBoxFlat
var _fill_style: StyleBoxFlat


func _init() -> void:
	custom_minimum_size = Vector2(180, 22)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	_track_style = StyleBoxFlat.new()
	_track_style.bg_color = Color(0.30, 0.30, 0.30, 1)
	_track_style.set_corner_radius_all(2)
	_fill_style = StyleBoxFlat.new()
	_fill_style.bg_color = Color(0.86, 0.86, 0.86, 1)
	_fill_style.set_corner_radius_all(2)


func set_value_no_signal(next: float) -> void:
	var clamped := _clamp_value(next)
	if is_equal_approx(clamped, value):
		return
	value = clamped
	queue_redraw()


func _clamp_value(next: float) -> float:
	return clampf(next, min_value, maxf(min_value, max_value))


func _ratio() -> float:
	var span := max_value - min_value
	if span <= 0.0001:
		return 0.0
	return clampf((value - min_value) / span, 0.0, 1.0)


func _grabber_radius() -> float:
	if (_hover or _dragging) and editable:
		return GRABBER_R_ACTIVE
	return GRABBER_R


func _track_rect() -> Rect2:
	var y := (size.y - TRACK_H) * 0.5
	return Rect2(GRABBER_R, y, maxf(0.0, size.x - GRABBER_R * 2.0), TRACK_H)


func _x_from_ratio(ratio: float) -> float:
	var track := _track_rect()
	return track.position.x + track.size.x * clampf(ratio, 0.0, 1.0)


func _value_from_x(x: float) -> float:
	var track := _track_rect()
	var t := 0.0 if track.size.x <= 0.001 else clampf((x - track.position.x) / track.size.x, 0.0, 1.0)
	return lerpf(min_value, max_value, t)


func _seek_to_mouse() -> void:
	set_value_no_signal(_value_from_x(get_local_mouse_position().x))


func _gui_input(event: InputEvent) -> void:
	if not editable:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse.pressed:
			_dragging = true
			drag_started.emit()
			_seek_to_mouse()
			queue_redraw()
			accept_event()
		elif _dragging:
			_dragging = false
			drag_ended.emit(true)
			queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_seek_to_mouse()
		accept_event()
	elif event.is_action_pressed("ui_left"):
		set_value_no_signal(value - maxf(0.1, (max_value - min_value) * 0.02))
		drag_ended.emit(true)
		accept_event()
	elif event.is_action_pressed("ui_right"):
		set_value_no_signal(value + maxf(0.1, (max_value - min_value) * 0.02))
		drag_ended.emit(true)
		accept_event()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			_hover = true
			queue_redraw()
		NOTIFICATION_MOUSE_EXIT:
			_hover = false
			queue_redraw()
		NOTIFICATION_RESIZED, NOTIFICATION_THEME_CHANGED, NOTIFICATION_VISIBILITY_CHANGED:
			queue_redraw()


func _draw() -> void:
	var track := _track_rect()
	_track_style.draw(get_canvas_item(), track)
	var fill_w := track.size.x * _ratio()
	if fill_w > 0.5:
		_fill_style.draw(get_canvas_item(), Rect2(track.position, Vector2(fill_w, track.size.y)))
	if not editable and is_equal_approx(max_value, min_value):
		return
	var center := Vector2(_x_from_ratio(_ratio()), size.y * 0.5)
	var radius := _grabber_radius()
	draw_circle(center, radius + 1.0, Color(0.08, 0.08, 0.08, 0.55), true, -1.0, true)
	draw_circle(center, radius, Color(0.93, 0.93, 0.93), true, -1.0, true)
