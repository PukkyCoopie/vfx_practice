class_name ToonStyle
extends RefCounted

## Cel lighting from waw. Outline uses inverted-hull grow so it works on
## GL Compatibility / Web (Godot stencil is not available there).

const TOON_SHADER: Shader = preload("res://shaders/toon_cel.gdshader")

const LIGHT_STEPS := 3
const OUTLINE_THICKNESS := 0.014
const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 1.0)


static func apply_tree(root: Node, with_outline: bool = true) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var use_outline := with_outline and not mesh_instance.is_in_group("toon_no_outline")
		apply_mesh_instance(mesh_instance, use_outline)


static func apply_unit(unit: Node, with_outline: bool = true) -> void:
	for node in unit.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var use_outline := with_outline and not mesh_instance.is_in_group("toon_no_outline")
		apply_mesh_instance(mesh_instance, use_outline)


static func apply_mesh_instance(mesh_instance: MeshInstance3D, with_outline: bool = true) -> void:
	if mesh_instance.is_in_group("toon_no_outline"):
		with_outline = false

	for surface_idx in mesh_instance.mesh.get_surface_count():
		var source := mesh_instance.get_active_material(surface_idx)
		if source == null:
			source = mesh_instance.mesh.surface_get_material(surface_idx)
		if source is ShaderMaterial and _is_toon_material(source as ShaderMaterial):
			var toon := (source as ShaderMaterial).duplicate() as ShaderMaterial
			toon.shader = TOON_SHADER
			toon.set_meta(&"toon_cel", true)
			toon.next_pass = _make_outline_material() if with_outline else null
			mesh_instance.set_surface_override_material(surface_idx, toon)
			continue

		var toon := make_toon_from(source)
		if with_outline:
			toon.next_pass = _make_outline_material()
		mesh_instance.set_surface_override_material(surface_idx, toon)


static func make_toon_from(source: Material) -> ShaderMaterial:
	var toon := ShaderMaterial.new()
	toon.shader = TOON_SHADER
	toon.set_meta(&"toon_cel", true)
	toon.set_shader_parameter("light_steps", LIGHT_STEPS)
	toon.set_shader_parameter("albedo_color", Color.WHITE)
	toon.set_shader_parameter("use_texture", false)

	if source is BaseMaterial3D:
		var base := source as BaseMaterial3D
		toon.set_shader_parameter("albedo_color", base.albedo_color)
		if base.albedo_texture != null:
			toon.set_shader_parameter("albedo_texture", base.albedo_texture)
			toon.set_shader_parameter("use_texture", true)
	elif source is ShaderMaterial:
		var sm := source as ShaderMaterial
		var tex: Variant = sm.get_shader_parameter("albedo_texture")
		if tex == null:
			tex = sm.get_shader_parameter("texture_albedo")
		if tex is Texture2D:
			toon.set_shader_parameter("albedo_texture", tex)
			toon.set_shader_parameter("use_texture", true)
		var color: Variant = sm.get_shader_parameter("albedo_color")
		if color is Color:
			toon.set_shader_parameter("albedo_color", color)

	return toon


static func _make_outline_material() -> StandardMaterial3D:
	var outline := StandardMaterial3D.new()
	outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline.albedo_color = OUTLINE_COLOR
	outline.cull_mode = BaseMaterial3D.CULL_FRONT
	outline.grow = true
	outline.grow_amount = OUTLINE_THICKNESS
	outline.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	return outline


static func _is_toon_material(mat: ShaderMaterial) -> bool:
	if mat.has_meta(&"toon_cel"):
		return true
	return mat.shader == TOON_SHADER
