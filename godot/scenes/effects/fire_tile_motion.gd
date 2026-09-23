extends Node
## Demo-only movement. The effect consumes center velocity, not input events.
signal velocity_sampled(velocity: Vector2)

var target: Control
var side := 109.5
var center := Vector2.ZERO
var dragging := false
var flying := false
var _offset := Vector2.ZERO
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _elapsed := 0.0
var _duration := 0.45
var _previous := Vector2.ZERO

func setup(holder: Control, tile_side: float) -> void:
	target = holder
	side = tile_side
	process_priority = -10
	center = get_viewport().get_visible_rect().size * 0.5
	_previous = center
	_place()

func _process(delta: float) -> void:
	if flying:
		_elapsed = minf(_elapsed + delta, _duration)
		var t := _elapsed / _duration
		# Normalized exponential ease-out, with a precise endpoint.
		var k := (1.0 - pow(2.0, -6.0 * t)) / (1.0 - pow(2.0, -6.0))
		center = _from.lerp(_to, k)
		if t >= 1.0:
			flying = false
	_place()
	velocity_sampled.emit((center - _previous) / maxf(delta, 0.0001))
	_previous = center

func _input(event: InputEvent) -> void:
	# Continue an existing grab across GUI, and always catch its release.
	if not dragging:
		return
	if event is InputEventMouseMotion:
		center = _clamp_center(event.position + _offset)
		_place()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		dragging = false
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	# GUI receives presses first, so gallery/transport clicks cannot launch a flight.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Rect2(center - Vector2.ONE * side * 0.5, Vector2.ONE * side).has_point(event.position):
			flying = false
			dragging = true
			_offset = center - event.position
		else:
			fly_to(event.position)
		get_viewport().set_input_as_handled()

func fly_to(destination: Vector2) -> void:
	dragging = false
	_from = center
	_to = _clamp_center(destination)
	_elapsed = 0.0
	_duration = clampf(center.distance_to(_to) / 1300.0, 0.30, 0.70)
	flying = center.distance_to(_to) > 0.5

func relayout(tile_side: float) -> void:
	side = tile_side
	center = _clamp_center(center)
	_from = center
	_to = _clamp_center(_to)
	_elapsed = 0.0
	_previous = center
	_place()
	velocity_sampled.emit(Vector2.ZERO)

func _clamp_center(point: Vector2) -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	var margin := Vector2.ONE * (side * 0.5 + 8.0)
	return point.clamp(margin.min(vp * 0.5), (vp - margin).max(vp * 0.5))

func _place() -> void:
	if is_instance_valid(target):
		target.position = center - target.size * 0.5

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		dragging = false
