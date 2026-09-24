extends Node

const FLAME_SHADER: Shader = preload("res://shaders/fire_tile_flames.gdshader")
const SPARK_SHADER: Shader = preload("res://shaders/fire_tile_spark.gdshader")
const RIBBON_SHADER: Shader = preload("res://shaders/fire_tile_ribbons.gdshader")
const MOTION_SCRIPT := preload("res://scenes/effects/fire_tile_motion.gd")

const REF_SIDE := 106.0
const REF_CHAMFER := 5.0
## Match Words & Wizards letter_tile.gd typography, including its size cap.
const LETTER_FONT: Font = preload("res://ui/fonts/RobotoSlab-Black.ttf")
const FONT_SIZE_RATIO := 0.462
const FONT_SIZE_MIN := 14
const FONT_SIZE_MAX := 44
const TEXT_MARGIN := 4.0
## Extra canvas above and beside the tile so flame tails can leave the cell.
const PAD_RATIO := 1.0

@export var studio_hide_stage: bool = true
## Waw's standard 750-wide board: (466 - 2*8 - 3*4) / 4.
## Set this to the board's live cell size when embedding in a scaled layout.
@export var tile_side: float = 109.5
## Capture window for the gallery sheet. The live flame loops on its own clock.
@export var emit_end: float = 2.0
## Rasterized once, then shaded by the same heat field as the tile.
@export var letter: String = "W":
	set(value):
		letter = value.left(1).to_upper()
		if _letter_label != null:
			_letter_label.text = letter
			_letter_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

var _mat: ShaderMaterial
var _ribbon_mat: ShaderMaterial
var _ribbons: ColorRect
var _letter_viewport: SubViewport
var _letter_label: Label
var _spark_mat: ShaderMaterial
var _holder: Control
var _flames: ColorRect
var _sparks: GPUParticles2D
var _side_sparks: Array[GPUParticles2D] = []
var _time := 0.0
var _side := 120.0
var _pad := 74.0
var _motion: Node
var _motion_velocity := Vector2.ZERO
var _wind_angle := -PI * 0.5
var _wind_strength := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_motion = MOTION_SCRIPT.new()
	add_child(_motion)
	_motion.setup(_holder, _side)
	_motion.velocity_sampled.connect(set_motion_velocity)
	if "--capture" in OS.get_cmdline_user_args():
		_motion.set_process(false)
		_motion.set_process_input(false)
		_motion.set_process_unhandled_input(false)
	else:
		var hint := Label.new()
		hint.text = "Drag tile  /  Click empty space to fly  /  R to reset"
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		hint.offset_top = -112.0
		hint.offset_bottom = -88.0
		_holder.get_parent().add_child(hint)


func _process(delta: float) -> void:
	_time = fmod(_time + delta, 256.0)
	_update_wind(delta)
	if _mat != null:
		_mat.set_shader_parameter("time", _time)
	if _ribbon_mat != null:
		_ribbon_mat.set_shader_parameter("time", _time)
	_update_particle_wind()


func _build() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)

	var center := Control.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)

	_holder = Control.new()
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.clip_contents = false
	center.add_child(_holder)
	_ribbon_mat = ShaderMaterial.new()
	_ribbon_mat.shader = RIBBON_SHADER
	_ribbons = ColorRect.new()
	_ribbons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ribbons.material = _ribbon_mat
	_holder.add_child(_ribbons)

	_mat = ShaderMaterial.new()
	_mat.shader = FLAME_SHADER
	_build_letter_mask()
	_flames = ColorRect.new()
	_flames.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flames.color = Color.WHITE
	_flames.material = _mat
	_holder.add_child(_flames)

	_sparks = _make_sparks()
	_holder.add_child(_sparks)


func _build_letter_mask() -> void:
	_letter_viewport = SubViewport.new()
	_letter_viewport.set_meta("static_render", true)
	_letter_viewport.size = Vector2i(256, 256)
	_letter_viewport.transparent_bg = true
	_letter_viewport.disable_3d = true
	_letter_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_letter_viewport)
	_letter_label = Label.new()
	_letter_label.text = letter
	_letter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_letter_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_letter_label.add_theme_font_override("font", LETTER_FONT)
	_letter_label.add_theme_color_override("font_color", Color.WHITE)
	_letter_label.add_theme_constant_override("outline_size", 0)
	_letter_viewport.add_child(_letter_label)
	_mat.set_shader_parameter("letter_mask", _letter_viewport.get_texture())


func _make_sparks() -> GPUParticles2D:
	_spark_mat = ShaderMaterial.new()
	_spark_mat.shader = SPARK_SHADER
	_spark_mat.set_shader_parameter("glow", 1.2)
	var gpu := GPUParticles2D.new()
	gpu.amount = 20
	gpu.lifetime = 0.40
	gpu.preprocess = 0.4
	gpu.explosiveness = 0.0
	gpu.randomness = 0.55
	gpu.local_coords = false
	gpu.visibility_rect = Rect2(-80, -160, 160, 200)
	gpu.z_index = 2
	gpu.material = _spark_mat
	gpu.texture = _make_spark_texture()
	gpu.process_material = _make_spark_process()
	return gpu


func _make_spark_process() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.particle_flag_disable_z = true
	pm.particle_flag_align_y = false
	pm.lifetime_randomness = 0.3
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(18.0, 3.0, 1.0)
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 18.0
	pm.initial_velocity_min = 90.0
	pm.initial_velocity_max = 150.0
	pm.gravity = Vector3(0.0, 8.0, 0.0)
	pm.damping_min = 0.8
	pm.damping_max = 2.2
	pm.linear_accel_min = -6.0
	pm.linear_accel_max = 2.0
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -90.0
	pm.angular_velocity_max = 90.0
	pm.anim_offset_min = 0.0
	pm.anim_offset_max = 1.0
	pm.scale_min = 0.28
	pm.scale_max = 0.48
	pm.scale_curve = _curve_texture(PackedVector2Array([
		Vector2(0.0, 0.45),
		Vector2(0.1, 1.0),
		Vector2(0.4, 0.75),
		Vector2(1.0, 0.08),
	]))
	pm.color_ramp = _color_ramp(
		PackedColorArray([
			Color(1.2, 0.95, 0.35, 1.0),
			Color(1.1, 0.70, 0.15, 1.0),
			Color(1.0, 0.38, 0.03, 0.7),
			Color(0.95, 0.18, 0.02, 0.0),
		]),
		PackedFloat32Array([0.0, 0.25, 0.58, 1.0])
	)
	pm.hue_variation_min = -0.02
	pm.hue_variation_max = 0.025
	pm.turbulence_enabled = false
	pm.turbulence_noise_strength = 22.0
	pm.turbulence_noise_scale = 1.5
	pm.turbulence_noise_speed = Vector3(0.3, 1.5, 0.35)
	pm.turbulence_noise_speed_random = 0.2
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.14
	pm.turbulence_initial_displacement_min = 0.0
	pm.turbulence_initial_displacement_max = 2.0
	pm.turbulence_influence_over_life = _curve_texture(PackedVector2Array([
		Vector2(0.0, 0.06),
		Vector2(0.4, 0.18),
		Vector2(1.0, 0.08),
	]))
	pm.tangential_accel_min = -6.0
	pm.tangential_accel_max = 6.0
	return pm


func _make_spark_texture() -> Texture2D:
	var img := Image.create(10, 12, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


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


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	if vp.y < 32.0 or _holder == null:
		return
	_side = maxf(24.0, tile_side)
	if "--capture" in OS.get_cmdline_user_args():
		_side = vp.y * 0.34
	_pad = _side * PAD_RATIO
	var total := _side + _pad * 2.0
	_holder.custom_minimum_size = Vector2(total, total)
	_holder.size = Vector2(total, total)
	_holder.position = (vp - _holder.size) * 0.5
	_flames.position = Vector2.ZERO
	_flames.size = Vector2(total, total)
	_ribbons.size = Vector2(total, total)
	_ribbon_mat.set_shader_parameter("rect_size", Vector2(total, total))
	_ribbon_mat.set_shader_parameter("tile_origin", Vector2(_pad, _pad))
	_ribbon_mat.set_shader_parameter("tile_size", Vector2(_side, _side))
	_ribbon_mat.set_shader_parameter("chamfer_px", REF_CHAMFER * _side / REF_SIDE)
	_mat.set_shader_parameter("rect_size", Vector2(total, total))
	_mat.set_shader_parameter("tile_origin", Vector2(_pad, _pad))
	_mat.set_shader_parameter("tile_size", Vector2(_side, _side))
	_mat.set_shader_parameter("chamfer_px", REF_CHAMFER * _side / REF_SIDE)
	_letter_viewport.size = Vector2i(roundi(_side), roundi(_side))
	_letter_label.position = Vector2(TEXT_MARGIN, TEXT_MARGIN)
	_letter_label.size = Vector2(_letter_viewport.size) - Vector2.ONE * TEXT_MARGIN * 2.0
	_letter_label.add_theme_font_size_override("font_size", roundi(clampf(tile_side * FONT_SIZE_RATIO, FONT_SIZE_MIN, FONT_SIZE_MAX) * _side / maxf(tile_side, 24.0)))
	_letter_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	if _sparks == null:
		return
	## Spawn on the flame tongue at the top edge so sparks ride the rise.
	_sparks.position = Vector2(_pad + _side * 0.5, _pad - _side * 0.02)
	_sparks.visibility_rect = Rect2(-_side, -_side * 1.5, _side * 2.0, _side * 2.0)
	_sparks.amount = 7
	_sparks.local_coords = false
	_sparks.lifetime = 0.42
	## Keep embers rising at a gentle pace near the upper edge.
	var rise := _side * 0.95
	var pm := _sparks.process_material as ParticleProcessMaterial
	if pm != null:
		pm.emission_box_extents = Vector3(_side * 0.36, maxf(_side * 0.02, 1.5), 1.0)
		pm.initial_velocity_min = rise * 0.95
		pm.initial_velocity_max = rise * 1.35
		pm.gravity = Vector3(0.0, _side * 0.06, 0.0)
		pm.turbulence_noise_strength = _side * 0.22
		pm.turbulence_initial_displacement_max = _side * 0.02
		pm.tangential_accel_min = -_side * 0.05
		pm.tangential_accel_max = _side * 0.05
		## Small flecks — big enough to read, short enough not to look like worms.
		pm.scale_min = _side / 190.0
		pm.scale_max = _side / 140.0
	_sparks.restart()
	_layout_side_sparks()
	for gpu in [_sparks] + _side_sparks:
		(gpu.material as ShaderMaterial).set_shader_parameter("turbulence_px", _side * 0.045)
		gpu.visibility_rect = Rect2(-Vector2.ONE * _side * 7.0, Vector2.ONE * _side * 14.0)
	if _motion != null:
		_motion.relayout(_side)


func _layout_side_sparks() -> void:
	for i in 2:
		var direction := -1.0 if i == 0 else 1.0
		if _side_sparks.size() <= i:
			var sparks := _make_sparks()
			sparks.local_coords = false
			sparks.amount = 3
			sparks.lifetime = 0.38
			_holder.add_child(sparks)
			_side_sparks.append(sparks)
		var sparks := _side_sparks[i]
		sparks.position = Vector2(_pad + _side * (0.5 + direction * 0.48), _pad + _side * 0.55)
		var pm := sparks.process_material as ParticleProcessMaterial
		pm.emission_box_extents = Vector3(1.0, _side * 0.30, 1.0)
		pm.direction = Vector3(direction * 0.5, -1.0, 0.0)
		pm.spread = 20.0
		pm.initial_velocity_min = _side * 0.50
		pm.initial_velocity_max = _side * 0.87
		pm.gravity = Vector3(0.0, -_side * 0.23, 0.0)
		pm.scale_min = _side / 200.0
		pm.scale_max = _side / 145.0
		sparks.restart()


## Screen-space center velocity (pixels per simulation second). No scale-derived wind.
func set_motion_velocity(velocity: Vector2) -> void:
	_motion_velocity = velocity


func _update_wind(delta: float) -> void:
	var speed := _motion_velocity.length() / maxf(_side, 1.0)
	var strength := smoothstep(0.35, 7.0, speed)
	var target_angle := Vector2.UP.angle()
	if strength > 0.001:
		target_angle = lerp_angle(target_angle, (-_motion_velocity).angle(), strength)
	var response := 1.0 - exp(-delta * (14.0 if strength > _wind_strength else 7.0))
	_wind_angle = lerp_angle(_wind_angle, target_angle, response)
	_wind_strength = lerpf(_wind_strength, strength, response)
	var direction := Vector2.from_angle(_wind_angle)
	for material in [_mat, _ribbon_mat]:
		if material != null:
			material.set_shader_parameter("flow_direction", Vector2(direction.x, -direction.y))
			material.set_shader_parameter("wind_strength", _wind_strength)


func _update_particle_wind() -> void:
	if _sparks == null:
		return
	var tail_direction := Vector2.from_angle(_wind_angle)
	var center := Vector2.ONE * (_pad + _side * 0.5)
	var sway := sin(_time * 1.55 * 2.1) * _side * 0.04
	var emitters: Array[GPUParticles2D] = [_sparks]
	emitters.append_array(_side_sparks)
	for i in emitters.size():
		var gpu := emitters[i]
		var rest_position := Vector2(sway, -_side * 0.52)
		var rest_direction := Vector2.UP
		if i > 0:
			var side := -1.0 if i == 1 else 1.0
			rest_position = Vector2(side * _side * 0.48, _side * 0.05)
			rest_direction = Vector2(side * 0.5, -1.0).normalized()
		# Shift the source toward the trailing edge; don't orbit the emitter ring.
		var trailing_position := tail_direction * (_side * 0.52 / maxf(absf(tail_direction.x), absf(tail_direction.y)))
		if i > 0:
			var side := -1.0 if i == 1 else 1.0
			trailing_position = trailing_position * 0.88 + tail_direction.orthogonal() * _side * side * 0.20
		gpu.position = center + rest_position.lerp(trailing_position, _wind_strength)
		var pm := gpu.process_material as ParticleProcessMaterial
		var direction := Vector2.from_angle(lerp_angle(rest_direction.angle(), _wind_angle, _wind_strength))
		pm.direction = Vector3(direction.x, direction.y, 0.0)
		var base_speed := _side * (0.95 if i == 0 else 0.58)
		pm.initial_velocity_min = base_speed * (1.0 + _wind_strength * 0.5)
		pm.initial_velocity_max = base_speed * (1.4 + _wind_strength * 0.7)
		# Existing particles retain their world-space positions and launch velocities.
