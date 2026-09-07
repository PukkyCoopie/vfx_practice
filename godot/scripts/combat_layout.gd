class_name CombatLayout
extends RefCounted

## Mirrors words_and_wizards combat grid spacing / unit scale.
## Studio keeps the classic 3/4 camera composition (player lower-left,
## enemy upper-right), so the duo faces along -Z like the old lab layout.

const CELL_SIZE := 1.4
const UNIT_SCALE := 1.5
const FRONT_ENEMY_ROW := 2

const PLAYER_CELL := Vector2i(0, 0)
const FRONT_SCARECROW_CELL := Vector2i(0, FRONT_ENEMY_ROW)


## World position of a cell's center (matches the studio checkerboard).
static func cell_to_world(cell: Vector2i, y: float = 0.0) -> Vector3:
	return Vector3(
		(float(cell.x) + 0.5) * CELL_SIZE,
		y,
		(float(cell.y) + 0.5) * CELL_SIZE
	)


static func front_row_distance() -> float:
	return float(FRONT_ENEMY_ROW) * CELL_SIZE


## Place duo for studio 3/4 view (yaw 45 / pitch -45):
## player on +Z facing -Z, scarecrow on -Z facing +Z, gap = front_row_distance().
## Both stand on tile centers (not grid lines). Scale is on Model so VFX
## under the unit stay in world units.
static func apply_duo(root: Node) -> void:
	var half := front_row_distance() * 0.5
	# Even cell gaps centered on the world origin land on grid lines.
	# Shift by half a cell so both feet sit in tile interiors.
	var mid := Vector3(CELL_SIZE * 0.5, 0.0, CELL_SIZE * 0.5)

	var player := root.get_node_or_null("Player") as Node3D
	if player != null:
		player.position = mid + Vector3(0.0, 0.0, half)
		# Face -Z (toward scarecrow) for the classic studio framing.
		player.rotation_degrees = Vector3(0.0, 180.0, 0.0)
		player.scale = Vector3.ONE
		_scale_model(player)

	var scarecrow := root.get_node_or_null("Scarecrow") as Node3D
	if scarecrow != null:
		scarecrow.position = mid + Vector3(0.0, 0.0, -half)
		scarecrow.rotation_degrees = Vector3(0.0, 0.0, 0.0)
		scarecrow.scale = Vector3.ONE
		_scale_model(scarecrow)


static func _scale_model(unit: Node3D) -> void:
	var model := unit.get_node_or_null("Model") as Node3D
	if model != null:
		model.scale = Vector3.ONE * UNIT_SCALE
