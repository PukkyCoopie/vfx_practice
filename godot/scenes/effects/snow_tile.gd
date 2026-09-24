extends Node
## Powder snow tile with a matte packed surface and wind-driven loose snow.

const SNOW_SHADER = preload("res://shaders/snow_tile.gdshader")
const MIST_SHADER = preload("res://shaders/snow_tile_mist.gdshader")
const PARTICLE_SHADER = preload("res://shaders/snow_tile_particles.gdshader")
const MOTION_SCRIPT = preload("res://scenes/effects/fire_tile_motion.gd")
const FONT = preload("res://ui/fonts/RobotoSlab-Black.ttf")

@export var studio_hide_stage: bool = true
@export var tile_side: float = 109.5
@export var emit_end: float = 3.0
@export var letter: String = "W":
	set(value):
		letter = value.left(1).to_upper()
		if _label != null:
			_label.text = letter
			_letter_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

var _holder: Control
var _surface: ColorRect
var _material: ShaderMaterial
var _letter_viewport: SubViewport
var _label: Label
var _motion: Node
var _mist: ColorRect
var _mist_material: ShaderMaterial
var _flakes: GPUParticles2D
var _velocity := Vector2.ZERO
var _trail := Vector2.ZERO
var _previous_velocity := Vector2.ZERO
var _gust := Vector2.ZERO
var _gust_velocity := Vector2.ZERO
var _powder_offset := Vector2.ZERO


var _time := 0.0
var _side := 109.5

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var layer := CanvasLayer.new()
	add_child(layer)
	_holder = Control.new()
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_holder)
	_material = ShaderMaterial.new()
	_material.shader = SNOW_SHADER
	_letter_viewport = SubViewport.new()
	_letter_viewport.set_meta("static_render", true)
	_letter_viewport.transparent_bg = true
	_letter_viewport.disable_3d = true
	add_child(_letter_viewport)
	_label = Label.new()
	_label.text = letter
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_override("font", FONT)
	_letter_viewport.add_child(_label)
	_material.set_shader_parameter("letter_mask", _letter_viewport.get_texture())
	_build_mist()
	_surface = ColorRect.new()
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.material = _material
	_holder.add_child(_surface)
	_build_flakes()
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
		layer.add_child(hint)

func _build_mist() -> void:
	# A single continuous field replaces separately emitted cloud sprites.
	_mist = ColorRect.new()
	_mist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mist_material = ShaderMaterial.new()
	_mist_material.shader = MIST_SHADER
	_mist.material = _mist_material
	_holder.add_child(_mist)

func _build_flakes() -> void:
	_flakes = GPUParticles2D.new()
	_flakes.amount = 32
	_flakes.lifetime = 2.2
	_flakes.preprocess = 2.2
	_flakes.local_coords = false
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color.WHITE, Color(0.86, 0.95, 1.0, 0.8), Color(0.86, 0.95, 1.0, 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 16
	texture.height = 16
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	_flakes.texture = texture
	var pm := ShaderMaterial.new()
	pm.shader = PARTICLE_SHADER
	_flakes.process_material = pm
	_holder.add_child(_flakes)

func _layout() -> void:
	_side = maxf(tile_side, 24.0)
	if "--capture" in OS.get_cmdline_user_args():
		_side = get_viewport().get_visible_rect().size.y * 0.34
	_holder.size = Vector2.ONE * _side * 3.0
	_holder.position = (get_viewport().get_visible_rect().size - _holder.size) * 0.5
	_surface.size = _holder.size
	_material.set_shader_parameter("tile_side", _side)
	_letter_viewport.size = Vector2i(roundi(_side), roundi(_side))
	_label.position = Vector2(4, 4)
	_label.size = Vector2(_letter_viewport.size) - Vector2(8, 8)
	_label.add_theme_font_size_override("font_size", roundi(clampf(tile_side * 0.462, 14.0, 44.0) * _side / maxf(tile_side, 24.0)))
	_letter_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_mist.position = Vector2.ONE * _side * 0.6
	_mist.size = Vector2.ONE * _side * 1.8
	_flakes.position = _holder.size * 0.5
	(_flakes.process_material as ShaderMaterial).set_shader_parameter("tile_side", _side)
	_flakes.visibility_rect = Rect2(-Vector2.ONE * _side * 7.0, Vector2.ONE * _side * 14.0)
	if _motion != null:
		_motion.relayout(_side)

func set_motion_velocity(velocity: Vector2) -> void:
	_velocity = velocity

func _process(delta: float) -> void:
	_time += delta
	# Acceleration dislodges loose powder. Deceleration sends it forward;
	# a damped spring leaves a small settling curl after the tile stops.
	var impulse := ((_velocity - _previous_velocity) / _side).limit_length(10.0)

	_previous_velocity = _velocity
	_gust_velocity -= impulse * 0.95
	var remaining := minf(delta, 0.10)
	while remaining > 0.0:
		var step := minf(remaining, 1.0 / 120.0)
		_gust_velocity += (-_gust * 32.0 - _gust_velocity * 5.0) * step
		_gust = (_gust + _gust_velocity * step).limit_length(1.5)
		remaining -= step
	var strength := smoothstep(0.3, 8.0, _velocity.length() / _side)
	_trail = _trail.lerp(-_velocity.normalized() * strength, 1.0 - exp(-delta * 7.0))
	_material.set_shader_parameter("time", _time)
	_material.set_shader_parameter("wind", _trail)
	_powder_offset += (_trail * 0.8 + _gust * 0.35) * delta
	_material.set_shader_parameter("powder_offset", _powder_offset)
	_mist_material.set_shader_parameter("time", _time)
	var center := _holder.position + _holder.size * 0.5
	for particles in [_flakes]:
		var pm := particles.process_material as ShaderMaterial
		pm.set_shader_parameter("wind", _trail)
		pm.set_shader_parameter("gust", _gust)
		pm.set_shader_parameter("center", center)
	_mist_material.set_shader_parameter("motion", _trail * 0.085 + _gust * 0.045)
	_mist_material.set_shader_parameter("flow_offset", _powder_offset * 0.35)
