extends Node3D

const CombatLayout := preload("res://scripts/combat_layout.gd")
const BODY_SHADER: Shader = preload("res://shaders/lightning_body.gdshader")
const SPARK_SHADER: Shader = preload("res://shaders/lightning_spark.gdshader")

const LAYER_GLOW := 0
const LAYER_BODY := 1
const LAYER_CORE := 2
const MAX_BRANCH_SEGS := 24
const WIDTH_TRUNK := 1.0
const WIDTH_BRANCH := 0.55
const WIDTH_TWIG := 0.30
const WIDTH_ARC := 0.42
const WIDTH_GHOST := 0.55
const GEN_TRUNK := 0
const GEN_BRANCH := 1
const GEN_TWIG := 2
const GEN_ARC := 3
const GEN_GHOST := 4
const SPARK_BANK := 4

@export_group("Placement")
@export var origin_height: float = 0.62
@export var origin_forward: float = 0.94

@export_group("Bolt")
@export var length: float = 0.0
@export var trunk_points: int = 10
@export var kink_min_deg: float = 18.0
@export var kink_max_deg: float = 48.0
@export var branch_chance: float = 0.28
@export var body_width: float = 0.05
@export var glow_width: float = 0.18
@export var core_width: float = 0.016
@export var reshape_interval: float = 0.07

@export_group("Cast Window")
@export var emit_start: float = 1.35
@export var emit_end: float = 1.98
@export var intro_span: float = 0.16
@export var outro_span: float = 0.24

@export_group("Light")
@export var light_energy: float = 4.6
@export var light_range: float = 4.0
@export var light_color: Color = Color(0.72, 0.32, 1.0)

@export var show_wireframe: bool = false:
	set(value):
		show_wireframe = value
		if is_instance_valid(_wire):
			_wire.visible = _wire_should_show()

var _layers: Array[MeshInstance3D] = []
var _layer_mats: Array[ShaderMaterial] = []
var _paths: Array[Dictionary] = []
var _wire: MeshInstance3D
var _light: OmniLight3D
var _anim: AnimationPlayer
var _origin_bank: Array[GPUParticles3D] = []
var _impact_bank: Array[GPUParticles3D] = []
var _origin_slot := 0
var _impact_slot := 0
var _spark_mesh: ArrayMesh
var _reshape_id := 0
var _reshape_clock := 0.0
var _next_reshape := 0.05
var _spark_cool := 0.0
var _cast_on := false
var _flash := 0.0
var _reveal := 1.0
var _conceal := 0.0
var _life := 1.0
var _impact_ready := false
var _flick_seed := 0.0
var _warming := false
var _warm_done := false


func _ready() -> void:
	add_to_group("vfx_no_toon")
	process_mode = Node.PROCESS_MODE_PAUSABLE
	position = Vector3(0.0, origin_height, origin_forward)
	if length <= 0.01:
		# Stop in the scarecrow, not behind it: cell gap minus staff offset.
		length = CombatLayout.front_row_distance() - origin_forward - 0.1
	_rebuild_paths()
	_spawn_layers()
	_spawn_sparks()
	_spawn_light()
	_rebuild_meshes()
	_anim = _find_anim()
	_apply_cast(0.0)
	if not _is_capture():
		_spawn_wireframe()
		_spawn_debug_gui()


func _process(delta: float) -> void:
	if _warming:
		return
	_apply_cast(_anim_time(), delta)


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
	_rebuild_paths()
	_rebuild_meshes()
	var items: Array = []
	for layer in _layers:
		items.append(layer)
	for gpu in _origin_bank:
		items.append(gpu)
	for gpu in _impact_bank:
		items.append(gpu)
	await VfxWarmup.warm_nodes(self, items)
	for layer in _layers:
		if is_instance_valid(layer):
			layer.layers = VfxWarmup.VISIBLE_LAYER
			layer.visible = false
	for gpu in _origin_bank:
		if is_instance_valid(gpu):
			gpu.emitting = false
			gpu.layers = VfxWarmup.VISIBLE_LAYER
	for gpu in _impact_bank:
		if is_instance_valid(gpu):
			gpu.emitting = false
			gpu.layers = VfxWarmup.VISIBLE_LAYER
	_warming = false
	_warm_done = true


func _spawn_layers() -> void:
	var specs := [
		{
			"name": "Glow",
			"priority": 1,
			"inner": Color(0.78, 0.28, 1.18),
			"outer": Color(0.22, 0.04, 0.48),
			"edge": 0.85,
			"steps": 2,
		},
		{
			"name": "Body",
			"priority": 2,
			"inner": Color(1.0, 0.88, 1.16),
			"outer": Color(0.62, 0.16, 1.05),
			"edge": 1.15,
			"steps": ToonStyle.LIGHT_STEPS,
		},
		{
			"name": "Core",
			"priority": 3,
			"inner": Color(1.0, 0.99, 1.0),
			"outer": Color(0.92, 0.78, 1.0),
			"edge": 1.7,
			"steps": 2,
		},
	]
	for spec in specs:
		var mat := ShaderMaterial.new()
		mat.shader = BODY_SHADER
		mat.render_priority = int(spec["priority"])
		mat.set_shader_parameter("color_inner", spec["inner"])
		mat.set_shader_parameter("color_outer", spec["outer"])
		mat.set_shader_parameter("edge_power", spec["edge"])
		mat.set_shader_parameter("toon_steps", spec["steps"])
		mat.set_shader_parameter("intensity", 0.0)
		var mesh_i := MeshInstance3D.new()
		mesh_i.name = String(spec["name"])
		mesh_i.add_to_group("vfx_no_toon")
		mesh_i.material_override = mat
		mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_i.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mesh_i.extra_cull_margin = 4.0
		mesh_i.visible = false
		add_child(mesh_i)
		_layers.append(mesh_i)
		_layer_mats.append(mat)


func _hash_u(x: int) -> int:
	var v := x & 0x7fffffff
	v = ((v >> 16) ^ v) * 0x45d9f3b
	v = ((v >> 16) ^ v) * 0x45d9f3b
	return (v ^ (v >> 16)) & 0x7fffffff


func _h01(a: int, b: int = 0, c: int = 0) -> float:
	return float(_hash_u(a * 73856093 ^ b * 19349663 ^ c * 83492791)) / 2147483647.0


func _hs(a: int, b: int = 0, c: int = 0) -> float:
	return _h01(a, b, c) * 2.0 - 1.0


func _basis_side_up(axis: Vector3) -> Array[Vector3]:
	var side := axis.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = axis.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(axis).normalized()
	return [side, up]


func _walk_polyline(
	start: Vector3,
	end: Vector3,
	count: int,
	seed: int,
	salt: int,
	pin_end: bool
) -> PackedVector3Array:
	var n := maxi(count, 2)
	var pts := PackedVector3Array()
	pts.resize(n)
	pts[0] = start
	var span := end - start
	var dist := span.length()
	if dist < 0.001:
		for i in range(1, n):
			pts[i] = end
		return pts
	var axis := span / dist
	var basis := _basis_side_up(axis)
	var side := basis[0]
	var up := basis[1]
	var min_k := deg_to_rad(minf(kink_min_deg, kink_max_deg))
	var max_k := deg_to_rad(maxf(kink_min_deg, kink_max_deg))
	var weights := PackedFloat32Array()
	weights.resize(n)
	weights[0] = 0.0
	var acc := 0.0
	for i in range(1, n):
		acc += lerpf(0.38, 1.85, _h01(seed, salt, i * 13 + 1))
		weights[i] = acc
	var pos := start
	var dir := axis
	for i in range(1, n):
		var t := weights[i] / maxf(acc, 0.001)
		if pin_end:
			if i == n - 1:
				pts[i] = end
				break
			var t0 := weights[i - 1] / maxf(acc, 0.001)
			var step := dist * absf(t - t0)
			var ang := lerpf(min_k, max_k, _h01(seed, salt, i * 13 + 2))
			var mag := step * tan(ang)
			var flip := 1.0 if i % 2 == 0 else -1.0
			if _h01(seed, salt, i * 13 + 4) < 0.16:
				flip *= -1.0
			var twist := _hs(seed, salt, i * 13 + 5) * 0.42
			pts[i] = start.lerp(end, t) + (side * flip + up * twist).normalized() * mag
			continue
		var left := n - i
		var to_end := end - pos
		var step := to_end.length() / float(left)
		step *= lerpf(0.42, 1.7, _h01(seed, salt, i * 13 + 1))
		var ang := lerpf(min_k, max_k, _h01(seed, salt, i * 13 + 2))
		var flip := 1.0 if i % 2 == 0 else -1.0
		var twist := _hs(seed, salt, i * 13 + 5) * 0.4
		var perp := (side * flip + up * twist).normalized()
		var kinked := (dir * cos(ang) + perp * sin(ang)).normalized()
		var aim := to_end.normalized()
		var new_dir := (kinked * 0.78 + aim * 0.22).normalized()
		pos += new_dir * step
		var delta := pos - pts[i - 1]
		dir = delta.normalized() if delta.length_squared() > 1e-8 else new_dir
		pts[i] = pos
	if pin_end:
		pts[n - 1] = end
	return pts


func _make_jitter(pts: PackedVector3Array, seed: int, salt: int, amp: float) -> PackedVector3Array:
	var jitter := PackedVector3Array()
	jitter.resize(pts.size())
	for i in pts.size():
		if i == 0 or i == pts.size() - 1:
			jitter[i] = Vector3.ZERO
			continue
		var d := pts[i] - pts[i - 1]
		if d.length_squared() < 1e-8:
			jitter[i] = Vector3.ZERO
			continue
		var basis := _basis_side_up(d.normalized())
		jitter[i] = (
			basis[0] * _hs(seed, salt, i * 7)
			+ basis[1] * _hs(seed, salt, i * 7 + 1)
		) * amp
	return jitter


func _push_path(
	pts: PackedVector3Array,
	width: float,
	weight: float,
	generation: int,
	seed: int,
	salt: int
) -> void:
	if pts.size() < 2:
		return
	_paths.append({
		"points": pts,
		"jitter": _make_jitter(pts, seed, salt, body_width * 0.7),
		"width": width,
		"weight": weight,
		"generation": generation,
		"salt": salt,
	})


func _rebuild_paths() -> void:
	_paths.clear()
	_reshape_id += 1
	var seed := _reshape_id * 9176 + 131
	var n := clampi(trunk_points + int(_hs(seed, 1) * 1.4), 6, 16)
	var origin := Vector3.ZERO
	var target := Vector3(0.0, 0.0, length)
	var trunk := _walk_polyline(origin, target, n, seed, 10, true)
	_push_path(trunk, WIDTH_TRUNK, 1.0, GEN_TRUNK, seed, 11)
	if _h01(seed, 2) < 0.32:
		var ghost := _walk_polyline(origin, target, maxi(n - 2, 6), seed, 20, true)
		_push_path(ghost, WIDTH_GHOST, 0.32, GEN_GHOST, seed, 21)
	var branch_segs := 0
	var branch_n := 0
	var max_primary := 2 + int(_h01(seed, 3) * 3.0)
	for i in range(1, trunk.size() - 1):
		if branch_n >= max_primary or branch_segs >= MAX_BRANCH_SEGS:
			break
		var t := float(i) / float(trunk.size() - 1)
		if t < 0.14 or t > 0.86:
			continue
		if _h01(seed, 30 + i) > branch_chance:
			continue
		var td := (trunk[i + 1] - trunk[i - 1]).normalized()
		var side := _basis_side_up(td)[0]
		if _h01(seed, 40 + i) < 0.5:
			side = -side
		var bdir := (
			side * lerpf(0.62, 0.9, _h01(seed, 41 + i))
			+ td * lerpf(0.18, 0.48, _h01(seed, 42 + i))
		).normalized()
		var blen := length * lerpf(0.15, 0.40, _h01(seed, 43 + i))
		var bseg := 3 + int(_h01(seed, 44 + i) * 3.0)
		bseg = mini(bseg, MAX_BRANCH_SEGS - branch_segs)
		if bseg < 2:
			break
		var bpts := _walk_polyline(trunk[i], trunk[i] + bdir * blen, bseg + 1, seed, 50 + i, false)
		_push_path(bpts, WIDTH_BRANCH, 0.78, GEN_BRANCH, seed, 51 + i)
		branch_segs += bseg
		branch_n += 1
		if _h01(seed, 60 + i) >= 0.62 or bpts.size() < 2:
			continue
		var left := MAX_BRANCH_SEGS - branch_segs
		if left < 2:
			continue
		var tip := bpts[bpts.size() - 1]
		var bd := (tip - bpts[bpts.size() - 2]).normalized()
		var tside := _basis_side_up(bd)[0]
		if _h01(seed, 61 + i) < 0.5:
			tside = -tside
		var tdir := (tside * 0.8 + bd * 0.25).normalized()
		var tlen := blen * lerpf(0.32, 0.55, _h01(seed, 62 + i))
		var tseg := mini(2 + int(_h01(seed, 63 + i) * 2.0), left)
		if tseg < 2:
			continue
		var twig := _walk_polyline(tip, tip + tdir * tlen, tseg + 1, seed, 70 + i, false)
		_push_path(twig, WIDTH_TWIG, 0.52, GEN_TWIG, seed, 71 + i)
		branch_segs += tseg
	_add_end_arcs(origin, Vector3(0.0, 0.0, 1.0), seed, 80)
	_add_end_arcs(target, Vector3(0.0, 0.0, -1.0), seed, 90)


func _add_end_arcs(root: Vector3, along: Vector3, seed: int, salt: int) -> void:
	var n := 2 + int(_h01(seed, salt) * 2.0)
	var basis := _basis_side_up(along.normalized())
	for k in n:
		var az := _h01(seed, salt, k * 5) * TAU
		var side := (basis[0] * cos(az) + basis[1] * sin(az)).normalized()
		var dir := (
			side * lerpf(0.55, 0.95, _h01(seed, salt, k * 5 + 1))
			+ along * lerpf(0.15, 0.55, _h01(seed, salt, k * 5 + 2))
		).normalized()
		var alen := length * lerpf(0.08, 0.15, _h01(seed, salt, k * 5 + 3))
		var segs := 2 + int(_h01(seed, salt, k * 5 + 4) * 2.0)
		var pts := _walk_polyline(root, root + dir * alen, segs + 1, seed, salt + 10 + k, false)
		_push_path(pts, WIDTH_ARC, 0.7, GEN_ARC, seed, salt + 20 + k)


func _cam_local() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3(1.4, 1.8, -2.2)
	return to_local(cam.global_position)


func _across(a: Vector3, b: Vector3, cam: Vector3) -> Vector3:
	var seg := b - a
	var to_cam := cam - (a + b) * 0.5
	var x := seg.cross(to_cam)
	if x.length_squared() < 1e-8:
		x = seg.cross(Vector3.UP)
		if x.length_squared() < 1e-8:
			x = Vector3.RIGHT
	return x.normalized()


func _across_hint(a: Vector3, b: Vector3, cam: Vector3, hint: Vector3) -> Vector3:
	var x := _across(a, b, cam)
	if hint.length_squared() > 0.0001 and x.dot(hint) < 0.0:
		x = -x
	return x


func _layer_half(layer: int, path_width: float, taper: float) -> float:
	var base := glow_width
	if layer == LAYER_BODY:
		base = body_width
	elif layer == LAYER_CORE:
		base = core_width
	return maxf(base * path_width * taper, 0.0012)


func _path_taper(generation: int, t: float) -> float:
	if generation == GEN_TRUNK or generation == GEN_GHOST:
		return 1.0
	return lerpf(1.0, 0.32, t)


func _rebuild_meshes() -> void:
	var cam := _cam_local()
	for layer in range(_layers.size()):
		if is_instance_valid(_layers[layer]):
			_layers[layer].mesh = _make_layer_mesh(layer, cam)
	if is_instance_valid(_wire):
		_wire.mesh = _make_wire_mesh()


func _make_layer_mesh(layer: int, cam: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var jitter_amt := 0.0
	if layer == LAYER_BODY:
		jitter_amt = 0.22
	elif layer == LAYER_CORE:
		jitter_amt = 1.0
	for path in _paths:
		var pts: PackedVector3Array = path["points"]
		var jit: PackedVector3Array = path["jitter"]
		var path_w: float = path["width"]
		var weight: float = path["weight"]
		var generation: int = path["generation"]
		var salt: int = int(path.get("salt", 0))
		if layer == LAYER_GLOW:
			weight *= 0.5
		elif layer == LAYER_BODY:
			weight *= 1.0
		else:
			weight *= 1.2
		var last := pts.size() - 1
		if last < 1:
			continue
		var clipped := _clip_path_z(pts, jit, jitter_amt, salt, layer)
		if clipped.size() < 2:
			continue
		var col := Color(1.0, 1.0, 1.0, weight)
		var left := PackedVector3Array()
		var right := PackedVector3Array()
		var clast := clipped.size() - 1
		left.resize(clipped.size())
		right.resize(clipped.size())
		var hint := Vector3.ZERO
		var life_w := lerpf(0.42, 1.0, _life)
		for i in clipped.size():
			var p: Vector3 = clipped[i]
			var t := float(i) / float(clast)
			var half := _layer_half(layer, path_w, _path_taper(generation, t))
			half *= lerpf(0.88, 1.14, _h01(_reshape_id, salt, i * 3 + 2)) * life_w
			var n := Vector3.ZERO
			if i == 0:
				n = _across_hint(p, clipped[1], cam, hint)
			elif i == clast:
				n = _across_hint(clipped[i - 1], p, cam, hint)
			else:
				var n0 := _across_hint(clipped[i - 1], p, cam, hint)
				var n1 := _across_hint(p, clipped[i + 1], cam, n0)
				var miter := n0 + n1
				if miter.length_squared() < 0.0004:
					n = n0
				else:
					miter = miter.normalized()
					n = miter * (1.0 / maxf(miter.dot(n0), 0.42))
			hint = n.normalized() if n.length_squared() > 0.0001 else hint
			left[i] = p + n * half
			right[i] = p - n * half
		for i in clast:
			var t0 := float(i) / float(clast)
			var t1 := float(i + 1) / float(clast)
			_add_tri(st, left[i], right[i], right[i + 1], Vector2(1.0, t0), Vector2(0.0, t0), Vector2(0.0, t1), col)
			_add_tri(st, left[i], right[i + 1], left[i + 1], Vector2(1.0, t0), Vector2(0.0, t1), Vector2(1.0, t1), col)
	st.index()
	return st.commit()


func _live_wiggle(i: int, salt: int, t: float) -> Vector3:
	var ph := float(i) * 1.73 + float(salt) * 0.19
	return Vector3(
		sin(t * 43.0 + ph) + sin(t * 71.0 + ph * 1.7) * 0.45,
		cos(t * 51.0 + ph * 1.3) + sin(t * 67.0 - ph) * 0.4,
		sin(t * 29.0 + ph * 0.6) * 0.18
	)


func _clip_path_z(
	pts: PackedVector3Array,
	jit: PackedVector3Array,
	jitter_amt: float,
	salt: int = 0,
	layer: int = 0
) -> PackedVector3Array:
	var zmin := length * _conceal - 0.02
	var zmax := length * _reveal + 0.03
	if zmin >= zmax:
		return PackedVector3Array()
	var raw := PackedVector3Array()
	raw.resize(pts.size())
	var last := pts.size() - 1
	var live_amp := body_width * (0.42 if layer == LAYER_GLOW else (0.7 if layer == LAYER_BODY else 1.0))
	var t := _flick_seed
	for i in pts.size():
		var p: Vector3 = pts[i] + jit[i] * jitter_amt
		if last > 1 and i > 0 and i < last:
			var pin := sin(float(i) / float(last) * PI)
			p += _live_wiggle(i, salt, t) * live_amp * pin
		raw[i] = p
	var out := PackedVector3Array()
	var started := false
	for i in range(raw.size() - 1):
		var seg := _clip_segment_z(raw[i], raw[i + 1], zmin, zmax)
		if seg.size() < 2:
			if started:
				break
			continue
		if not started:
			out.append(seg[0])
			started = true
		out.append(seg[1])
	return out


func _clip_segment_z(a: Vector3, b: Vector3, zmin: float, zmax: float) -> PackedVector3Array:
	var dz := b.z - a.z
	if absf(dz) < 0.00001:
		if a.z < zmin or a.z > zmax:
			return PackedVector3Array()
		return PackedVector3Array([a, b])
	var t_lo: float
	var t_hi: float
	if dz > 0.0:
		t_lo = (zmin - a.z) / dz
		t_hi = (zmax - a.z) / dz
	else:
		t_lo = (zmax - a.z) / dz
		t_hi = (zmin - a.z) / dz
	var t0 := maxf(0.0, t_lo)
	var t1 := minf(1.0, t_hi)
	if t0 > t1:
		return PackedVector3Array()
	return PackedVector3Array([a.lerp(b, t0), a.lerp(b, t1)])


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


func _make_wire_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for path in _paths:
		var pts: PackedVector3Array = path["points"]
		for i in range(pts.size() - 1):
			st.add_vertex(pts[i])
			st.add_vertex(pts[i + 1])
	return st.commit()


func _apply_cast(time: float, delta: float = 0.0) -> void:
	if _layer_mats.is_empty():
		return
	var on := time >= emit_start and time <= emit_end
	_update_life(time)
	if on and not _cast_on:
		_cast_on = true
		_reshape_clock = 0.0
		_spark_cool = 0.0
		_impact_ready = false
		_strike()
	elif not on and _cast_on:
		_cast_on = false
		_stop_sparks()
	if on:
		_reshape_clock += delta
		if _reshape_clock >= _next_reshape:
			_reshape_clock = 0.0
			_strike()
		else:
			_rebuild_meshes()
		if not _impact_ready and _reveal >= 0.88 and _conceal < 0.82:
			_fire_spark(_impact_bank, true)
			_impact_ready = true
		if _conceal > 0.12:
			_quiet_bank(_origin_bank)
		if _conceal > 0.82:
			_quiet_bank(_impact_bank)
		_flick_seed += delta
		_spark_cool = maxf(_spark_cool - delta, 0.0)
		var bucket := int(_flick_seed * 36.0)
		var h := _h01(bucket, _reshape_id)
		var strobe := 1.0
		if h < 0.1:
			strobe = 0.18
		elif h < 0.22:
			strobe = 0.62
		else:
			strobe = 1.0
		_flash = move_toward(_flash, 0.0, delta * 6.5)
		if time < emit_start + intro_span:
			var intro_u := clampf(inverse_lerp(emit_start, emit_start + intro_span, time), 0.0, 1.0)
			_flash = maxf(_flash, lerpf(1.0, 0.28, intro_u))
		var intensity := strobe * (0.84 + 0.26 * _flash) * _life
		if _layer_mats.size() > LAYER_GLOW:
			_layer_mats[LAYER_GLOW].set_shader_parameter("intensity", intensity * 0.62)
		if _layer_mats.size() > LAYER_BODY:
			_layer_mats[LAYER_BODY].set_shader_parameter("intensity", intensity)
		if _layer_mats.size() > LAYER_CORE:
			_layer_mats[LAYER_CORE].set_shader_parameter("intensity", intensity * 1.2)
		for layer in _layers:
			if is_instance_valid(layer):
				layer.visible = _life > 0.02
		var light_w := intensity * (1.0 - smoothstep(0.06, 0.42, _conceal))
		_update_light(light_w, light_w > 0.03)
	else:
		for mat in _layer_mats:
			if is_instance_valid(mat):
				mat.set_shader_parameter("intensity", 0.0)
		for layer in _layers:
			if is_instance_valid(layer):
				layer.visible = false
		_update_light(0.0, false)


func _update_life(time: float) -> void:
	if time < emit_start or time > emit_end:
		_reveal = 0.0
		_conceal = 1.0
		_life = 0.0
		return
	var intro := maxf(intro_span, 0.04)
	var outro := maxf(outro_span, 0.04)
	var intro_end := emit_start + intro
	var outro_start := emit_end - outro
	if time < intro_end:
		var u := clampf(inverse_lerp(emit_start, intro_end, time), 0.0, 1.0)
		_reveal = 1.0 - pow(2.0, -10.0 * u)
		_conceal = 0.0
		_life = lerpf(1.42, 1.0, u)
	elif time > outro_start:
		var u := clampf(inverse_lerp(outro_start, emit_end, time), 0.0, 1.0)
		_reveal = 1.0
		_conceal = 1.0 - pow(2.0, -10.0 * u)
		_life = lerpf(1.0, 0.62, u)
	else:
		_reveal = 1.0
		_conceal = 0.0
		_life = 1.0


func _strike() -> void:
	_rebuild_paths()
	_rebuild_meshes()
	_pick_next_reshape()
	_burst_sparks()
	_flash = 1.0


func _pick_next_reshape() -> void:
	var roll := _h01(_reshape_id, 8)
	var span := maxf(reshape_interval, 0.03)
	if roll < 0.26:
		_next_reshape = span * lerpf(0.28, 0.5, _h01(_reshape_id, 9))
	elif roll < 0.44:
		_next_reshape = span * lerpf(1.8, 2.9, _h01(_reshape_id, 9))
	else:
		_next_reshape = span * lerpf(0.72, 1.2, _h01(_reshape_id, 9))
	_next_reshape = clampf(_next_reshape, 0.02, 0.28)


func _spawn_sparks() -> void:
	_spark_mesh = _make_spark_cross_mesh(0.26, 0.82)
	var origin_pm := _make_spark_process(Vector3(0.0, 0.0, -1.0), true)
	var impact_pm := _make_spark_process(Vector3(0.0, 0.42, 1.0), false)
	for i in SPARK_BANK:
		var origin := _make_spark_gpu(
			"OriginSparks_%d" % i,
			Vector3.ZERO,
			AABB(Vector3(-3.2, -4.2, -4.6), Vector3(6.4, 5.6, 5.8)),
			origin_pm
		)
		_origin_bank.append(origin)
		add_child(origin)
		var impact := _make_spark_gpu(
			"ImpactSparks_%d" % i,
			Vector3(0.0, 0.0, length),
			AABB(Vector3(-2.8, -4.2, -1.2), Vector3(5.6, 5.6, 7.2)),
			impact_pm
		)
		_impact_bank.append(impact)
		add_child(impact)


func _make_spark_gpu(
	node_name: String,
	pos: Vector3,
	bounds: AABB,
	process: ParticleProcessMaterial
) -> GPUParticles3D:
	var gpu := GPUParticles3D.new()
	gpu.name = node_name
	gpu.add_to_group("vfx_no_toon")
	gpu.position = pos
	gpu.amount = 14
	gpu.lifetime = 0.52
	gpu.one_shot = true
	gpu.explosiveness = 1.0
	gpu.randomness = 0.62
	gpu.emitting = false
	gpu.local_coords = true
	gpu.visibility_aabb = bounds
	gpu.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gpu.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	gpu.extra_cull_margin = 4.0
	gpu.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	gpu.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Y_TO_VELOCITY
	gpu.draw_pass_1 = _spark_mesh
	var mat := ShaderMaterial.new()
	mat.shader = SPARK_SHADER
	mat.set_shader_parameter("glow", 8.5)
	mat.set_shader_parameter("toon_steps", 3)
	mat.render_priority = 4
	gpu.material_override = mat
	gpu.process_material = process
	return gpu


func _make_spark_process(direction: Vector3, perp_disk: bool) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.lifetime_randomness = 0.38
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.05
	pm.direction = direction
	if perp_disk:
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3(0.0, 0.0, 1.0)
		pm.emission_ring_height = 0.02
		pm.emission_ring_radius = 0.07
		pm.emission_ring_inner_radius = 0.03
		pm.spread = 6.0
		pm.flatness = 0.0
		pm.initial_velocity_min = 1.3
		pm.initial_velocity_max = 2.4
		pm.radial_velocity_min = 3.0
		pm.radial_velocity_max = 5.2
		pm.radial_velocity_curve = _curve_texture(PackedVector2Array([
			Vector2(0.0, 1.0),
			Vector2(0.28, 0.72),
			Vector2(1.0, 0.12),
		]))
	else:
		pm.spread = 38.0
		pm.flatness = 0.0
		pm.initial_velocity_min = 3.6
		pm.initial_velocity_max = 7.8
	pm.gravity = Vector3(0.0, -11.5, 0.0)
	pm.particle_flag_align_y = true
	pm.damping_min = 0.35
	pm.damping_max = 1.4
	pm.scale_min = 0.36
	pm.scale_max = 0.82
	pm.scale_curve = _curve_texture(PackedVector2Array([
		Vector2(0.0, 1.2),
		Vector2(0.14, 1.0),
		Vector2(0.62, 0.7),
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


func _burst_sparks() -> void:
	if _spark_cool > 0.001:
		return
	_spark_cool = 0.16
	if _conceal < 0.12:
		_fire_spark(_origin_bank, false)
	if _reveal >= 0.88 and _conceal < 0.82:
		_fire_spark(_impact_bank, true)
		_impact_ready = true


func _fire_spark(bank: Array[GPUParticles3D], impact: bool) -> void:
	if bank.is_empty():
		return
	var slot := _impact_slot if impact else _origin_slot
	var gpu := bank[slot]
	if is_instance_valid(gpu):
		gpu.restart()
	slot = (slot + 1) % bank.size()
	if impact:
		_impact_slot = slot
	else:
		_origin_slot = slot


func _quiet_bank(bank: Array[GPUParticles3D]) -> void:
	for gpu in bank:
		if is_instance_valid(gpu):
			gpu.emitting = false


func _stop_sparks() -> void:
	_quiet_bank(_origin_bank)
	_quiet_bank(_impact_bank)


func _spawn_light() -> void:
	_light = OmniLight3D.new()
	_light.name = "GlowLight"
	_light.position = Vector3(0.0, 0.0, length * 0.5)
	_light.light_color = light_color
	_light.light_energy = 0.0
	_light.light_specular = 0.0
	_light.omni_range = light_range
	_light.omni_attenuation = 0.7
	_light.shadow_enabled = false
	_light.visible = false
	add_child(_light)


func _update_light(weight: float, on: bool) -> void:
	if _light == null or not is_instance_valid(_light):
		return
	_light.visible = on
	if not on:
		_light.light_energy = 0.0
		return
	_light.light_energy = light_energy * weight * (0.72 + 0.55 * _flash)
	_light.light_color = light_color


func _is_capture() -> bool:
	return "--capture" in OS.get_cmdline_user_args()


func _wire_should_show() -> bool:
	return show_wireframe and not _is_capture()


func _spawn_wireframe() -> void:
	_wire = MeshInstance3D.new()
	_wire.name = "Wireframe"
	_wire.add_to_group("vfx_no_toon")
	_wire.mesh = _make_wire_mesh()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.2, 1.0, 0.42)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 10
	_wire.material_override = mat
	_wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wire.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_wire.extra_cull_margin = 4.0
	_wire.visible = _wire_should_show()
	add_child(_wire)


func _spawn_debug_gui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ViewDebug"
	layer.layer = 14
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
	frame.offset_left = -268.0
	frame.offset_top = 16.0
	frame.offset_right = -16.0
	frame.offset_bottom = 0.0
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.11, 0.12, 0.94)
	style.set_border_width_all(1)
	style.border_color = Color(0.26, 0.26, 0.28, 1.0)
	style.set_corner_radius_all(3)
	frame.add_theme_stylebox_override("panel", style)
	root.add_child(frame)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	frame.add_child(stack)

	_debug_title(stack, "Bolt")
	_debug_rule(stack)
	_debug_slider(stack, "Segments", float(trunk_points), 6.0, 16.0, 1.0, func(v: float) -> void:
		trunk_points = clampi(int(round(v)), 6, 16)
		_rebuild_paths()
		_rebuild_meshes()
	)
	_debug_slider(stack, "Kink", kink_max_deg, 18.0, 60.0, 1.0, func(v: float) -> void:
		kink_max_deg = v
		_rebuild_paths()
		_rebuild_meshes()
	)
	_debug_slider(stack, "Branch", branch_chance, 0.0, 0.6, 0.02, func(v: float) -> void:
		branch_chance = v
		_rebuild_paths()
		_rebuild_meshes()
	)
	_debug_slider(stack, "Glow", glow_width, 0.06, 0.32, 0.005, func(v: float) -> void:
		glow_width = v
		_rebuild_meshes()
	)
	_debug_slider(stack, "Body", body_width, 0.02, 0.1, 0.002, func(v: float) -> void:
		body_width = v
		_rebuild_meshes()
	)
	_debug_slider(stack, "Core", core_width, 0.006, 0.04, 0.001, func(v: float) -> void:
		core_width = v
		_rebuild_meshes()
	)
	_debug_slider(stack, "Reshape", reshape_interval, 0.03, 0.16, 0.005, func(v: float) -> void:
		reshape_interval = v
	)
	_debug_rule(stack)
	_debug_check(stack, "Wireframe", show_wireframe, func(on: bool) -> void:
		show_wireframe = on
	)


func _debug_title(stack: VBoxContainer, text: String) -> void:
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_left", 10)
	wrap.add_theme_constant_override("margin_right", 10)
	wrap.add_theme_constant_override("margin_top", 7)
	wrap.add_theme_constant_override("margin_bottom", 6)
	stack.add_child(wrap)
	var title := Label.new()
	title.text = text
	title.add_theme_color_override("font_color", Color(0.82, 0.82, 0.84))
	wrap.add_child(title)


func _debug_rule(stack: VBoxContainer) -> void:
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 1)
	rule.color = Color(0.26, 0.26, 0.28, 1.0)
	stack.add_child(rule)


func _debug_check(stack: VBoxContainer, text: String, on: bool, cb: Callable) -> void:
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_left", 10)
	wrap.add_theme_constant_override("margin_right", 8)
	wrap.add_theme_constant_override("margin_top", 6)
	wrap.add_theme_constant_override("margin_bottom", 6)
	stack.add_child(wrap)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	wrap.add_child(row)
	var lab := Label.new()
	lab.text = text
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.add_theme_color_override("font_color", Color(0.9, 0.9, 0.91))
	row.add_child(lab)
	var box := CheckBox.new()
	box.button_pressed = on
	box.focus_mode = Control.FOCUS_NONE
	box.toggled.connect(cb)
	row.add_child(box)


func _debug_slider(
	stack: VBoxContainer,
	text: String,
	value: float,
	min_v: float,
	max_v: float,
	step: float,
	cb: Callable
) -> void:
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_left", 10)
	wrap.add_theme_constant_override("margin_right", 10)
	wrap.add_theme_constant_override("margin_top", 4)
	wrap.add_theme_constant_override("margin_bottom", 6)
	stack.add_child(wrap)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	wrap.add_child(col)
	var lab := Label.new()
	lab.text = "%s  %.2f" % [text, value]
	lab.add_theme_color_override("font_color", Color(0.9, 0.9, 0.91))
	col.add_child(lab)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(0, 18)
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(v: float) -> void:
		lab.text = "%s  %.2f" % [text, v]
		cb.call(v)
	)
	col.add_child(slider)


func _anim_time() -> float:
	if _anim == null or not is_instance_valid(_anim):
		_anim = _find_anim()
	if _anim == null or _anim.current_animation.is_empty():
		return 0.0
	return _anim.current_animation_position


func _find_anim() -> AnimationPlayer:
	var host := get_parent()
	if host == null:
		return null
	var found := host.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		return null
	return found[0] as AnimationPlayer
