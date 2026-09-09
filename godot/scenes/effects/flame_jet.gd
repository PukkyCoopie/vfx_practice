extends Node3D

const PARTICLE_SHADER: Shader = preload("res://shaders/flame_particle.gdshader")
const STAMP_SHADER: Shader = preload("res://shaders/flame_stamp.gdshader")
const SPARK_SHADER: Shader = preload("res://shaders/flame_spark.gdshader")

@export_group("Placement")
@export var origin_height: float = 0.62
@export var origin_forward: float = 0.94

@export_group("Stream")
@export var length: float = 3.2

@export_group("Cast Window")
@export var emit_start: float = 1.02
@export var emit_full: float = 1.28
@export var emit_fade_start: float = 3.16
@export var emit_end: float = 3.72

@export_group("Light")
@export var light_energy: float = 5.0
@export var light_range: float = 4.2
@export var light_color: Color = Color(1.0, 0.48, 0.12)

var _quad: QuadMesh
var _spark_mesh: ArrayMesh
var _flame_mat: ShaderMaterial
var _stamp_mat: ShaderMaterial
var _spark_mat: ShaderMaterial
var _sprite_vp: SubViewport
var _stream: GPUParticles3D
var _sparks: GPUParticles3D
var _light: OmniLight3D
var _anim: AnimationPlayer
var _flick_seed := 0.0
var _bite_time := 0.0
var _last_emit_weight := -1.0


func _ready() -> void:
	add_to_group("vfx_no_toon")
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = Vector3(0.0, origin_height, origin_forward)
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE
	_flame_mat = _make_sprite_material()
	_spawn_sprite_viewport()
	if "--capture" not in OS.get_cmdline_user_args():
		_spawn_sprite_overlay()
	_stamp_mat = _make_stamp_material()
	_spark_mat = _make_spark_material()
	_stream = _make_stream()
	add_child(_stream)
	_sparks = _make_sparks()
	add_child(_sparks)
	_spawn_light()
	_anim = _find_anim()
	_apply_emit_weight(0.0, 0.0)
	_warmup_particle_shaders()


func _process(delta: float) -> void:
	_bite_time = fmod(_bite_time + delta, 256.0)
	if is_instance_valid(_flame_mat):
		_flame_mat.set_shader_parameter("bite_time", _bite_time)
	_apply_emit_weight(_emit_weight(_anim_time()), delta)


func _anim_time() -> float:
	if _anim == null or not is_instance_valid(_anim):
		_anim = _find_anim()
	if _anim == null or _anim.current_animation.is_empty():
		return 0.0
	return _anim.current_animation_position


func get_cast_time() -> float:
	return _anim_time()


func _emit_weight(time: float) -> float:
	if time < emit_start or time > emit_end:
		return 0.0
	if time < emit_full:
		return smoothstep(emit_start, emit_full, time)
	if time > emit_fade_start:
		return 1.0 - smoothstep(emit_fade_start, emit_end, time)
	return 1.0


func _warmup_particle_shaders() -> void:
	# Compatibility compiles the generated particle process shader on first emit.
	# Turbulence makes that shader large; compile it at spawn, not mid-cast.
	if is_instance_valid(_sparks):
		_sparks.emitting = true
		_sparks.restart()
	if is_instance_valid(_stream):
		_stream.emitting = true
		_stream.restart()


func _apply_emit_weight(weight: float, delta: float) -> void:
	if not is_equal_approx(weight, _last_emit_weight):
		_last_emit_weight = weight
		if is_instance_valid(_stream):
			_stream.amount_ratio = weight
		if is_instance_valid(_sparks):
			_sparks.amount_ratio = weight
	if _light == null or not is_instance_valid(_light):
		return
	var on := weight > 0.001
	_light.visible = on
	if not on:
		_light.light_energy = 0.0
		return
	_flick_seed += delta
	var flick := (
		0.78
		+ 0.16 * sin(_flick_seed * 17.3)
		+ 0.1 * sin(_flick_seed * 29.8 + 1.4)
		+ 0.06 * sin(_flick_seed * 47.1 + 2.2)
	)
	var size_f := (
		0.86
		+ 0.12 * sin(_flick_seed * 13.6 + 0.7)
		+ 0.08 * sin(_flick_seed * 22.4 + 3.1)
	)
	_light.light_energy = light_energy * weight * clampf(flick, 0.62, 1.18)
	_light.omni_range = light_range * clampf(size_f, 0.78, 1.16)
	_light.light_color = light_color.lerp(Color(1.0, 0.72, 0.22), clampf((flick - 0.8) * 2.2, 0.0, 0.45))


func _find_anim() -> AnimationPlayer:
	var host := get_parent()
	if host == null:
		return null
	var found := host.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		return null
	return found[0] as AnimationPlayer


func _make_stream() -> GPUParticles3D:
	var gpu := GPUParticles3D.new()
	gpu.name = "Stream"
	gpu.add_to_group("vfx_no_toon")
	gpu.amount = 168
	gpu.lifetime = 1.18
	gpu.preprocess = 0.0
	gpu.explosiveness = 0.0
	gpu.randomness = 0.68
	gpu.amount_ratio = 0.0
	gpu.fixed_fps = 0
	gpu.interpolate = true
	gpu.fract_delta = true
	gpu.local_coords = true
	gpu.visibility_aabb = AABB(Vector3(-4.5, -2.2, -0.6), Vector3(9.0, 4.6, length + 2.2))
	gpu.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gpu.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	gpu.extra_cull_margin = 4.0
	gpu.draw_order = GPUParticles3D.DRAW_ORDER_LIFETIME
	gpu.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Y_TO_VELOCITY
	gpu.draw_pass_1 = _quad
	gpu.material_override = _stamp_mat
	gpu.process_material = _make_process()
	return gpu


func _make_process() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.lifetime_randomness = 0.58
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.34, 0.07, 0.05)
	pm.direction = Vector3(0.0, 0.04, 1.0)
	pm.spread = 50.0
	pm.flatness = 0.96
	pm.gravity = Vector3(0.0, 1.55, 0.0)
	pm.radial_accel_min = 0.35
	pm.radial_accel_max = 2.15
	pm.particle_flag_align_y = true
	pm.initial_velocity_min = 6.4
	pm.initial_velocity_max = 11.2
	pm.damping_min = 4.8
	pm.damping_max = 13.8
	pm.linear_accel_min = -6.4
	pm.linear_accel_max = -1.5
	pm.damping_curve = _curve_texture(PackedVector2Array([
		Vector2(0.0, 0.12),
		Vector2(0.2, 0.5),
		Vector2(0.5, 0.92),
		Vector2(1.0, 1.0),
	]))
	pm.velocity_limit_curve = _curve_texture(PackedVector2Array([
		Vector2(0.0, 14.5),
		Vector2(0.16, 6.2),
		Vector2(0.4, 2.2),
		Vector2(0.66, 0.55),
		Vector2(1.0, 0.08),
	]))
	pm.scale_min = 0.55
	pm.scale_max = 1.18
	pm.scale_curve = _flame_scale_curve()
	pm.color_ramp = _color_ramp(
		PackedColorArray([
			Color(1.0, 0.96, 0.38, 0.0),
			Color(1.0, 0.96, 0.38, 1.0),
			Color(1.0, 0.48, 0.06, 1.0),
			Color(0.55, 0.07, 0.015, 1.0),
			Color(0.1, 0.06, 0.04, 0.92),
			Color(0.03, 0.025, 0.022, 0.0),
		]),
		PackedFloat32Array([0.0, 0.08, 0.18, 0.42, 0.78, 1.0])
	)
	pm.hue_variation_min = -0.07
	pm.hue_variation_max = 0.08
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -175.0
	pm.angular_velocity_max = 175.0
	pm.anim_offset_min = 0.0
	pm.anim_offset_max = 1.0
	pm.anim_speed_min = 0.0
	pm.anim_speed_max = 0.0
	return pm


func _make_sprite_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = PARTICLE_SHADER
	mat.set_shader_parameter("bite_time", 0.0)
	mat.set_shader_parameter("bite_speed", 0.55)
	mat.set_shader_parameter("bite_grow", 1.12)
	mat.render_priority = 1
	return mat


func _make_stamp_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = STAMP_SHADER
	if is_instance_valid(_sprite_vp):
		mat.set_shader_parameter("sprite", _sprite_vp.get_texture())
	mat.render_priority = 1
	return mat


func _make_spark_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SPARK_SHADER
	mat.set_shader_parameter("glow", 4.4)
	mat.render_priority = 2
	return mat


func _make_spark_cross_mesh(width: float, length: float) -> ArrayMesh:
	var hw := width * 0.5
	var hl := length * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_spark_quad_verts(st,
		Vector3(-hw, -hl, 0.0), Vector3(hw, -hl, 0.0),
		Vector3(hw, hl, 0.0), Vector3(-hw, hl, 0.0))
	_spark_quad_verts(st,
		Vector3(0.0, -hl, -hw), Vector3(0.0, -hl, hw),
		Vector3(0.0, hl, hw), Vector3(0.0, hl, -hw))
	st.generate_normals()
	return st.commit()


func _spark_quad_verts(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.set_uv(Vector2(0.0, 1.0))
	st.add_vertex(a)
	st.set_uv(Vector2(1.0, 1.0))
	st.add_vertex(b)
	st.set_uv(Vector2(1.0, 0.0))
	st.add_vertex(c)
	st.set_uv(Vector2(0.0, 1.0))
	st.add_vertex(a)
	st.set_uv(Vector2(1.0, 0.0))
	st.add_vertex(c)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(d)


func _make_sparks() -> GPUParticles3D:
	_spark_mesh = _make_spark_cross_mesh(0.34, 0.98)
	var gpu := GPUParticles3D.new()
	gpu.name = "Sparks"
	gpu.add_to_group("vfx_no_toon")
	gpu.amount = 22
	gpu.lifetime = 1.42
	gpu.preprocess = 0.12
	gpu.explosiveness = 0.0
	gpu.randomness = 0.72
	gpu.amount_ratio = 0.0
	gpu.fixed_fps = 0
	gpu.interpolate = true
	gpu.fract_delta = true
	gpu.local_coords = true
	gpu.visibility_aabb = AABB(Vector3(-4.5, -2.2, -0.6), Vector3(9.0, 4.6, length + 2.2))
	gpu.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gpu.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	gpu.extra_cull_margin = 4.0
	gpu.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	gpu.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Y_TO_VELOCITY
	gpu.draw_pass_1 = _spark_mesh
	gpu.material_override = _spark_mat
	gpu.process_material = _make_spark_process()
	return gpu


func _make_spark_process() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.lifetime_randomness = 0.48
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.34, 0.08, 0.05)
	pm.direction = Vector3(0.0, 0.04, 1.0)
	pm.spread = 52.0
	pm.flatness = 0.96
	pm.gravity = Vector3(0.0, 0.7, 0.0)
	pm.radial_accel_min = 0.3
	pm.radial_accel_max = 1.9
	pm.particle_flag_align_y = true
	pm.particle_flag_rotate_y = true
	pm.initial_velocity_min = 6.8
	pm.initial_velocity_max = 11.0
	pm.damping_min = 1.5
	pm.damping_max = 4.4
	pm.linear_accel_min = -1.8
	pm.linear_accel_max = -0.3
	pm.damping_curve = _curve_texture(PackedVector2Array([
		Vector2(0.0, 0.08),
		Vector2(0.28, 0.32),
		Vector2(0.62, 0.58),
		Vector2(1.0, 0.72),
	]))
	pm.velocity_limit_curve = _curve_texture(PackedVector2Array([
		Vector2(0.0, 14.5),
		Vector2(0.2, 9.2),
		Vector2(0.45, 5.6),
		Vector2(0.72, 3.2),
		Vector2(1.0, 1.8),
	]))
	pm.scale_min = 0.17
	pm.scale_max = 0.32
	pm.scale_curve = _curve_texture(PackedVector2Array([
		Vector2(0.0, 0.7),
		Vector2(0.1, 1.0),
		Vector2(0.55, 0.95),
		Vector2(1.0, 0.42),
	]))
	pm.color_ramp = _color_ramp(
		PackedColorArray([
			Color(2.1, 1.9, 1.15, 1.0),
			Color(1.7, 1.05, 0.32, 1.0),
			Color(1.35, 0.48, 0.08, 1.0),
			Color(0.95, 0.18, 0.02, 0.0),
		]),
		PackedFloat32Array([0.0, 0.32, 0.68, 1.0])
	)
	pm.hue_variation_min = -0.03
	pm.hue_variation_max = 0.04
	pm.angle_min = 0.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -360.0
	pm.angular_velocity_max = 360.0
	pm.anim_offset_min = 0.0
	pm.anim_offset_max = 1.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.85
	pm.turbulence_noise_scale = 1.8
	pm.turbulence_noise_speed = Vector3(0.22, 0.7, 0.32)
	pm.turbulence_noise_speed_random = 0.28
	pm.turbulence_influence_min = 0.04
	pm.turbulence_influence_max = 0.12
	pm.turbulence_initial_displacement_min = 0.0
	pm.turbulence_initial_displacement_max = 0.03
	pm.turbulence_influence_over_life = _curve_texture(PackedVector2Array([
		Vector2(0.0, 0.06),
		Vector2(0.3, 0.22),
		Vector2(0.7, 0.32),
		Vector2(1.0, 0.24),
	]))
	return pm


func _flame_scale_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.min_value = 0.0
	curve.max_value = 1.8
	curve.add_point(Vector2(0.0, 0.5), 0.0, 14.0)
	curve.add_point(Vector2(0.08, 0.86), 1.6, 3.6)
	curve.add_point(Vector2(0.28, 1.8), 0.0, 0.0)
	curve.add_point(Vector2(0.66, 1.8), 0.0, 0.0)
	curve.add_point(Vector2(1.0, 1.36), 0.0, 0.0)
	var tex := CurveTexture.new()
	tex.width = 256
	tex.curve = curve
	return tex


func _ease_out_curve(start_v: float, peak_v: float, peak_at: float = 1.0, end_v: float = -1.0) -> CurveTexture:
	var last_v := peak_v if end_v < 0.0 else end_v
	var curve := Curve.new()
	curve.min_value = 0.0
	curve.max_value = maxf(peak_v, last_v)
	curve.add_point(Vector2(0.0, start_v), 0.0, 4.2)
	if peak_at < 0.999:
		curve.add_point(Vector2(peak_at, peak_v), 0.0, 0.0)
		if end_v >= 0.0:
			curve.add_point(Vector2(0.66, peak_v), 0.0, 0.0)
	curve.add_point(Vector2(1.0, last_v), 0.0, 0.0)
	var tex := CurveTexture.new()
	tex.width = 256
	tex.curve = curve
	return tex


func _curve_texture(points: PackedVector2Array) -> CurveTexture:
	var curve := Curve.new()
	var ymax := 1.0
	for point in points:
		ymax = maxf(ymax, point.y)
	curve.min_value = 0.0
	curve.max_value = ymax
	for point in points:
		curve.add_point(point)
	var tex := CurveTexture.new()
	tex.width = 256
	tex.curve = curve
	return tex


func _color_ramp(colors: PackedColorArray, offsets: PackedFloat32Array) -> GradientTexture1D:
	var grad := Gradient.new()
	grad.offsets = offsets
	grad.colors = colors
	var tex := GradientTexture1D.new()
	tex.width = 128
	tex.gradient = grad
	return tex


func _spawn_sprite_viewport() -> void:
	var vp := SubViewport.new()
	vp.name = "SpriteViewport"
	vp.size = Vector2i(1024, 1024)
	vp.transparent_bg = true
	vp.handle_input_locally = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	_sprite_vp = vp
	add_child(vp)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.0
	cam.position = Vector3(0.0, 0.0, 2.0)
	cam.current = true
	vp.add_child(cam)

	var sprite := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	sprite.mesh = quad
	sprite.material_override = _flame_mat
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vp.add_child(sprite)


func _spawn_sprite_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SpritePreview"
	layer.layer = 12
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var frame := PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	frame.anchor_left = 1.0
	frame.anchor_top = 1.0
	frame.anchor_right = 1.0
	frame.anchor_bottom = 1.0
	frame.offset_left = -236.0
	frame.offset_top = -326.0
	frame.offset_right = -16.0
	frame.offset_bottom = -106.0
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.09, 0.92)
	style.set_border_width_all(1)
	style.border_color = Color(0.22, 0.22, 0.24, 1.0)
	style.set_content_margin_all(6.0)
	frame.add_theme_stylebox_override("panel", style)
	root.add_child(frame)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	frame.add_child(stack)

	var title := Label.new()
	title.text = "Particle sprites"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)

	var stage := Control.new()
	stage.custom_minimum_size = Vector2(208, 208)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(stage)

	var checker := ColorRect.new()
	checker.set_anchors_preset(Control.PRESET_FULL_RECT)
	checker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var checker_mat := ShaderMaterial.new()
	var checker_shader := Shader.new()
	checker_shader.code = """
shader_type canvas_item;
void fragment() {
	vec2 cell = floor(UV * 8.0);
	float parity = mod(cell.x + cell.y, 2.0);
	COLOR = vec4(mix(vec3(0.14), vec3(0.2), parity), 1.0);
}
"""
	checker_mat.shader = checker_shader
	checker.material = checker_mat
	stage.add_child(checker)

	var view := TextureRect.new()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(_sprite_vp):
		view.texture = _sprite_vp.get_texture()
	stage.add_child(view)


func _spawn_light() -> void:
	_light = OmniLight3D.new()
	_light.name = "Glow"
	_light.position = Vector3(0.0, 0.12, length * 0.34)
	_light.light_color = light_color
	_light.light_energy = 0.0
	_light.light_specular = 0.0
	_light.omni_range = light_range
	_light.omni_attenuation = 0.7
	_light.shadow_enabled = false
	_light.visible = false
	add_child(_light)
