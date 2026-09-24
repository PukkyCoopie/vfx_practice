extends Node
## Smoke-filled electric tile with finite-lived, animated branched discharge paths.

const SURFACE_SHADER = preload("res://shaders/lightning_tile.gdshader")
const ARC_SHADER = preload("res://shaders/lightning_tile_arc.gdshader")
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
var _arc_material: ShaderMaterial
var _arc_texture: GradientTexture2D
var _letter_viewport: SubViewport
var _label: Label
var _motion: Node
var _world_arcs: Node2D
var _arcs: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _velocity := Vector2.ZERO
var _previous_velocity := Vector2.ZERO
var _previous_center := Vector2.ZERO
var _time := 0.0
var _side := 109.5
var _main_timer := 0.18
var _edge_timer := 0.05
var _trail_timer := 0.0
var _burst_cooldown := 0.0
var _discharge := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.seed = 73491
	var layer := CanvasLayer.new()
	add_child(layer)
	_world_arcs = Node2D.new()
	layer.add_child(_world_arcs)
	_holder = Control.new()
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_holder)
	_material = ShaderMaterial.new()
	_material.shader = SURFACE_SHADER
	_arc_material = ShaderMaterial.new()
	_arc_material.shader = ARC_SHADER
	# Shared white texture enables distance-along-path UVs on Line2D.
	_arc_texture = GradientTexture2D.new()
	_arc_texture.width = 2
	_arc_texture.height = 2
	_arc_texture.gradient = Gradient.new()
	_arc_texture.gradient.colors = PackedColorArray([Color.WHITE, Color.WHITE])
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
	get_viewport().size_changed.connect(_layout)
	_layout()
	_motion = MOTION_SCRIPT.new()
	add_child(_motion)
	_motion.setup(_holder, _side)
	_motion.velocity_sampled.connect(set_motion_velocity)
	_previous_center = _motion.center
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

func _layout() -> void:
	_side = maxf(tile_side, 24.0)
	if "--capture" in OS.get_cmdline_user_args():
		_side = get_viewport().get_visible_rect().size.y * 0.34
	_holder.size = Vector2.ONE * _side * 3.0
	_holder.position = (get_viewport().get_visible_rect().size - _holder.size) * 0.5
	_surface.size = _holder.size
	_material.set_shader_parameter("tile_side", _side)
	_arc_material.set_shader_parameter("tile_side", _side)
	_letter_viewport.size = Vector2i(roundi(_side), roundi(_side))
	_label.position = Vector2(4, 4)
	_label.size = Vector2(_letter_viewport.size) - Vector2(8, 8)
	_label.add_theme_font_size_override("font_size", roundi(clampf(tile_side * 0.462, 14.0, 44.0) * _side / maxf(tile_side, 24.0)))
	_letter_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if _motion != null:
		_motion.relayout(_side)
		_previous_center = _motion.center
		_velocity = Vector2.ZERO
		_previous_velocity = Vector2.ZERO

func set_motion_velocity(velocity: Vector2) -> void:
	_velocity = velocity

func _process(delta: float) -> void:
	_time += delta
	_discharge = maxf(0.0, _discharge - delta * 5.0)
	_burst_cooldown -= delta
	_main_timer -= delta
	_edge_timer -= delta
	_trail_timer -= delta
	_update_arcs(delta)
	var speed := _velocity.length() / _side
	var change := (_velocity - _previous_velocity).length() / _side
	if change > 2.2 and _burst_cooldown <= 0.0:
		_discharge = 1.0
		_burst_cooldown = 0.24
		_main_timer = 0.0
		for i in 2:
			_external_arc()
	if _main_timer <= 0.0:
		_main_arc()
		_main_timer = _rng.randf_range(0.46, 0.78) / (1.0 + minf(speed * 0.04, 0.5))
	if _edge_timer <= 0.0:
		_edge_arc()
		_edge_timer = _rng.randf_range(0.12, 0.29)
		if _rng.randf() < 0.48:
			_external_arc()
	var center := _holder.position + _holder.size * 0.5
	if speed > 1.2 and _trail_timer <= 0.0:
		var behind := -_velocity.normalized()
		var rim := behind * (_side * 0.51 / maxf(absf(behind.x), absf(behind.y)))
		var start := center + rim
		var travel := center.distance_to(_previous_center)
		var finish := start + behind * minf(_side * 1.3, maxf(_side * 0.24, travel * 2.5))
		_add_arc(_world_arcs, _jagged(start, finish, _side * 0.065, 6), 0.23, 0.7)
		_trail_timer = 0.055
	_previous_center = center
	_previous_velocity = _velocity
	_material.set_shader_parameter("time", _time)
	_material.set_shader_parameter("discharge", _discharge)
	_material.set_shader_parameter("drift", (_velocity / _side).limit_length(1.0))

func _jagged(start: Vector2, finish: Vector2, amplitude: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array([start])
	var perpendicular := (finish - start).normalized().orthogonal()
	for i in range(1, segments):
		var t := float(i) / segments
		points.append(start.lerp(finish, t) + perpendicular * _rng.randf_range(-amplitude, amplitude))
	points.append(finish)
	return points

func _local_point(p: Vector2) -> Vector2:
	return (p + Vector2.ONE * 1.5) * _side

func _main_arc() -> void:
	# Route around the glyph: one broad bend, then short irregular segments.
	var flip := -1.0 if _rng.randf() < 0.5 else 1.0
	var a := Vector2(-0.43, _rng.randf_range(-0.29, 0.29))
	var b := Vector2(_rng.randf_range(-0.10, 0.10), flip * _rng.randf_range(0.31, 0.38))
	var c := Vector2(0.43, _rng.randf_range(-0.29, 0.29))
	var points := _jagged(_local_point(a), _local_point(b), _side * 0.065, 4)
	points.append_array(_jagged(_local_point(b), _local_point(c), _side * 0.065, 4).slice(1))
	_add_arc(_holder, points, 0.42, 1.0)
	var branch_start := points[2]
	var branch_end := branch_start + Vector2(_side * 0.13, -flip * _side * 0.14)
	_add_arc(_holder, _jagged(branch_start, branch_end, _side * 0.024, 3), 0.32, 0.72, _branch_delay(points, 2, 0.42))
	_discharge = maxf(_discharge, 0.55)

func _edge_arc() -> void:
	var edge := _rng.randi_range(0, 3)
	var start := Vector2(_rng.randf_range(-0.37, 0.05), -0.49)
	var finish := start + Vector2(_rng.randf_range(0.16, 0.31), 0.0)
	var rotation := edge * PI * 0.5
	_add_arc(_holder, _jagged(_local_point(start.rotated(rotation)), _local_point(finish.rotated(rotation)), _side * 0.014, 5), 0.20, 0.6)

func _external_arc() -> void:
	var direction := Vector2.from_angle(_rng.randf_range(0.0, TAU))
	var start := direction * (0.49 / maxf(absf(direction.x), absf(direction.y)))
	var finish := start + direction * _rng.randf_range(0.25, 0.48)
	var points := _jagged(_local_point(start), _local_point(finish), _side * 0.065, 4)
	_add_arc(_holder, points, 0.28, 0.95)
	_add_arc(_holder, _jagged(points[2], points[2] + direction.rotated(0.8) * _side * 0.17, _side * 0.025, 2), 0.22, 0.65, _branch_delay(points, 2, 0.28))

func _branch_delay(points: PackedVector2Array, junction: int, lifetime: float) -> float:
	var total := 0.0
	var distance_to_junction := 0.0
	for i in range(1, points.size()):
		var length := points[i - 1].distance_to(points[i])
		total += length
		if i <= junction:
			distance_to_junction += length
	return lifetime * 0.34 * distance_to_junction / maxf(total, 0.001)

func _add_arc(parent: Node, points: PackedVector2Array, lifetime: float, intensity: float, delay: float = 0.0) -> void:
	var root := Node2D.new()
	root.modulate.a = 0.0
	parent.add_child(root)
	# One material per bolt, shared by its three layers; geometry stays static.
	var material := _arc_material.duplicate() as ShaderMaterial
	var widths := [9.0, 4.2, 1.65]
	var colors := [Color(0.55, 0.12, 1.0, 0.20), Color(0.65, 0.32, 1.0, 0.68), Color(0.96, 0.85, 1.0, 1.0)]
	for i in 3:
		var line := Line2D.new()
		line.points = points
		line.material = material
		line.texture = _arc_texture
		line.texture_mode = Line2D.LINE_TEXTURE_STRETCH
		line.width = widths[i] * (_side / 109.5) * sqrt(intensity)
		line.default_color = colors[i]
		line.antialiased = true
		line.joint_mode = Line2D.LINE_JOINT_BEVEL
		root.add_child(line)
	_arcs.append({"node": root, "material": material, "age": -delay, "lifetime": lifetime, "intensity": intensity})

func _update_arcs(delta: float) -> void:
	for i in range(_arcs.size() - 1, -1, -1):
		var arc := _arcs[i]
		arc.age += delta
		var life: float = arc.age / arc.lifetime
		if life >= 1.0:
			arc.node.queue_free()
			_arcs.remove_at(i)
		else:
			arc.material.set_shader_parameter("arc_clock", Vector2(life, _time))
			# Fast ignition, a smooth re-strike, then a longer fading tail.
			# Simulation age respects pause and studio playback speed.
			var envelope := smoothstep(0.0, 0.12, life) * (1.0 - smoothstep(0.56, 1.0, life))
			var pulse := 0.70 + 0.30 * cos((life - 0.16) * TAU * 2.0)
			arc.node.modulate.a = envelope * pulse * arc.intensity
