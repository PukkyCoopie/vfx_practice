extends Node3D

@export_group("Placement")
@export var origin_height: float = 0.62
@export var origin_forward: float = 0.94

@export_group("Cast Window")
@export var emit_start: float = 1.02
@export var emit_full: float = 1.28
@export var emit_fade_start: float = 3.16
@export var emit_end: float = 3.72

@export_group("Light")
@export var light_energy: float = 4.2
@export var light_range: float = 4.2
@export var light_color: Color = Color(0.72, 0.32, 1.0)

var _anim: AnimationPlayer


func _ready() -> void:
	add_to_group("vfx_no_toon")
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = Vector3(0.0, origin_height, origin_forward)
	_anim = _find_anim()


func get_cast_time() -> float:
	return _anim_time()


func _anim_time() -> float:
	if _anim == null or not is_instance_valid(_anim):
		_anim = _find_anim()
	if _anim == null or _anim.current_animation.is_empty():
		return 0.0
	return _anim.current_animation_position


func _find_anim() -> AnimationPlayer:
	var host := get_parent()
	if host == null:
		return null
	var found := host.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		return null
	return found[0] as AnimationPlayer
