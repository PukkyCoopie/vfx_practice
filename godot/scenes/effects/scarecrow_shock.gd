extends Node

## Short electric hit on the scarecrow idle pose.
## Opening jolt, building tremble, a last yank, then the same shake winds down.

const SPARK_SHADER: Shader = preload("res://shaders/lightning_spark.gdshader")

@export_group("Hit Window")
@export var hit_start: float = 1.35
@export var hit_end: float = 2.28
@export var punch1_span: float = 0.16
@export var punch2_start: float = 1.60
@export var punch2_span: float = 0.22

@export_group("Motion")
@export var punch1_lean: float = 11.0
@export var punch2_lean: float = 10.0
@export var tremble: float = 1.0

var _mod: ShockMod
var _cast: Node
var _host: Node3D
var _clock := 0.0
var _sparks: GPUParticles3D
var _finale_burst := false
var _warming := false
var _warm_done := false


func _ready() -> void:
	call_deferred("_attach")


func _process(delta: float) -> void:
	if _mod == null or _warming:
		return
	_clock += delta
	var time := _cast_time()
	var state := _envelope(time)
	_mod.tremble = state.x
	_mod.punch1 = state.y
	_mod.punch2 = state.z
	_mod.clock = _clock
	_mod.punch1_lean = punch1_lean
	_mod.punch2_lean = punch2_lean
	_mod.tremble_amt = tremble
	_update_sparks(time, state)


func ensure_vfx_warm() -> void:
	if _warm_done:
		return
	if _warming:
		while _warming and is_inside_tree():
			await get_tree().process_frame
		return
	if not is_instance_valid(_sparks) and get_tree() != null:
		await get_tree().process_frame
	if not is_instance_valid(_sparks):
		return
	_warming = true
	await VfxWarmup.warm_nodes(self, [_sparks])
	if is_instance_valid(_sparks):
		_sparks.emitting = false
	_warming = false
	_warm_done = true


func _attach() -> void:
	var host := get_parent() as Node3D
	if host == null:
		return
	_host = host
	var found := host.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		push_warning("Scarecrow shock: Skeleton3D not found")
		return
	var skeleton := found[0] as Skeleton3D
	_mod = ShockMod.new()
	_mod.name = "ShockMod"
	skeleton.add_child(_mod)
	if _sparks == null:
		_sparks = _make_sparks()
		host.add_child(_sparks)
		_fit_sparks_to_body()
		call_deferred("_fit_sparks_to_body")
	var stage := host.get_parent()
	if stage != null:
		_cast = _find_cast_source(stage)


func _find_cast_source(stage: Node) -> Node:
	var player := stage.get_node_or_null("Player")
	if player == null:
		return null
	for child in player.get_children():
		if child.has_method("get_cast_time"):
			return child
	return null


func _cast_time() -> float:
	if _cast != null and _cast.has_method("get_cast_time"):
		return float(_cast.call("get_cast_time"))
	return 0.0


func _envelope(time: float) -> Vector3:
	if time < hit_start or time > hit_end:
		return Vector3.ZERO
	var punch1 := 0.0
	var u1 := (time - hit_start) / maxf(punch1_span, 0.05)
	if u1 >= 0.0 and u1 <= 1.0:
		punch1 = sin(u1 * PI)
	var punch2 := 0.0
	var u2 := (time - punch2_start) / maxf(punch2_span, 0.05)
	if u2 >= 0.0 and u2 <= 1.0:
		punch2 = _punch2_envelope(u2)
	return Vector3(_tremble_envelope(time), punch1, punch2)


func _tremble_envelope(time: float) -> float:
	var trem_start := hit_start + punch1_span * 0.38
	if time < trem_start or time > hit_end:
		return 0.0
	var hold := punch2_start
	var release := punch2_start + punch2_span * 0.55
	if time <= hold:
		var u := inverse_lerp(trem_start, hold, time)
		var rise := u * u * (3.0 - 2.0 * u)
		var swell := smoothstep(0.55, 1.0, u)
		return lerpf(0.82 * rise, 1.0, swell)
	if time <= release:
		var u := inverse_lerp(hold, release, time)
		return lerpf(1.0, 1.08, u * u * (3.0 - 2.0 * u))
	var u := inverse_lerp(release, hit_end, time)
	return 1.08 * (1.0 - pow(clampf(u, 0.0, 1.0), 1.55))


func _punch2_envelope(u: float) -> float:
	var attack := 1.0 - pow(2.0, -16.0 * clampf(u / 0.18, 0.0, 1.0))
	var decay := 1.0
	if u > 0.16:
		var r := clampf((u - 0.16) / 0.84, 0.0, 1.0)
		decay = 1.0 - r * r * (3.0 - 2.0 * r)
	return clampf(attack * decay, 0.0, 1.0)


func _update_sparks(time: float, state: Vector3) -> void:
	if not is_instance_valid(_sparks):
		return
	if time < punch2_start:
		_finale_burst = false
		return
	var punch2: float = state.z
	if punch2 > 0.12 and not _finale_burst:
		_finale_burst = true
		_sparks.restart()


func _make_sparks() -> GPUParticles3D:
	var gpu := GPUParticles3D.new()
	gpu.name = "ShockSparks"
	gpu.add_to_group("vfx_no_toon")
	gpu.position = Vector3(0.0, 1.12, 0.0)
	gpu.amount = 18
	gpu.lifetime = 1.5
	gpu.one_shot = true
	gpu.explosiveness = 1.0
	gpu.randomness = 0.0
	gpu.emitting = false
	gpu.local_coords = true
	gpu.visibility_aabb = AABB(Vector3(-3.4, -1.4, -3.4), Vector3(6.8, 6.8, 6.8))
	gpu.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gpu.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	gpu.extra_cull_margin = 4.0
	gpu.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	gpu.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Y_TO_VELOCITY
	gpu.draw_pass_1 = _make_spark_cross_mesh(0.14, 0.2)
	var mat := ShaderMaterial.new()
	mat.shader = SPARK_SHADER
	mat.set_shader_parameter("glow", 8.5)
	mat.set_shader_parameter("toon_steps", 3)
	mat.render_priority = 4
	gpu.material_override = mat
	gpu.process_material = _make_spark_process()
	return gpu


func _make_spark_cross_mesh(width: float, spark_len: float) -> ArrayMesh:
	var hw := width * 0.5
	var hl := spark_len * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_spark_quad(
		st,
		Vector3(-hw, -hl, 0.0), Vector3(hw, -hl, 0.0),
		Vector3(hw, hl, 0.0), Vector3(-hw, hl, 0.0)
	)
	_spark_quad(
		st,
		Vector3(0.0, -hl, -hw), Vector3(0.0, -hl, hw),
		Vector3(0.0, hl, hw), Vector3(0.0, hl, -hw)
	)
	st.generate_normals()
	return st.commit()


func _spark_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
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


func _make_spark_process() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.lifetime_randomness = 0.35
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.28, 0.72, 0.22)
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 28.0
	pm.flatness = 0.72
	pm.gravity = Vector3(0.0, 1.85, 0.0)
	pm.radial_accel_min = 0.12
	pm.radial_accel_max = 0.42
	pm.particle_flag_align_y = true
	pm.initial_velocity_min = 0.68
	pm.initial_velocity_max = 0.84
	pm.damping_min = 0.9
	pm.damping_max = 1.4
	pm.orbit_velocity_min = -0.22
	pm.orbit_velocity_max = 0.22
	pm.tangential_accel_min = -0.4
	pm.tangential_accel_max = 0.4
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.48
	pm.turbulence_noise_scale = 2.2
	pm.turbulence_noise_speed = Vector3(0.16, 0.52, 0.2)
	pm.turbulence_noise_speed_random = 0.22
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.14
	pm.turbulence_initial_displacement_min = 0.0
	pm.turbulence_initial_displacement_max = 0.04
	pm.scale_min = 0.52
	pm.scale_max = 1.12
	pm.scale_curve = _curve_texture(PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(0.08, 0.72),
		Vector2(0.16, 1.05),
		Vector2(0.7, 0.7),
		Vector2(1.0, 0.08),
	]))
	pm.color_ramp = _color_ramp(
		PackedColorArray([
			Color(2.2, 2.05, 2.4, 1.0),
			Color(1.55, 0.78, 1.85, 1.0),
			Color(0.85, 0.28, 1.35, 0.9),
			Color(0.38, 0.08, 0.78, 0.0),
		]),
		PackedFloat32Array([0.0, 0.22, 0.62, 1.0])
	)
	return pm


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
	tex.width = 128
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


func _fit_sparks_to_body() -> void:
	if not is_instance_valid(_sparks) or _host == null:
		return
	var box := _body_aabb(_host)
	if box.size.y < 0.2:
		return
	_sparks.position = box.get_center()
	var half := box.size * 0.5
	var pm := _sparks.process_material as ParticleProcessMaterial
	if pm == null:
		return
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(
		maxf(half.x * 0.78, 0.22),
		maxf(half.y * 0.96, 0.55),
		maxf(half.z * 0.78, 0.18)
	)


func _body_aabb(host: Node3D) -> AABB:
	var merged := _mesh_aabb(host)
	var inv := host.global_transform.affine_inverse()
	for node in host.find_children("*", "Skeleton3D", true, false):
		var skel := node as Skeleton3D
		if skel == null:
			continue
		for i in skel.get_bone_count():
			var p := inv * (skel.global_transform * skel.get_bone_global_pose(i).origin)
			if merged.size == Vector3.ZERO:
				merged = AABB(p, Vector3.ZERO)
			else:
				merged = merged.expand(p)
	return merged


func _mesh_aabb(host: Node3D) -> AABB:
	var merged := AABB()
	var any := false
	var inv := host.global_transform.affine_inverse()
	for node in host.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if mi.is_in_group("vfx_no_toon"):
			continue
		var xf := inv * mi.global_transform
		var box := _xform_aabb(xf, mi.mesh.get_aabb())
		if not any:
			merged = box
			any = true
		else:
			merged = merged.merge(box)
	return merged


func _xform_aabb(xf: Transform3D, aabb: AABB) -> AABB:
	var out := AABB(xf * aabb.position, Vector3.ZERO)
	for i in 8:
		out = out.expand(xf * aabb.get_endpoint(i))
	return out


class ShockMod extends SkeletonModifier3D:
	var tremble := 0.0
	var punch1 := 0.0
	var punch2 := 0.0
	var clock := 0.0
	var punch1_lean := 11.0
	var punch2_lean := 10.0
	var tremble_amt := 1.0
	var _idx: Dictionary = {}

	func _ready() -> void:
		var skel := get_skeleton()
		if skel == null:
			return
		for i in skel.get_bone_count():
			_idx[skel.get_bone_name(i)] = i

	func _process_modification() -> void:
		if tremble <= 0.001 and punch1 <= 0.001 and punch2 <= 0.001:
			return
		var skel := get_skeleton()
		if skel == null:
			return
		if _idx.is_empty():
			for i in skel.get_bone_count():
				_idx[skel.get_bone_name(i)] = i
		var t := clock
		var zap := punch2
		var tr := tremble * tremble_amt * (1.0 + zap * 0.9)
		var lean := punch1_lean * punch1 + punch2_lean * zap
		var twist := 6.0 * punch1 + 7.0 * zap
		var twitch := Vector3(
			sin(t * 37.0) * 1.8 * tr + sin(t * 91.0) * 1.6 * zap,
			sin(t * 52.0 + 0.4) * 2.2 * tr + sin(t * 103.0) * 2.0 * zap,
			sin(t * 29.0 + 1.1) * 1.5 * tr + sin(t * 84.0 + 0.6) * 1.4 * zap
		)
		_add_deg(
			skel,
			"Hips",
			Vector3(
				-lean * 0.12 + twitch.x,
				twist * 0.42 + twitch.y,
				twitch.z * 0.85 + 2.4 * zap
			)
		)
		_add_pos(
			skel,
			"Hips",
			Vector3(
				sin(t * 41.0) * 0.004 * tr + 0.007 * zap * sin(t * 72.0),
				0.007 * zap - 0.006 * punch1 + sin(t * 48.0) * 0.003 * tr,
				-0.02 * punch1 - 0.012 * zap - sin(t * 33.0) * 0.004 * tr
			)
		)
		_add_deg(
			skel,
			"Spine",
			Vector3(
				-lean * 0.28 + sin(t * 44.0) * 2.6 * tr - 2.2 * zap,
				twist * 0.7 + sin(t * 39.0 + 0.7) * 3.4 * tr,
				sin(t * 31.0) * 2.2 * tr + 1.8 * zap
			)
		)
		_add_deg(
			skel,
			"Chest",
			Vector3(
				-lean * 0.18 + sin(t * 47.0 + 0.3) * 3.0 * tr + 3.2 * zap,
				-twist * 0.55 + sin(t * 43.0) * 2.8 * tr,
				6.0 * punch1 + sin(t * 35.0 + 1.4) * 2.4 * tr + sin(t * 77.0) * 2.8 * zap
			)
		)
		_add_deg(
			skel,
			"Neck",
			Vector3(
				8.0 * punch1 + sin(t * 56.0) * 3.8 * tr - 2.0 * zap,
				11.0 * punch1 + sin(t * 61.0) * 4.5 * tr + 5.0 * zap,
				sin(t * 49.0) * 2.6 * tr + 5.5 * zap
			)
		)
		_add_deg(
			skel,
			"Head",
			Vector3(
				10.0 * punch1 + sin(t * 64.0 + 0.5) * 5.0 * tr + sin(t * 118.0) * 3.8 * zap,
				sin(t * 71.0) * 5.5 * tr + 6.5 * zap,
				sin(t * 53.0 + 0.8) * 3.2 * tr + 4.2 * zap
			)
		)
		_add_deg(
			skel,
			"LeftUpperArm",
			Vector3(
				-6.0 * punch1 + sin(t * 46.0) * 3.2 * tr - 5.5 * zap,
				5.0 * punch1 + sin(t * 38.0) * 2.8 * tr + 4.5 * zap,
				7.0 * punch1 + sin(t * 42.0) * 2.4 * tr + sin(t * 66.0) * 3.4 * zap
			)
		)
		_add_deg(
			skel,
			"RightUpperArm",
			Vector3(
				-5.5 * punch1 + sin(t * 44.0 + 0.9) * 3.0 * tr + 5.0 * zap,
				-5.0 * punch1 + sin(t * 36.0) * 2.6 * tr - 6.0 * zap,
				-7.2 * punch1 + sin(t * 40.0 + 1.2) * 2.5 * tr - 4.8 * zap
			)
		)
		_add_deg(
			skel,
			"LeftLowerArm",
			Vector3(8.0 * punch1 + sin(t * 58.0) * 4.0 * tr + 4.2 * zap, 2.8 * zap, 0.0)
		)
		_add_deg(
			skel,
			"RightLowerArm",
			Vector3(8.4 * punch1 + sin(t * 54.0 + 0.6) * 4.2 * tr + 5.0 * zap, -3.4 * zap, 0.0)
		)

	func _add_deg(skel: Skeleton3D, bone: String, degrees: Vector3) -> void:
		if not _idx.has(bone):
			return
		var i: int = _idx[bone]
		var extra := Quaternion.from_euler(
			Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z))
		)
		skel.set_bone_pose_rotation(i, skel.get_bone_pose_rotation(i) * extra)

	func _add_pos(skel: Skeleton3D, bone: String, offset: Vector3) -> void:
		if not _idx.has(bone):
			return
		var i: int = _idx[bone]
		skel.set_bone_pose_position(i, skel.get_bone_pose_position(i) + offset)
