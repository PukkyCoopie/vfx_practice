extends RefCounted

const CombatLayout := preload("res://scripts/combat_layout.gd")

## Move a unit so its visible mesh sits on the tile under its origin.


static func snap(unit: Node3D, tile_size: float = -1.0) -> void:
	var size := tile_size
	if size < 0.0:
		size = CombatLayout.CELL_SIZE
	size = maxf(size, 0.001)
	var visual := _visual_ground(unit)
	var tile_x := floorf(unit.global_position.x / size) * size + size * 0.5
	var tile_z := floorf(unit.global_position.z / size) * size + size * 0.5
	unit.global_position += Vector3(tile_x - visual.x, 0.0, tile_z - visual.z)


static func _visual_ground(unit: Node3D) -> Vector3:
	var merged := AABB()
	var found := false
	for node in unit.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var aabb := mesh_instance.global_transform * mesh_instance.get_aabb()
		if not found:
			merged = aabb
			found = true
		else:
			merged = merged.merge(aabb)
	if not found:
		return Vector3(unit.global_position.x, 0.0, unit.global_position.z)
	var center := merged.get_center()
	return Vector3(center.x, 0.0, center.z)
