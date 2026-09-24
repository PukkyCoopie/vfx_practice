extends Node
## A screen-space water tile. Motion supplies velocity; a damped spring supplies inertia.

const WATER_SHADER = preload("res://shaders/water_tile.gdshader")
const BUBBLES_SCRIPT = preload("res://scenes/effects/water_tile_bubbles.gd")
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
var _drops: GPUParticles2D
var _bubbles: Node2D
var _velocity := Vector2.ZERO
var _previous_velocity := Vector2.ZERO
var _slosh := Vector2.ZERO
var _spring_velocity := Vector2.ZERO
var _trail := Vector2.ZERO
var _time := 0.0
var _side := 109.5
var _splash := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var layer := CanvasLayer.new()
	add_child(layer)
	_holder = Control.new()
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_holder)
	_material = ShaderMaterial.new()
	_material.shader = WATER_SHADER
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
	_surface = ColorRect.new()
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.material = _material
	_holder.add_child(_surface)
	_build_drops()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_bubbles = BUBBLES_SCRIPT.new()
	layer.add_child(_bubbles)
	_bubbles.setup(_holder)
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

func _build_drops() -> void:
	_drops = GPUParticles2D.new()
	_drops.amount = 14
	_drops.lifetime = 0.48
	_drops.emitting = false
	_drops.local_coords = false
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.7, 0.97, 1.0), Color(0.09, 0.65, 0.85), Color(0.02, 0.25, 0.42, 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 24
	texture.height = 24
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.38, 0.32)
	texture.fill_to = Vector2(0.85, 0.82)
	_drops.texture = texture
	var pm := ParticleProcessMaterial.new()
	pm.particle_flag_disable_z = true
	pm.spread = 28.0
	pm.scale_min = 0.13
	pm.scale_max = 0.28
	pm.gravity = Vector3(0, 160, 0)
	var fade := GradientTexture1D.new()
	fade.gradient = Gradient.new()
	fade.gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	pm.color_ramp = fade
	_drops.process_material = pm
	_holder.add_child(_drops)

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
	_drops.visibility_rect = Rect2(-Vector2.ONE * _side * 7.0, Vector2.ONE * _side * 14.0)
	if _motion != null:
		_motion.relayout(_side)

func set_motion_velocity(velocity: Vector2) -> void:
	_velocity = velocity

func _process(delta: float) -> void:
	_time += delta
	_bubbles.advance(delta, _side, _velocity)
	var impulse := ((_velocity - _previous_velocity) / _side).limit_length(12.0)
	_spring_velocity -= impulse * 0.11
	_previous_velocity = _velocity
	# Bounded substeps keep the spring stable at low frame rates.
	var remaining := minf(delta, 0.1)
	while remaining > 0.0:
		var step := minf(remaining, 1.0 / 120.0)
		_spring_velocity += (-_slosh * 90.0 - _spring_velocity * 7.0) * step
		_slosh = (_slosh + _spring_velocity * step).limit_length(0.15)
		remaining -= step
	var strength := smoothstep(0.5, 9.0, _velocity.length() / _side)
	_trail = _trail.lerp(-_velocity.normalized() * strength, 1.0 - exp(-delta * 9.0))
	_material.set_shader_parameter("time", _time)
	_material.set_shader_parameter("slosh", _slosh)
	_material.set_shader_parameter("trail", _trail)
	_splash = maxf(_splash - delta, 0.0)
	if impulse.length() > 2.0:
		_splash = 0.14
	_drops.emitting = strength > 0.28 or _splash > 0.0
	var direction := _trail.normalized() if strength > 0.1 else _spring_velocity.normalized()
	var edge := direction * (0.51 / maxf(maxf(absf(direction.x), absf(direction.y)), 0.01))
	_drops.position = (Vector2.ONE * 1.5 + edge) * _side
	var pm := _drops.process_material as ParticleProcessMaterial
	pm.direction = Vector3(direction.x, direction.y, 0)
	pm.initial_velocity_min = _side * 0.6
	pm.initial_velocity_max = _side * (1.0 + strength)
	pm.gravity = Vector3(0, _side * 1.5, 0)
