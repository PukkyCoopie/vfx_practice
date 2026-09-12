extends Node3D

const SPRAY_SHADER: Shader = preload("res://shaders/frost_spray.gdshader")
const SMOKE_SPRITE_SHADER: Shader = preload("res://shaders/frost_smoke_sprite.gdshader")
const RIBBON_SHADER: Shader = preload("res://shaders/frost_ribbon.gdshader")
const SPARK_SHADER: Shader = preload("res://shaders/frost_spark.gdshader")
const GROUND_SHADER: Shader = preload("res://shaders/frost_ground.gdshader")

const RIBBON_SEGS := 40
const RIBBON_WIDTH := 0.025

@export_group("Placement")
@export var origin_height: float = 0.62
@export var origin_forward: float = 0.94

@export_group("Spray")
@export var spray_length: float = 3.2
@export var spray_width: float = 0.95
@export var spray_speed: float = 1.15
@export var spray_density: float = 1.0
@export var spray_lifetime: float = 1.05
@export var noise_strength: float = 0.85

@export_group("Ribbon")
@export var ribbon_count: int = 12
@export var ribbon_speed: float = 1.15
@export var ribbon_radius: float = 0.58
@export var ribbon_lifetime: float = 1.05

@export_group("Snow")
@export var snow_amount: float = 1.0
@export var snow_speed: float = 1.0

@export_group("Ground")
@export var ground_radius: float = 1.55
@export var ground_intensity: float = 0.85

@export_group("Cast Window")
@export var emit_start: float = 1.02
@export var emit_full: float = 1.28
@export var emit_fade_start: float = 3.16
@export var emit_end: float = 3.72

@export_group("Light")
@export var light_energy: float = 4.2
@export var light_range: float = 4.2
@export var light_color: Color = Color(0.58, 0.84, 1.0)

@export_group("Global")
@export var overall_intensity: float = 1.0

var _quad: QuadMesh
var _smoke_mat: ShaderMaterial
var _core_mat: ShaderMaterial
var _mist_mat: ShaderMaterial
var _spark_mat: ShaderMaterial
var _ribbon_mat: ShaderMaterial
var _ground_mat: ShaderMaterial
var _sprite_vp: SubViewport
var _core: GPUParticles3D
var _mist: GPUParticles3D
var _sparks_near: GPUParticles3D
var _sparks_far: GPUParticles3D
var _ground: MeshInstance3D
var _light: OmniLight3D
var _anim: AnimationPlayer
var _ribbons: Array[MeshInstance3D] = []
var _ribbon_state: Array[Dictionary] = []
var _ribbons_spawned_cast := 0
var _ribbon_spawn_dues: Array[float] = []
var _ribbon_was_in_cast := false
var _flick_seed := 0.0
var _smoke_time := 0.0
var _warming := false
var _warm_done := false


func _ready() -> void:
	add_to_group("vfx_no_toon")
	process_mode = Node.PROCESS_MODE_PAUSABLE
	position = Vector3(0.0, origin_height, origin_forward)
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE
	_smoke_mat = _make_smoke_sprite_material()
	_spawn_sprite_viewport()
	if "--capture" not in OS.get_cmdline_user_args():
		_spawn_sprite_overlay()
	_core_mat = _make_spray_material(0, 1)
	_mist_mat = _make_spray_material(1, 0)
	_spark_mat = _make_spark_material()
	_ribbon_mat = _make_ribbon_material()
	_ground_mat = _make_ground_material()
	_core = _make_core()
	add_child(_core)
	_mist = _make_mist()
	add_child(_mist)
	_sparks_near = _make_sparks("FrostSparksNear", true)
	add_child(_sparks_near)
	_sparks_far = _make_sparks("FrostSparksFar", false)
	add_child(_sparks_far)
	_spawn_ribbons()
	_spawn_ground()
	_spawn_light()
	_anim = _find_anim()
	_apply_emit_weight(0.0, 0.0)


func _process(delta: float) -> void:
	if _warming:
		return
	_smoke_time = fmod(_smoke_time + delta, 256.0)
	if is_instance_valid(_smoke_mat):
		_smoke_mat.set_shader_parameter("smoke_time", _smoke_time)
	var weight := _emit_weight(_anim_time())
	_apply_emit_weight(weight, delta)
	_update_ribbons(delta, weight)
	_update_shader_params()


func get_cast_time() -> float:
	return _anim_time()


func ensure_vfx_warm() -> void:
	if _warm_done:
		return
	if _warming:
		while _warming and is_inside_tree():
			await get_tree().process_frame
		return
	_warming = true
	var items: Array = [_core, _mist, _sparks_near, _sparks_far, _ground]
	for ribbon in _ribbons:
		items.append(ribbon)
	if is_instance_valid(_sprite_vp):
		_sprite_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await VfxWarmup.warm_nodes(self, items)
	await VfxWarmup.wait_draw(self)
	_warming = false
	_warm_done = true


func _anim_time() -> float:
	if _anim == null or not is_instance_valid(_anim):
		_anim = _find_anim()
	if _anim == null or _anim.current_animation.is_empty():
		return 0.0
	return _anim.current_animation_position


func _emit_weight(time: float) -> float:
	if time < emit_start or time > emit_end:
		return 0.0
	if time < emit_full:
		return smoothstep(emit_start, emit_full, time)
	if time > emit_fade_start:
		return 1.0 - smoothstep(emit_fade_start, emit_end, time)
	return 1.0


func _apply_emit_weight(weight: float, delta: float) -> void:
	var scaled := weight * overall_intensity
	var emitting := weight > 0.001
	var dens := clampf(spray_density, 0.05, 2.5)
	var snow := clampf(snow_amount, 0.05, 2.5)
	# Keep amount_ratio stable while casting. Fading via shader cast_weight avoids
	# per-frame particle pool thrash (looks like flicker / double spawn).
	if is_instance_valid(_core):
		_core.emitting = emitting
		_core.amount_ratio = dens if emitting else 0.0
	if is_instance_valid(_mist):
		_mist.emitting = emitting
		_mist.amount_ratio = dens * 0.85 if emitting else 0.0
	if is_instance_valid(_sparks_near):
		_sparks_near.emitting = emitting
		_sparks_near.amount_ratio = snow if emitting else 0.0
	if is_instance_valid(_sparks_far):
		_sparks_far.emitting = emitting
		_sparks_far.amount_ratio = snow if emitting else 0.0
	if is_instance_valid(_ground):
		_ground.visible = emitting
	if is_instance_valid(_core_mat):
		_core_mat.set_shader_parameter("cast_weight", weight)
	if is_instance_valid(_mist_mat):
		_mist_mat.set_shader_parameter("cast_weight", weight)
	if is_instance_valid(_ground_mat):
		_ground_mat.set_shader_parameter("intensity", ground_intensity * scaled)
		_ground_mat.set_shader_parameter("overall_intensity", overall_intensity)
	if is_instance_valid(_ribbon_mat):
		_ribbon_mat.set_shader_parameter("overall_intensity", overall_intensity * weight)
	if _light == null or not is_instance_valid(_light):
		return
	_light.visible = emitting
	if not emitting:
		_light.light_energy = 0.0
		return
	_flick_seed += delta
	var flick := (
		0.82
		+ 0.12 * sin(_flick_seed * 14.7)
		+ 0.08 * sin(_flick_seed * 27.2 + 1.1)
		+ 0.05 * sin(_flick_seed * 41.5 + 2.4)
	)
	var size_f := (
		0.88
		+ 0.1 * sin(_flick_seed * 11.4 + 0.6)
		+ 0.07 * sin(_flick_seed * 19.8 + 2.8)
	)
	_light.light_energy = light_energy * scaled * clampf(flick, 0.65, 1.15)
	_light.omni_range = light_range * clampf(size_f, 0.8, 1.12)
	_light.light_color = light_color.lerp(Color(0.85, 0.96, 1.0), clampf((flick - 0.82) * 2.0, 0.0, 0.4))
	_light.position = Vector3(0.0, 0.1, spray_length * 0.34)


func _update_shader_params() -> void:
	if is_instance_valid(_smoke_mat):
		_smoke_mat.set_shader_parameter("noise_strength", noise_strength)
	if is_instance_valid(_core_mat):
		_core_mat.set_shader_parameter("overall_intensity", overall_intensity)
		_core_mat.set_shader_parameter("density", spray_density)
	if is_instance_valid(_mist_mat):
		_mist_mat.set_shader_parameter("overall_intensity", overall_intensity)
		_mist_mat.set_shader_parameter("density", spray_density * 0.7)
	if is_instance_valid(_spark_mat):
		_spark_mat.set_shader_parameter("overall_intensity", overall_intensity)
	if is_instance_valid(_ground):
		var span := ground_radius * 2.0
		_ground.scale = Vector3(span * 0.85, 1.0, span * 1.35)
		_ground.position = Vector3(0.0, -origin_height + 0.02, spray_length * 0.45)


func _find_anim() -> AnimationPlayer:
	var host := get_parent()
	if host == null:
		return null
	var found := host.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		return null
	return found[0] as AnimationPlayer


func _make_smoke_sprite_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SMOKE_SPRITE_SHADER
	mat.set_shader_parameter("smoke_time", 0.0)
	mat.set_shader_parameter("smoke_speed", 1.85)
	mat.set_shader_parameter("noise_strength", noise_strength)
	mat.set_shader_parameter("threshold", 0.36)
	mat.render_priority = 0
	return mat


func _make_spray_material(layer: int, priority: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SPRAY_SHADER
	mat.render_priority = priority
	mat.set_shader_parameter("layer_mode", layer)
	mat.set_shader_parameter("smoke_alpha", 0.82 if layer == 0 else 0.5)
	mat.set_shader_parameter("cast_weight", 0.0)
	mat.set_shader_parameter("density", 1.0)
	mat.set_shader_parameter("core_boost", 1.2 if layer == 0 else 0.4)
	mat.set_shader_parameter("overall_intensity", overall_intensity)
	mat.set_shader_parameter("toon_steps", 3)
	if is_instance_valid(_sprite_vp):
		mat.set_shader_parameter("sprite", _sprite_vp.get_texture())
	return mat


func _spawn_sprite_viewport() -> void:
	var vp := SubViewport.new()
	vp.name = "SmokeSpriteViewport"
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
	sprite.material_override = _smoke_mat
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


func _make_spark_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SPARK_SHADER
	mat.render_priority = 2
	mat.set_shader_parameter("glow", 3.2)
	mat.set_shader_parameter("overall_intensity", overall_intensity)
	return mat


func _make_ribbon_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = RIBBON_SHADER
	mat.render_priority = 3
	mat.set_shader_parameter("color", Color(0.78, 0.94, 1.0, 1.0))
	mat.set_shader_parameter("intensity", 1.35)
	mat.set_shader_parameter("overall_intensity", overall_intensity)
	return mat


func _make_ground_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.render_priority = -2
	mat.set_shader_parameter("intensity", ground_intensity)
	mat.set_shader_parameter("overall_intensity", overall_intensity)
	mat.set_shader_parameter("noise_amount", 0.55)
	return mat


func _make_core() -> GPUParticles3D:
	var gpu := GPUParticles3D.new()
	gpu.name = "SprayCore"
	gpu.add_to_group("vfx_no_toon")
	gpu.amount = int(round(100.0 * clampf(spray_density, 0.4, 2.0)))
	gpu.lifetime = spray_lifetime
	gpu.preprocess = 0.0
	gpu.explosiveness = 0.0
	gpu.randomness = 0.62
	gpu.amount_ratio = 0.0
	gpu.fixed_fps = 0
	gpu.interpolate = true
	gpu.fract_delta = true
	gpu.local_coords = true
	gpu.visibility_aabb = AABB(Vector3(-4.5, -2.2, -0.6), Vector3(9.0, 4.6, spray_length + 2.2))
	gpu.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gpu.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	gpu.extra_cull_margin = 4.0
	gpu.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	gpu.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	gpu.draw_pass_1 = _quad
	gpu.material_override = _core_mat
	gpu.process_material = _make_core_process()
	return gpu


func _make_mist() -> GPUParticles3D:
	var gpu := GPUParticles3D.new()
	gpu.name = "SprayMist"
	gpu.add_to_group("vfx_no_toon")
	gpu.amount = int(round(52.0 * clampf(spray_density, 0.4, 2.0)))
	gpu.lifetime = spray_lifetime * 1.25
	gpu.preprocess = 0.0
	gpu.explosiveness = 0.0
	gpu.randomness = 0.7
	gpu.amount_ratio = 0.0
	gpu.fixed_fps = 0
	gpu.interpolate = true
	gpu.fract_delta = true
	gpu.local_coords = true
	gpu.visibility_aabb = AABB(Vector3(-4.5, -2.2, -0.6), Vector3(9.0, 4.6, spray_length + 2.2))
	gpu.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gpu.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	gpu.extra_cull_margin = 4.0
	gpu.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	gpu.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	gpu.draw_pass_1 = _quad
	gpu.material_override = _mist_mat
	gpu.process_material = _make_mist_process()
	return gpu


func _make_core_process() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	var speed := clampf(spray_speed, 0.4, 2.5)
	var width := clampf(spray_width, 0.3, 2.5)
	pm.lifetime_randomness = 0.5
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.18 * width, 0.06, 0.04)
	pm.direction = Vector3(0.0, 0.04, 1.0)
	pm.spread = 28.0 * width
	pm.flatness = 0.55
	pm.gravity = Vector3(0.0, 0.35, 0.0)
	pm.radial_accel_min = 0.15
	pm.radial_accel_max = 1.1
	pm.particle_flag_align_y = false
	pm.initial_velocity_min = 5.4 * speed
	pm.initial_velocity_max = 9.2 * speed
	pm.damping_min = 3.8
	pm.damping_max = 11.5
	pm.linear_accel_min = -5.5
	pm.linear_accel_max = -1.2
	pm.damping_curve = _curve_texture(PackedVector2Array([
		Vector2(0.0, 0.1),
		Vector2(0.22, 0.48),
		Vector2(0.55, 0.9),
		Vector2(1.0, 1.0),
	]))
	pm.velocity_limit_curve = _curve_texture(PackedVector2Array([
		Vector2(0.0, 9.0),
		Vector2(0.14, 5.0),
		Vector2(0.4, 2.2),
		Vector2(0.7, 0.6),
		Vector2(1.0, 0.1),
	]))
	pm.scale_min = 0.38
	pm.scale_max = 0.82
	pm.scale_curve = _curve_texture(PackedVector2Array([
		Vector2(0.0, 0.45),
		Vector2(0.12, 0.95),
		Vector2(0.45, 1.25),
		Vector2(0.78, 1.05),
		Vector2(1.0, 0.55),
	]))
	pm.color_ramp = _color_ramp(
		PackedColorArray([
			Color(0.38, 0.82, 1.0, 0.0),
			Color(0.48, 0.88, 1.0, 0.9),
			Color(0.82, 0.96, 1.0, 0.85),
			Color(0.97, 0.99, 1.0, 0.7),
			Color(0.94, 0.98, 1.0, 0.35),
			Color(0.9, 0.96, 1.0, 0.0),
		]),
		PackedFloat32Array([0.0, 0.08, 0.28, 0.55, 0.82, 1.0])
	)
	pm.hue_variation_min = 0.0
	pm.hue_variation_max = 0.0
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = 0.0
	pm.angular_velocity_max = 0.0
	pm.anim_offset_min = 0.0
	pm.anim_offset_max = 1.0
	pm.anim_speed_min = 0.0
	pm.anim_speed_max = 0.0
	return pm


func _make_mist_process() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	var speed := clampf(spray_speed, 0.4, 2.5)
	var width := clampf(spray_width, 0.3, 2.5)
	pm.lifetime_randomness = 0.58
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.28 * width, 0.1, 0.06)
	pm.direction = Vector3(0.0, 0.05, 1.0)
	pm.spread = 42.0 * width
	pm.flatness = 0.4
	pm.gravity = Vector3(0.0, 0.55, 0.0)
	pm.radial_accel_min = 0.4
	pm.radial_accel_max = 2.0
	pm.particle_flag_align_y = false
	pm.initial_velocity_min = 3.8 * speed
	pm.initial_velocity_max = 7.0 * speed
	pm.damping_min = 4.2
	pm.damping_max = 12.0
	pm.linear_accel_min = -4.8
	pm.linear_accel_max = -0.8
	pm.damping_curve = _curve_texture(PackedVector2Array([
		Vector2(0.0, 0.12),
		Vector2(0.25, 0.55),
		Vector2(0.6, 0.92),
		Vector2(1.0, 1.0),
	]))
	pm.velocity_limit_curve = _curve_texture(PackedVector2Array([
		Vector2(0.0, 7.5),
		Vector2(0.18, 4.2),
		Vector2(0.45, 1.8),
		Vector2(0.75, 0.5),
		Vector2(1.0, 0.1),
	]))
	pm.scale_min = 0.65
	pm.scale_max = 1.2
	pm.scale_curve = _curve_texture(PackedVector2Array([
		Vector2(0.0, 0.4),
		Vector2(0.15, 0.9),
		Vector2(0.5, 1.4),
		Vector2(0.82, 1.15),
		Vector2(1.0, 0.65),
	]))
	pm.color_ramp = _color_ramp(
		PackedColorArray([
			Color(0.4, 0.8, 1.0, 0.0),
			Color(0.55, 0.88, 1.0, 0.55),
			Color(0.82, 0.95, 1.0, 0.45),
			Color(0.94, 0.98, 1.0, 0.22),
			Color(0.92, 0.97, 1.0, 0.0),
		]),
		PackedFloat32Array([0.0, 0.12, 0.4, 0.75, 1.0])
	)
	pm.hue_variation_min = 0.0
	pm.hue_variation_max = 0.0
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = 0.0
	pm.angular_velocity_max = 0.0
	pm.anim_offset_min = 0.0
	pm.anim_offset_max = 1.0
	return pm


func _make_sparks(node_name: String, near_band: bool) -> GPUParticles3D:
	var gpu := GPUParticles3D.new()
	gpu.name = node_name
	gpu.add_to_group("vfx_no_toon")
	var total := int(round(38.0 * clampf(snow_amount, 0.3, 2.5)))
	# Bias spawn toward the nozzle (near band denser).
	gpu.amount = maxi(int(round(float(total) * (0.72 if near_band else 0.28))), 6)
	gpu.lifetime = 0.85
	gpu.preprocess = 0.0
	gpu.explosiveness = 0.0
	gpu.randomness = 0.7
	gpu.amount_ratio = 0.0
	gpu.fixed_fps = 0
	gpu.interpolate = true
	gpu.fract_delta = true
	gpu.local_coords = true
	gpu.visibility_aabb = AABB(Vector3(-4.5, -2.2, -0.6), Vector3(9.0, 4.6, spray_length + 2.2))
	gpu.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gpu.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	gpu.extra_cull_margin = 4.0
	gpu.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	gpu.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	gpu.draw_pass_1 = _quad
	gpu.material_override = _spark_mat
	gpu.process_material = _make_spark_process(near_band)
	return gpu


func _make_spark_process(near_band: bool) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	var speed := clampf(snow_speed, 0.3, 2.5)
	var width := clampf(spray_width, 0.3, 2.5)
	var cone_spread := 28.0 * width
	var len_z := spray_length
	pm.lifetime_randomness = 0.35
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	if near_band:
		# Dense near-nozzle band.
		pm.emission_box_extents = Vector3(0.38 * width, 0.18, len_z * 0.24)
		pm.emission_shape_offset = Vector3(0.0, 0.0, len_z * 0.24)
	else:
		# Sparse forward band.
		pm.emission_box_extents = Vector3(0.85 * width, 0.3, len_z * 0.26)
		pm.emission_shape_offset = Vector3(0.0, 0.0, len_z * 0.74)
	pm.direction = Vector3(0.0, 0.03, 1.0)
	pm.spread = cone_spread + 14.0
	pm.flatness = 0.5
	pm.gravity = Vector3(0.0, -0.12, 0.0)
	pm.radial_accel_min = 0.25
	pm.radial_accel_max = 1.2
	pm.particle_flag_align_y = false
	# Keep a hard floor on speed so crystals don't stall mid-air.
	pm.initial_velocity_min = 6.5 * speed
	pm.initial_velocity_max = 11.5 * speed
	pm.damping_min = 0.35
	pm.damping_max = 1.4
	pm.linear_accel_min = -0.4
	pm.linear_accel_max = 0.35
	pm.velocity_limit_curve = _curve_texture(PackedVector2Array([
		Vector2(0.0, 14.0),
		Vector2(0.35, 9.5),
		Vector2(0.7, 6.5),
		Vector2(1.0, 4.2),
	]))
	pm.scale_min = 0.035
	pm.scale_max = 0.08
	pm.scale_curve = _curve_texture(PackedVector2Array([
		Vector2(0.0, 1.0),
		Vector2(0.5, 1.0),
		Vector2(1.0, 1.0),
	]))
	pm.color_ramp = _color_ramp(
		PackedColorArray([
			Color(1.0, 1.0, 1.0, 0.0),
			Color(0.95, 0.98, 1.0, 1.0),
			Color(0.8, 0.93, 1.0, 1.0),
			Color(0.65, 0.88, 1.0, 0.85),
			Color(0.5, 0.8, 1.0, 0.0),
		]),
		PackedFloat32Array([0.0, 0.1, 0.45, 0.78, 1.0])
	)
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -40.0
	pm.angular_velocity_max = 40.0
	pm.anim_offset_min = 0.0
	pm.anim_offset_max = 1.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.28
	pm.turbulence_noise_scale = 1.4
	pm.turbulence_noise_speed = Vector3(0.15, 0.3, 0.55)
	pm.turbulence_noise_speed_random = 0.18
	pm.turbulence_influence_min = 0.02
	pm.turbulence_influence_max = 0.08
	return pm


func _spawn_ribbons() -> void:
	_ribbons.clear()
	_ribbon_state.clear()
	_ribbons_spawned_cast = 0
	_ribbon_spawn_dues.clear()
	_ribbon_was_in_cast = false
	# Pool covers one full cast so rings never share a slot mid-life.
	var count := clampi(ribbon_count, 1, 16)
	for i in count:
		var mesh_i := MeshInstance3D.new()
		mesh_i.name = "Ribbon%d" % i
		mesh_i.add_to_group("vfx_no_toon")
		mesh_i.material_override = _ribbon_mat
		mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_i.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mesh_i.extra_cull_margin = 4.0
		mesh_i.visible = false
		add_child(mesh_i)
		_ribbons.append(mesh_i)
		_ribbon_state.append(_blank_ring_state(float(i) * 17.3))


func _blank_ring_state(seed_v: float) -> Dictionary:
	return {
		"alive": false,
		"age": 0.0,
		"life": ribbon_lifetime,
		"phase": 0.0,
		"spin": 1.0,
		"r0": ribbon_radius * 0.35,
		"r1": ribbon_radius * 1.6,
		"z0": 0.1,
		"z1": spray_length * 0.55,
		"band": RIBBON_WIDTH,
		"tilt": 0.0,
		"squash": 0.82,
		"warp": 0.05,
		"gap_center": 0.0,
		"gap_width": 1.2,
		"slant": 0.04,
		"seed": seed_v,
	}


func _rebuild_ribbon_spawn_dues(want: int) -> void:
	_ribbon_spawn_dues.clear()
	var spawn_start := emit_start
	var spawn_end := emit_fade_start
	var span := maxf(spawn_end - spawn_start, 0.05)
	var interval := span / float(want)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in want:
		var base := spawn_start + (float(i) + 0.5) * interval
		# Keep order-ish but break metronome feel (±40% of slot).
		var jitter := interval * rng.randf_range(-0.4, 0.4)
		_ribbon_spawn_dues.append(clampf(base + jitter, spawn_start, spawn_end))
	_ribbon_spawn_dues.sort()


func _update_ribbons(delta: float, weight: float) -> void:
	if _ribbons.is_empty():
		return

	var anim_t := _anim_time()
	var in_cast := anim_t >= emit_start and anim_t <= emit_end
	var want := clampi(ribbon_count, 1, 16)
	if in_cast and not _ribbon_was_in_cast:
		_ribbons_spawned_cast = 0
		_rebuild_ribbon_spawn_dues(want)
	_ribbon_was_in_cast = in_cast

	while _ribbons.size() < want:
		var mesh_i := MeshInstance3D.new()
		mesh_i.name = "Ribbon%d" % _ribbons.size()
		mesh_i.add_to_group("vfx_no_toon")
		mesh_i.material_override = _ribbon_mat
		mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_i.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mesh_i.extra_cull_margin = 4.0
		mesh_i.visible = false
		add_child(mesh_i)
		_ribbons.append(mesh_i)
		_ribbon_state.append(_blank_ring_state(float(_ribbons.size()) * 17.3))

	# Exactly ribbon_count rings per cast, with randomized timing offsets.
	# Last dues stay before fade_start — earlier than smoke (runs to emit_end).
	if in_cast and _ribbons_spawned_cast < want and _ribbon_spawn_dues.size() == want:
		while _ribbons_spawned_cast < want:
			var due: float = _ribbon_spawn_dues[_ribbons_spawned_cast]
			if anim_t < due:
				break
			var slot := _find_free_ribbon_slot()
			if slot < 0:
				break
			_spawn_ribbon(slot)
			_ribbons_spawned_cast += 1

	# Living ribbons finish their life even after smoke weight drops.
	for i in _ribbons.size():
		var st: Dictionary = _ribbon_state[i]
		if not st.get("alive", false):
			if is_instance_valid(_ribbons[i]):
				_ribbons[i].visible = false
			continue
		st["age"] = float(st["age"]) + delta
		var life: float = maxf(float(st["life"]), 0.05)
		var t := float(st["age"]) / life
		if t >= 1.0:
			st["alive"] = false
			_ribbons[i].visible = false
			continue
		var fade := smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.78, 1.0, t))
		var draw_w := weight if weight > 0.05 else 1.0
		_ribbons[i].mesh = _make_ribbon_mesh(st, t, fade * draw_w)
		_ribbons[i].visible = true


func _find_free_ribbon_slot() -> int:
	for i in _ribbons.size():
		if not _ribbon_state[i].get("alive", false):
			return i
	return -1


func _spawn_ribbon(index: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var st: Dictionary = _ribbon_state[index]
	st["alive"] = true
	st["age"] = 0.0
	st["life"] = ribbon_lifetime * rng.randf_range(0.85, 1.35)
	st["phase"] = rng.randf() * TAU
	# Always clockwise; speed varies per ring.
	st["spin"] = rng.randf_range(0.5, 1.4) * ribbon_speed
	# Tighter size spread: mins larger, maxes smaller.
	var size_roll := rng.randf()
	var size_mul := 0.82 if size_roll < 0.3 else (1.0 if size_roll < 0.7 else 1.18)
	st["r0"] = ribbon_radius * rng.randf_range(0.26, 0.42) * size_mul
	st["r1"] = ribbon_radius * rng.randf_range(1.35, 1.95) * size_mul
	st["z0"] = rng.randf_range(0.03, spray_length * 0.1)
	st["z1"] = spray_length * rng.randf_range(0.55, 0.82)
	st["band"] = RIBBON_WIDTH * rng.randf_range(0.95, 1.35) * size_mul
	st["tilt"] = rng.randf_range(-0.28, 0.28)
	st["squash"] = rng.randf_range(0.72, 1.0)
	st["warp"] = rng.randf_range(0.03, 0.08)
	st["slant"] = rng.randf_range(0.03, 0.09)
	# Single C-gap: leave a random open arc empty.
	st["gap_center"] = rng.randf() * TAU
	st["gap_width"] = rng.randf_range(0.7, 2.2)
	st["seed"] = rng.randf() * 100.0
	_ribbon_state[index] = st


func _ring_gap_mask(ang: float, st: Dictionary, life_t: float) -> float:
	# Hard C-gap occupancy: 1 = filled body, 0 = open sector.
	return 1.0 if _ring_tip_scale(ang, st, life_t) > 0.001 else 0.0


func _ring_tip_scale(ang: float, st: Dictionary, life_t: float) -> float:
	# Width taper from each C tip. Each tip spans ~1/3 of the filled arc.
	var spin: float = float(st["spin"])
	var gap_c: float = float(st["gap_center"]) - life_t * spin * TAU
	var gap_w: float = float(st["gap_width"])
	var half := gap_w * 0.5
	var d := absf(angle_difference(ang, gap_c))
	if d <= half:
		return 0.0
	var filled := maxf(TAU - gap_w, 0.35)
	var tip_len := filled / 3.0
	var into := d - half
	if into >= tip_len:
		return 1.0
	# Smooth ramp tip → full over tip_len.
	return smoothstep(0.0, tip_len, into)


func _make_ribbon_mesh(st: Dictionary, life_t: float, fade: float) -> ArrayMesh:
	var expand_t := 1.0 - pow(1.0 - life_t, 1.12)
	var travel_t := pow(life_t, 1.05)
	# Clockwise rotation.
	var phase: float = float(st["phase"]) - float(st["spin"]) * life_t * TAU
	var rad_base := lerpf(float(st["r0"]), float(st["r1"]), expand_t)
	var z_base := lerpf(float(st["z0"]), float(st["z1"]), travel_t)
	var tilt: float = float(st["tilt"])
	var band: float = float(st.get("band", RIBBON_WIDTH))
	var squash: float = float(st.get("squash", 0.82))
	var warp: float = float(st.get("warp", 0.05))
	var salt: float = float(st["seed"])
	var cam := _cam_local()

	var st_mesh := SurfaceTool.new()
	st_mesh.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Centerline + half-width. View-aligned extrusion keeps width from any angle.
	var pts: Array[Vector3] = []
	var halves: Array[float] = []
	var masks: Array[float] = []
	for i in RIBBON_SEGS + 1:
		var u := float(i) / float(RIBBON_SEGS)
		var ang := phase + u * TAU
		var tip := _ring_tip_scale(ang, st, life_t)
		var wobble := sin(ang * 2.0 + salt) * 0.035 + sin(ang * 5.0 - salt * 1.3) * 0.025
		wobble += sin(ang * 3.0 + life_t * 5.0 + salt) * warp * 0.65
		var rad := rad_base * (1.0 + wobble)
		var p := Vector3(cos(ang) * rad, sin(ang) * rad * squash + tilt * rad * 0.2, z_base)
		var band_wobble := 1.0 + 0.12 * sin(ang * 3.0 + salt)
		var half := band * 0.5 * tip * band_wobble
		pts.append(p)
		halves.append(half)
		masks.append(tip)

	# Shared camera-facing edges with proper miter joins (no outer gaps / inner overlaps).
	var lefts: Array[Vector3] = []
	var rights: Array[Vector3] = []
	var prev_across := Vector3.ZERO
	var count := pts.size()
	for i in count:
		var i0 := maxi(i - 1, 0)
		var i1 := mini(i + 1, count - 1)
		var tangent := pts[i1] - pts[i0]
		if tangent.length_squared() < 0.00001:
			tangent = Vector3(0.0, 0.0, 1.0)
		else:
			tangent = tangent.normalized()
		var across := tangent.cross(cam - pts[i])
		if across.length_squared() < 0.00001:
			across = tangent.cross(Vector3.UP)
		if across.length_squared() < 0.00001:
			across = Vector3.RIGHT
		across = across.normalized()
		if prev_across.length_squared() > 0.0001 and across.dot(prev_across) < 0.0:
			across = -across
		# Miter from adjacent segment normals so shared joints stay continuous.
		var miter := across
		if i > 0 and i < count - 1:
			var t_a := pts[i] - pts[i - 1]
			var t_b := pts[i + 1] - pts[i]
			if t_a.length_squared() > 0.00001 and t_b.length_squared() > 0.00001:
				t_a = t_a.normalized()
				t_b = t_b.normalized()
				var n_a := t_a.cross(cam - pts[i])
				var n_b := t_b.cross(cam - pts[i])
				if n_a.length_squared() > 0.00001 and n_b.length_squared() > 0.00001:
					n_a = n_a.normalized()
					n_b = n_b.normalized()
					if n_a.dot(across) < 0.0:
						n_a = -n_a
					if n_b.dot(across) < 0.0:
						n_b = -n_b
					var m := n_a + n_b
					if m.length_squared() > 0.0004:
						miter = m.normalized()
						var keep := maxf(miter.dot(n_a), 0.35)
						miter *= 1.0 / keep
		prev_across = across
		var h: float = halves[i]
		lefts.append(pts[i] + miter * h)
		rights.append(pts[i] - miter * h)

	for i in RIBBON_SEGS:
		var m0: float = masks[i]
		var m1: float = masks[i + 1]
		if m0 < 0.04 and m1 < 0.04:
			continue
		var u0 := float(i) / float(RIBBON_SEGS)
		var u1 := float(i + 1) / float(RIBBON_SEGS)
		var a_seg := fade * ((m0 + m1) * 0.5)
		var col := Color(1.0, 1.0, 1.0, a_seg)
		_add_tri(st_mesh, lefts[i], rights[i], rights[i + 1], Vector2(1.0, u0), Vector2(0.0, u0), Vector2(0.0, u1), col)
		_add_tri(st_mesh, lefts[i], rights[i + 1], lefts[i + 1], Vector2(1.0, u0), Vector2(0.0, u1), Vector2(1.0, u1), col)

	st_mesh.index()
	return st_mesh.commit()


func _cam_local() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3(0.0, 1.0, 0.0)
	return to_local(cam.global_position)


func _add_tri(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	uv_a: Vector2,
	uv_b: Vector2,
	uv_c: Vector2,
	col: Color
) -> void:
	st.set_color(col)
	st.set_uv(uv_a)
	st.add_vertex(a)
	st.set_color(col)
	st.set_uv(uv_b)
	st.add_vertex(b)
	st.set_color(col)
	st.set_uv(uv_c)
	st.add_vertex(c)


func _spawn_ground() -> void:
	_ground = MeshInstance3D.new()
	_ground.name = "GroundGlow"
	_ground.add_to_group("vfx_no_toon")
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	_ground.mesh = plane
	_ground.material_override = _ground_mat
	_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ground.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_ground.position = Vector3(0.0, -origin_height + 0.02, spray_length * 0.45)
	var span := ground_radius * 2.0
	_ground.scale = Vector3(span * 0.85, 1.0, span * 1.35)
	_ground.visible = false
	add_child(_ground)


func _spawn_light() -> void:
	_light = OmniLight3D.new()
	_light.name = "Glow"
	_light.position = Vector3(0.0, 0.1, spray_length * 0.34)
	_light.light_color = light_color
	_light.light_energy = 0.0
	_light.light_specular = 0.0
	_light.omni_range = light_range
	_light.omni_attenuation = 0.7
	_light.shadow_enabled = false
	_light.visible = false
	add_child(_light)


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
