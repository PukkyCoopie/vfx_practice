extends Node3D

@export_group("Placement")
@export var origin_height: float = 0.62
@export var origin_forward: float = 0.94


func _ready() -> void:
	add_to_group("vfx_no_toon")
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = Vector3(0.0, origin_height, origin_forward)
