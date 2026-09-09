extends Node3D

const BODY_SHADER: Shader = preload("res://shaders/water_jet_body.gdshader")
const FOAM_EMIT_SHADER: Shader = preload("res://shaders/water_jet_foam_emit.gdshader")
const FOAM_SPRITE_SHADER: Shader = preload("res://shaders/water_foam_sprite.gdshader")
const FOAM_STAMP_SHADER: Shader = preload("res://shaders/water_foam_stamp.gdshader")
const FOAM_COLLAR_SHADER: Shader = preload("res://shaders/water_foam_collar.gdshader")
const FOAM_PROCESS_SHADER: Shader = preload("res://shaders/water_foam_process.gdshader")

@export_group("Placement")
@export var origin_height: float = 0.62
@export var origin_forward: float = 1.16

@export_group("Body")
@export var length: float = 2.85
@export var start_half_width: float = 0.22
@export var start_half_height: float = 0.12
@export var end_half_width: float = 1.7
@export var end_half_height: float = 0.38
@export var flare_power: float = 1.58
@export var end_arc: float = 0.32
@export var superellipse_n: float = 2.6
@export var ring_count: int = 36
@export var side_count: int = 36

@export_group("Cast Window")
@export var emit_start: float = 1.02
@export var emit_full: float = 1.28
@export var emit_fade_start: float = 3.16
@export var emit_end: float = 3.72

@export_group("Flow")
@export var flow_speed_back: float = 1.7
@export var flow_speed_front: float = 6.8
@export var displace_amp: float = 0.1

@export_group("Light")
@export var light_energy: float = 2.5
@export var light_range: float = 4.2
@export var light_color: Color = Color(0.28, 0.58, 1.0)

@export_group("Splash")
@export var use_circle_sprite: bool = false:
	set(value):
		use_circle_sprite = value
		_apply_sprite_mode()

@export_group("Debug")
@export var show_island_field: bool = false:
	set(value):
		show_island_field = value
		_apply_island_debug()

var _body: MeshInstance3D
var _body_mat: ShaderMaterial
var _foam_mat: ShaderMaterial
var _foam_emit_mat: ShaderMaterial
var _foam_emit_vp: SubViewport
var _foam_sprite_mat: ShaderMaterial
var _sprite_vp: SubViewport
var _stamp_spray: ShaderMaterial
var _stamp_collar: ShaderMaterial
var _process_mats: Array[ShaderMaterial] = []
var _splashes: Array[GPUParticles3D] = []
var _anim: AnimationPlayer
var _quad: QuadMesh
var _sprite_opt: OptionButton
var _light: OmniLight3D
var _flick_seed := 0.0
var _warming := false
var _warm_done := false


func _ready() -> void:
	add_to_group("vfx_no_toon")
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = Vector3(0.0, origin_height, origin_forward)
	_spawn_body()
	_anim = _find_anim()
	if _is_capture():
		await _warmup_for_capture()
	else:
		_warmup_splash()
	_apply_cast(0.0)


func _process(delta: float) -> void:
	if _warming:
		return
	_apply_cast(_anim_time(), delta)


func _spawn_body() -> void:
	var mesh := _make_body_mesh()
	_body_mat = _make_body_material()
	_body = MeshInstance3D.new()
	_body.name = "Body"
	_body.mesh = mesh
	_body.material_override = _body_mat
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_body.extra_cull_margin = 4.0
	_foam_mat = _make_foam_material()
	_body_mat.next_pass = _foam_mat
	add_child(_body)
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE
	_foam_sprite_mat = _make_sprite_material()
	_spawn_emit_viewport()
	_spawn_sprite_viewport()
	_stamp_spray = _make_stamp_material(0, 9)
	_stamp_collar = _make_stamp_material(1, 24)
	_spawn_splashes()
	if not _is_capture():
		_spawn_sprite_preview()
		_spawn_debug_gui()
	_spawn_light()


func _make_body_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = BODY_SHADER
	mat.render_priority = 1
	_bind_jet_field(mat, 9.0, 1.45, 0.68, 0.13)
	mat.set_shader_parameter("displace_amp", displace_amp)
	mat.set_shader_parameter("shell_offset", 0.0)
	mat.set_shader_parameter("layer_mode", 0)
	mat.set_shader_parameter("color_blue", Color(0.12, 0.48, 0.98, 1.0))
	mat.set_shader_parameter("color_light", Color(0.28, 0.62, 1.0, 1.0))
	_set_tail_foam(mat)
	return mat


func _make_foam_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = BODY_SHADER
	mat.render_priority = 8
	_bind_jet_field(mat, 13.0, 4.6, 0.62, 0.14)
	mat.set_shader_parameter("displace_amp", displace_amp)
	mat.set_shader_parameter("shell_offset", 0.0)
	mat.set_shader_parameter("layer_mode", 2)
	_set_tail_foam(mat)
	return mat


func _set_tail_foam(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("foam_tail_width", 0.46)
	mat.set_shader_parameter("foam_blue_retract", 0.28)
	mat.set_shader_parameter("foam_island_len", 0.24)
	mat.set_shader_parameter("foam_body_len", 0.04)
	mat.set_shader_parameter("foam_bite_len", 0.18)
	mat.set_shader_parameter("foam_scroll", 9.2)
	mat.set_shader_parameter("debug_island_field", show_island_field)


func _bind_jet_field(mat: ShaderMaterial, cells: float, along: float, warp: float, wall: float) -> void:
	mat.set_shader_parameter("body_length", length)
	mat.set_shader_parameter("wave_count", 1.32)
	mat.set_shader_parameter("flow_scroll", 1.9)
	mat.set_shader_parameter("noise_scale", 0.88)
	mat.set_shader_parameter("flow_speed_back", flow_speed_back)
	mat.set_shader_parameter("flow_speed_front", flow_speed_front)
	mat.set_shader_parameter("cell_count", cells)
	mat.set_shader_parameter("cell_along", along)
	mat.set_shader_parameter("cell_warp", warp)
	mat.set_shader_parameter("wall_width", wall)
	mat.set_shader_parameter("start_half_width", start_half_width)
	mat.set_shader_parameter("start_half_height", start_half_height)
	mat.set_shader_parameter("end_half_width", end_half_width)
	mat.set_shader_parameter("end_half_height", end_half_height)
	mat.set_shader_parameter("flare_power", flare_power)
	mat.set_shader_parameter("end_arc", end_arc)
	mat.set_shader_parameter("superellipse_n", superellipse_n)


func _apply_island_debug() -> void:
	if is_instance_valid(_foam_mat):
		_foam_mat.set_shader_parameter("debug_island_field", show_island_field)


func _is_capture() -> bool:
	return "--capture" in OS.get_cmdline_user_args()


func _make_sprite_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = FOAM_SPRITE_SHADER
	mat.render_priority = 1
	return mat


func _make_stamp_material(kind: int, priority: int = 9) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = FOAM_COLLAR_SHADER if kind == 1 else FOAM_STAMP_SHADER
	if is_instance_valid(_sprite_vp):
		mat.set_shader_parameter("sprite", _sprite_vp.get_texture())
	mat.set_shader_parameter("glow", 2.6 if kind == 0 else 3.6)
	mat.set_shader_parameter("stamp_kind", kind)
	mat.set_shader_parameter("use_circle", use_circle_sprite)
	mat.render_priority = priority
	return mat


func _apply_sprite_mode() -> void:
	if is_instance_valid(_stamp_spray):
		_stamp_spray.set_shader_parameter("use_circle", use_circle_sprite)
	if is_instance_valid(_stamp_collar):
		_stamp_collar.set_shader_parameter("use_circle", use_circle_sprite)
	if is_instance_valid(_sprite_opt):
		_sprite_opt.set_block_signals(true)
		_sprite_opt.selected = 1 if use_circle_sprite else 0
		_sprite_opt.set_block_signals(false)


func _group_spec(group: int) -> Dictionary:
	match group:
		0:
			return {
				"name": "Tail",
				"amount": 18,
				"lifetime": 0.78,
				"flow": 0.3,
				"normal": 0.2,
				"lift": 0.024,
				"back": 0.0,
				"channel": 0,
				"y0": 0.48,
				"y1": 1.0,
				"s0": 0.22,
				"s1": 0.4,
				"keep": 0.35,
				"curl": 1.15,
				"swirl": 0.88,
				"spread": 0.08,
				"damp": 3.5,
				"grav": 0.0,
				"kind": 0,
				"end_scale": 0.38,
				"spin": 11.0,
			}
		1:
			return {
				"name": "Side",
				"amount": 16,
				"lifetime": 0.7,
				"flow": 0.27,
				"normal": 0.23,
				"lift": 0.029,
				"back": 0.0,
				"channel": 1,
				"y0": 0.08,
				"y1": 0.92,
				"s0": 0.065,
				"s1": 0.085,
				"keep": 1.0,
				"curl": 0.74,
				"swirl": 0.5,
				"spread": 0.037,
				"damp": 5.3,
				"grav": 0.0,
				"kind": 0,
				"end_scale": 1.0,
				"spin": 10.0,
			}
		2:
			return {
				"name": "Body",
				"amount": 8,
				"lifetime": 0.78,
				"flow": 0.28,
				"normal": 0.16,
				"lift": 0.05,
				"back": 0.0,
				"channel": 2,
				"y0": 0.16,
				"y1": 0.78,
				"s0": 0.065,
				"s1": 0.08,
				"keep": 1.0,
				"curl": 0.95,
				"swirl": 0.68,
				"spread": 0.05,
				"damp": 3.7,
				"grav": 0.0,
				"kind": 0,
				"end_scale": 1.0,
				"spin": 9.5,
			}
		3:
			return {
				"name": "NozzleSplash",
				"amount": 32,
				"lifetime": 0.68,
				"flow": 0.2,
				"normal": 0.08,
				"lift": 0.01,
				"back": 0.02,
				"channel": 3,
				"y0": 0.0,
				"y1": 0.06,
				"s0": 0.34,
				"s1": 0.52,
				"keep": 1.0,
				"curl": 0.22,
				"swirl": 0.18,
				"spread": 0.012,
				"damp": 3.4,
				"grav": 0.0,
				"kind": 1,
				"end_scale": 1.0,
				"spin": 4.5,
			}
		_:
			return {
				"name": "NozzleFoam",
				"amount": 16,
				"lifetime": 0.72,
				"flow": 0.32,
				"normal": 0.1,
				"lift": 0.028,
				"back": 0.0,
				"channel": 3,
				"y0": 0.0,
				"y1": 0.08,
				"s0": 0.06,
				"s1": 0.11,
				"keep": 1.0,
				"curl": 1.2,
				"swirl": 0.92,
				"spread": 0.016,
				"damp": 6.4,
				"grav": 0.0,
				"kind": 0,
				"end_scale": 1.0,
				"spin": 12.0,
			}


func _make_process_material(spec: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = FOAM_PROCESS_SHADER
	_bind_jet_field(mat, 13.0, 4.6, 0.62, 0.14)
	mat.set_shader_parameter("displace_amp", displace_amp)
	mat.set_shader_parameter("flow_along", spec["flow"])
	mat.set_shader_parameter("normal_speed", spec["normal"])
	mat.set_shader_parameter("spawn_lift", spec["lift"])
	mat.set_shader_parameter("spawn_back", spec["back"])
	mat.set_shader_parameter("map_channel", spec["channel"])
	mat.set_shader_parameter("uv_y_min", spec["y0"])
	mat.set_shader_parameter("uv_y_max", spec["y1"])
	mat.set_shader_parameter("scale_min", spec["s0"])
	mat.set_shader_parameter("scale_max", spec["s1"])
	mat.set_shader_parameter("keep_outward", spec["keep"])
	mat.set_shader_parameter("curl_strength", spec["curl"])
	mat.set_shader_parameter("curl_swirl", spec["swirl"])
	mat.set_shader_parameter("side_spread", spec["spread"])
	mat.set_shader_parameter("damping", spec["damp"])
	mat.set_shader_parameter("gravity", spec["grav"])
	mat.set_shader_parameter("end_scale", spec["end_scale"])
	mat.set_shader_parameter("spin_speed", spec["spin"])
	if is_instance_valid(_foam_emit_vp):
		mat.set_shader_parameter("foam_map", _foam_emit_vp.get_texture())
	return mat


func _spawn_splashes() -> void:
	_process_mats.clear()
	_splashes.clear()
	for i in 5:
		var spec := _group_spec(i)
		spec["emit_group"] = i
		var mat := _make_process_material(spec)
		mat.set_shader_parameter("emit_group", i)
		_process_mats.append(mat)
		var gpu := GPUParticles3D.new()
		gpu.name = String(spec["name"])
		gpu.add_to_group("vfx_no_toon")
		gpu.amount = maxi(int(spec["amount"]), 4)
		gpu.lifetime = spec["lifetime"]
		gpu.preprocess = 0.0
		gpu.explosiveness = 0.0
		gpu.randomness = 0.5
		gpu.amount_ratio = 0.0
		gpu.fixed_fps = 0
		gpu.interpolate = true
		gpu.fract_delta = true
		gpu.local_coords = true
		gpu.visibility_aabb = AABB(Vector3(-5.0, -2.6, -0.8), Vector3(10.0, 5.4, length + 3.0))
		gpu.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gpu.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		gpu.extra_cull_margin = 4.0
		gpu.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
		gpu.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Y_TO_VELOCITY
		gpu.sorting_offset = 2.4 if (i == 3 or i == 4) else 0.0
		gpu.draw_pass_1 = _quad
		gpu.material_override = _stamp_collar if (i == 3 or i == 4) else _stamp_spray
		gpu.process_material = mat
		add_child(gpu)
		_splashes.append(gpu)


func ensure_vfx_warm() -> void:
	while not _warm_done and is_inside_tree():
		await get_tree().process_frame


func _warmup_splash() -> void:
	# Live: compile path is already warm after the first studio play.
	for gpu in _splashes:
		if is_instance_valid(gpu):
			gpu.amount_ratio = 0.0
			gpu.emitting = true
			gpu.restart()
	_warm_done = true


func _warmup_for_capture() -> void:
	# Capture is a cold start. Compile process shaders off-camera, then
	# restore the live emit-on-cast behavior before recording.
	_warming = true
	const hide_layer := 1 << 19
	for gpu in _splashes:
		if is_instance_valid(gpu):
			gpu.layers = hide_layer
			gpu.amount_ratio = 1.0
			gpu.emitting = true
			gpu.restart()
	await get_tree().create_timer(0.22).timeout
	await RenderingServer.frame_post_draw
	for gpu in _splashes:
		if is_instance_valid(gpu):
			gpu.layers = 1
			gpu.amount_ratio = 0.0
			gpu.emitting = false
			gpu.restart()
	_warming = false
	_warm_done = true


func _spawn_emit_viewport() -> void:
	_foam_emit_mat = ShaderMaterial.new()
	_foam_emit_mat.shader = FOAM_EMIT_SHADER
	_bind_jet_field(_foam_emit_mat, 13.0, 4.6, 0.62, 0.14)
	_set_tail_foam(_foam_emit_mat)

	var vp := SubViewport.new()
	vp.name = "FoamEmitMap"
	vp.size = Vector2i(256, 256)
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.handle_input_locally = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_2d = Viewport.MSAA_DISABLED
	_foam_emit_vp = vp
	add_child(vp)

	var view := ColorRect.new()
	view.size = Vector2(256, 256)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.color = Color.BLACK
	view.material = _foam_emit_mat
	vp.add_child(view)


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
	sprite.material_override = _foam_sprite_mat
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vp.add_child(sprite)


func _spawn_sprite_preview() -> void:
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
	frame.offset_left = -460.0
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

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	stack.add_child(row)
	_add_preview_tile(row, "Foam emit", _foam_emit_vp, false)
	_add_preview_tile(row, "Foam sprites", _sprite_vp, true)


func _add_preview_tile(parent: Control, title_text: String, vp: SubViewport, checker: bool) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	parent.add_child(col)
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(208, 208)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(stage)
	if checker:
		var board := ColorRect.new()
		board.set_anchors_preset(Control.PRESET_FULL_RECT)
		board.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
		board.material = checker_mat
		stage.add_child(board)
	var view := TextureRect.new()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(vp):
		view.texture = vp.get_texture()
	stage.add_child(view)


func _spawn_debug_gui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DebugGui"
	layer.layer = 13
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var frame := PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	frame.anchor_left = 1.0
	frame.anchor_top = 0.0
	frame.anchor_right = 1.0
	frame.anchor_bottom = 0.0
	frame.offset_left = -252.0
	frame.offset_top = 16.0
	frame.offset_right = -16.0
	frame.offset_bottom = 0.0
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.11, 0.12, 0.94)
	style.set_border_width_all(1)
	style.border_color = Color(0.26, 0.26, 0.28, 1.0)
	style.set_corner_radius_all(3)
	style.content_margin_left = 0.0
	style.content_margin_top = 0.0
	style.content_margin_right = 0.0
	style.content_margin_bottom = 0.0
	frame.add_theme_stylebox_override("panel", style)
	root.add_child(frame)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	frame.add_child(stack)

	var title_wrap := MarginContainer.new()
	title_wrap.add_theme_constant_override("margin_left", 10)
	title_wrap.add_theme_constant_override("margin_right", 10)
	title_wrap.add_theme_constant_override("margin_top", 7)
	title_wrap.add_theme_constant_override("margin_bottom", 6)
	stack.add_child(title_wrap)
	var title := Label.new()
	title.text = "Island"
	title.add_theme_color_override("font_color", Color(0.82, 0.82, 0.84))
	title_wrap.add_child(title)

	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 1)
	rule.color = Color(0.26, 0.26, 0.28, 1.0)
	stack.add_child(rule)

	var row_wrap := MarginContainer.new()
	row_wrap.add_theme_constant_override("margin_left", 10)
	row_wrap.add_theme_constant_override("margin_right", 8)
	row_wrap.add_theme_constant_override("margin_top", 6)
	row_wrap.add_theme_constant_override("margin_bottom", 8)
	stack.add_child(row_wrap)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row_wrap.add_child(row)
	var lab := Label.new()
	lab.text = "Show field"
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.add_theme_color_override("font_color", Color(0.9, 0.9, 0.91))
	row.add_child(lab)
	var box := CheckBox.new()
	box.button_pressed = show_island_field
	box.focus_mode = Control.FOCUS_NONE
	box.toggled.connect(func(on: bool) -> void:
		show_island_field = on
	)
	row.add_child(box)

	var rule2 := ColorRect.new()
	rule2.custom_minimum_size = Vector2(0, 1)
	rule2.color = Color(0.26, 0.26, 0.28, 1.0)
	stack.add_child(rule2)

	var sprite_wrap := MarginContainer.new()
	sprite_wrap.add_theme_constant_override("margin_left", 10)
	sprite_wrap.add_theme_constant_override("margin_right", 8)
	sprite_wrap.add_theme_constant_override("margin_top", 6)
	sprite_wrap.add_theme_constant_override("margin_bottom", 8)
	stack.add_child(sprite_wrap)
	var sprite_row := HBoxContainer.new()
	sprite_row.add_theme_constant_override("separation", 8)
	sprite_wrap.add_child(sprite_row)
	var sprite_lab := Label.new()
	sprite_lab.text = "Sprite"
	sprite_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sprite_lab.add_theme_color_override("font_color", Color(0.9, 0.9, 0.91))
	sprite_row.add_child(sprite_lab)
	_sprite_opt = OptionButton.new()
	_sprite_opt.focus_mode = Control.FOCUS_NONE
	_sprite_opt.add_item("Foam")
	_sprite_opt.add_item("Circle")
	_sprite_opt.selected = 1 if use_circle_sprite else 0
	_sprite_opt.item_selected.connect(func(idx: int) -> void:
		use_circle_sprite = idx == 1
	)
	sprite_row.add_child(_sprite_opt)


func _anim_time() -> float:
	if _anim == null or not is_instance_valid(_anim):
		_anim = _find_anim()
	if _anim == null or _anim.current_animation.is_empty():
		return 0.0
	return _anim.current_animation_position


func get_cast_time() -> float:
	return _anim_time()


func _cast_grow(time: float) -> float:
	if time < emit_start or time > emit_end:
		return 0.0
	if time < emit_full:
		return clampf((time - emit_start) / maxf(emit_full - emit_start, 0.001), 0.0, 1.0)
	return 1.0


func _cast_cut(time: float) -> float:
	if time < emit_fade_start or time > emit_end:
		return 0.0 if time < emit_fade_start else 1.0
	return clampf((time - emit_fade_start) / maxf(emit_end - emit_fade_start, 0.001), 0.0, 1.0)


func _apply_cast(time: float, delta: float = 0.0) -> void:
	if not is_instance_valid(_body_mat):
		return
	var grow := _cast_grow(time)
	var cut := _cast_cut(time)
	var flow_time := maxf(time - emit_start, 0.0)
	var settle := _head_settle(time)
	_sync_cast(_body_mat, grow, cut, flow_time, settle)
	if is_instance_valid(_foam_mat):
		_sync_cast(_foam_mat, grow, cut, flow_time, settle)
	if is_instance_valid(_foam_emit_mat):
		_sync_cast(_foam_emit_mat, grow, cut, flow_time, settle)
	for mat in _process_mats:
		if is_instance_valid(mat):
			_sync_cast(mat, grow, cut, flow_time, settle)
	var ratio := grow * (1.0 - cut)
	var spraying := grow > 0.02
	var nozzle_on := time >= emit_start - 0.1 and time < emit_fade_start + 0.1
	var nozzle_fade := 0.0
	if time >= emit_fade_start + 0.1:
		nozzle_fade = clampf((time - emit_fade_start - 0.1) / 0.12, 0.0, 1.0)
	for i in _splashes.size():
		var gpu := _splashes[i]
		if not is_instance_valid(gpu):
			continue
		if i == 3:
			gpu.amount_ratio = 1.0 if nozzle_on else 0.0
			gpu.emitting = nozzle_on
		elif i == 4:
			gpu.amount_ratio = ratio if spraying else 0.0
			gpu.emitting = spraying
		else:
			gpu.amount_ratio = ratio
			gpu.emitting = ratio > 0.001
	if _process_mats.size() > 3 and is_instance_valid(_process_mats[3]):
		_process_mats[3].set_shader_parameter("nozzle_fade", nozzle_fade)
	_update_light(_light_weight(time), delta)


func _light_weight(time: float) -> float:
	if time < emit_start or time > emit_end:
		return 0.0
	if time < emit_full:
		return smoothstep(emit_start, emit_full, time)
	if time > emit_fade_start:
		return 1.0 - smoothstep(emit_fade_start, emit_end, time)
	return 1.0


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


func _update_light(weight: float, delta: float) -> void:
	if _light == null or not is_instance_valid(_light):
		return
	var on := weight > 0.001
	_light.visible = on
	if not on:
		_light.light_energy = 0.0
		return
	_flick_seed += delta
	var flick := (
		0.94
		+ 0.055 * sin(_flick_seed * 17.3)
		+ 0.035 * sin(_flick_seed * 29.8 + 1.4)
		+ 0.02 * sin(_flick_seed * 47.1 + 2.2)
	)
	var size_f := (
		0.96
		+ 0.04 * sin(_flick_seed * 13.6 + 0.7)
		+ 0.025 * sin(_flick_seed * 22.4 + 3.1)
	)
	_light.light_energy = light_energy * weight * clampf(flick, 0.88, 1.06)
	_light.omni_range = light_range * clampf(size_f, 0.92, 1.06)
	_light.light_color = light_color.lerp(
		Color(0.52, 0.76, 1.0),
		clampf((flick - 0.94) * 1.6, 0.0, 0.16)
	)


func _head_settle(time: float) -> float:
	if time < emit_full:
		return 0.0
	return clampf((time - emit_full) / 0.14, 0.0, 1.0)


func _sync_cast(mat: ShaderMaterial, grow: float, cut: float, flow_time: float, head_settle: float = 0.0) -> void:
	mat.set_shader_parameter("grow", grow)
	mat.set_shader_parameter("cut", cut)
	mat.set_shader_parameter("flow_time", flow_time)
	mat.set_shader_parameter("head_settle", head_settle)


func _find_anim() -> AnimationPlayer:
	var host := get_parent()
	if host == null:
		return null
	var found := host.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		return null
	return found[0] as AnimationPlayer


func _make_body_mesh() -> ArrayMesh:
	var rings := maxi(ring_count, 2)
	var sides := maxi(side_count, 8)
	var n := maxf(superellipse_n, 1.2)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var ring_pts: Array[PackedVector3Array] = []
	for i in rings:
		var t := float(i) / float(rings - 1)
		ring_pts.append(_ring_points(t, sides, n))

	for i in rings - 1:
		var a := ring_pts[i]
		var b := ring_pts[i + 1]
		var v0 := float(i) / float(rings - 1)
		var v1 := float(i + 1) / float(rings - 1)
		for j in sides:
			var jn := (j + 1) % sides
			var u0 := float(j) / float(sides)
			var u1 := float(j + 1) / float(sides)
			_add_tri(st, a[j], b[j], b[jn], Vector2(u0, v0), Vector2(u0, v1), Vector2(u1, v1))
			_add_tri(st, a[j], b[jn], a[jn], Vector2(u0, v0), Vector2(u1, v1), Vector2(u1, v0))

	st.generate_normals()
	st.index()
	return st.commit()


func _flare(t: float) -> float:
	return pow(clampf(t, 0.0, 1.0), maxf(flare_power, 1.0))


func _ring_points(t: float, sides: int, n: float) -> PackedVector3Array:
	var flare := _flare(t)
	var half_w := lerpf(start_half_width, end_half_width, flare)
	var half_h := lerpf(start_half_height, end_half_height, flare)
	var spine_z := t * length
	var exp := 2.0 / n
	var pts := PackedVector3Array()
	pts.resize(sides)
	for j in sides:
		var theta := (float(j) / float(sides)) * TAU
		var c := cos(theta)
		var s := sin(theta)
		var x := half_w * signf(c) * pow(absf(c), exp)
		var y := half_h * signf(s) * pow(absf(s), exp)
		var nx := x / maxf(half_w, 0.0001)
		var ny := y / maxf(half_h, 0.0001)
		var rim := clampf(pow(nx * nx + ny * ny * 0.22, 0.68), 0.0, 1.0)
		var z := spine_z - length * end_arc * flare * rim
		pts[j] = Vector3(x, y, z)
	return pts


func _add_tri(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	uv_a: Vector2,
	uv_b: Vector2,
	uv_c: Vector2
) -> void:
	st.set_uv(uv_a)
	st.add_vertex(a)
	st.set_uv(uv_b)
	st.add_vertex(b)
	st.set_uv(uv_c)
	st.add_vertex(c)
