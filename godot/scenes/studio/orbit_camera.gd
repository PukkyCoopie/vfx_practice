extends Node3D

@export var target: Vector3 = Vector3(0.0, 0.0, 0.0)
@export var distance: float = 8.0
## Classic studio 3/4 view: player lower-left, enemy upper-right.
@export var yaw_degrees: float = 45.0
@export var pitch_degrees: float = -45.0
@export var min_pitch: float = -80.0
@export var max_pitch: float = -10.0
@export var min_distance: float = 2.5
@export var max_distance: float = 22.0
@export var orbit_sensitivity: float = 0.35
@export var pan_sensitivity: float = 0.008
@export var zoom_sensitivity: float = 0.85

@onready var _yaw: Node3D = $Yaw
@onready var _pitch: Node3D = $Yaw/Pitch
@onready var _camera: Camera3D = $Yaw/Pitch/Camera3D

var _default_target: Vector3
var _default_distance: float
var _default_yaw: float
var _default_pitch: float


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_default_target = target
	_default_distance = distance
	_default_yaw = yaw_degrees
	_default_pitch = pitch_degrees
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_WHEEL_UP and mouse.pressed:
			distance = clampf(distance - zoom_sensitivity, min_distance, max_distance)
			_apply()
		elif mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse.pressed:
			distance = clampf(distance + zoom_sensitivity, min_distance, max_distance)
			_apply()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			yaw_degrees -= motion.relative.x * orbit_sensitivity
			pitch_degrees = clampf(
				pitch_degrees - motion.relative.y * orbit_sensitivity,
				min_pitch,
				max_pitch
			)
			_apply()
		elif (
			Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
			or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
		):
			var right := _camera.global_transform.basis.x
			var up := _camera.global_transform.basis.y
			target -= (right * motion.relative.x + up * -motion.relative.y) * pan_sensitivity * distance
			_apply()


func set_distance(value: float) -> void:
	distance = clampf(value, min_distance, max_distance)
	_apply()


func set_target(value: Vector3) -> void:
	target = value
	_apply()


func reset_view() -> void:
	target = _default_target
	distance = _default_distance
	yaw_degrees = _default_yaw
	pitch_degrees = _default_pitch
	_apply()


func _apply() -> void:
	global_position = target
	_yaw.rotation.y = deg_to_rad(yaw_degrees)
	_pitch.rotation.x = deg_to_rad(pitch_degrees)
	_camera.position = Vector3(0.0, 0.0, distance)
	_camera.rotation = Vector3.ZERO
