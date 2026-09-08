extends Node

## Overlay a fire-hit reaction on the scarecrow idle pose.
## Idle keeps playing; this modifier adds impact / writhe / collapse.

@export_group("Hit Window")
@export var hit_start: float = 1.18
@export var hit_full: float = 1.52
@export var hit_fade_start: float = 3.18
@export var hit_end: float = 4.12

@export_group("Impact")
@export var impact_span: float = 0.24
@export var impact_lean: float = 20.0
@export var impact_head: float = 16.0

@export_group("Sustain")
@export var sustain_lean: float = 9.0
@export var writhe: float = 1.0

@export_group("Collapse")
@export var collapse_lean: float = 14.0
@export var collapse_sink: float = 0.045

var _mod: BurnMod
var _flame: Node
var _clock := 0.0


func _ready() -> void:
	call_deferred("_attach")


func _process(delta: float) -> void:
	if _mod == null:
		return
	_clock += delta
	var time := _cast_time()
	var state := _envelope(time)
	_mod.intensity = state.x
	_mod.impact = state.y
	_mod.collapse = state.z
	_mod.clock = _clock
	_mod.lean_impact = impact_lean
	_mod.lean_sustain = sustain_lean
	_mod.lean_collapse = collapse_lean
	_mod.sink = collapse_sink
	_mod.writhe = writhe
	_mod.head_impact = impact_head


func _attach() -> void:
	var host := get_parent()
	if host == null:
		return
	var found := host.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		push_warning("Scarecrow burn: Skeleton3D not found")
		return
	var skeleton := found[0] as Skeleton3D
	_mod = BurnMod.new()
	_mod.name = "BurnMod"
	skeleton.add_child(_mod)
	var stage := host.get_parent()
	if stage != null:
		_flame = stage.get_node_or_null("Player/Flame")


func _cast_time() -> float:
	if _flame != null and _flame.has_method("get_cast_time"):
		return float(_flame.call("get_cast_time"))
	return 0.0


func _envelope(time: float) -> Vector3:
	if time < hit_start or time > hit_end:
		return Vector3.ZERO
	var intensity := 0.0
	var impact := 0.0
	var collapse := 0.0
	if time < hit_full:
		var u := inverse_lerp(hit_start, hit_full, time)
		intensity = u * u * (3.0 - 2.0 * u)
		var punch := clampf((time - hit_start) / maxf(impact_span, 0.05), 0.0, 1.0)
		impact = sin(punch * PI)
		if u > 0.7:
			impact = maxf(impact, sin((u - 0.7) / 0.3 * PI) * 0.4)
	elif time < hit_fade_start:
		intensity = 1.0
	else:
		var u := inverse_lerp(hit_fade_start, hit_end, time)
		if u < 0.38:
			var c := u / 0.38
			collapse = sin(c * PI)
			intensity = 1.0 - 0.12 * c
		else:
			var r := inverse_lerp(0.38, 1.0, u)
			var ease := r * r * (3.0 - 2.0 * r)
			collapse = (1.0 - ease) * 0.32
			intensity = 1.0 - ease
	return Vector3(intensity, impact, collapse)


class BurnMod extends SkeletonModifier3D:
	var intensity := 0.0
	var impact := 0.0
	var collapse := 0.0
	var clock := 0.0
	var lean_impact := 20.0
	var lean_sustain := 9.0
	var lean_collapse := 14.0
	var sink := 0.045
	var writhe := 1.0
	var head_impact := 16.0
	var _idx: Dictionary = {}

	func _ready() -> void:
		var skel := get_skeleton()
		if skel == null:
			return
		for i in skel.get_bone_count():
			_idx[skel.get_bone_name(i)] = i

	func _process_modification() -> void:
		if intensity <= 0.001 and impact <= 0.001 and collapse <= 0.001:
			return
		var skel := get_skeleton()
		if skel == null:
			return
		if _idx.is_empty():
			for i in skel.get_bone_count():
				_idx[skel.get_bone_name(i)] = i
		var w := intensity
		var p := impact
		var c := collapse
		var t := clock
		var wr := writhe
		var lean := lean_sustain * w + lean_impact * p + lean_collapse * c
		_add_deg(skel, "Hips", Vector3(-lean * 0.22, sin(t * 6.1) * 3.2 * w * wr, sin(t * 4.4) * 2.4 * w * wr))
		_add_pos(
			skel,
			"Hips",
			Vector3(
				sin(t * 8.2) * 0.006 * w * wr,
				-0.016 * w - sink * c - 0.012 * p,
				-0.028 * p - 0.01 * w - 0.018 * c
			)
		)
		_add_deg(
			skel,
			"Spine",
			Vector3(
				-lean * 0.55 + sin(t * 11.0) * 3.4 * w * wr,
				sin(t * 7.3) * 5.5 * w * wr + 6.0 * p,
				sin(t * 5.6 + 0.8) * 4.2 * w * wr
			)
		)
		_add_deg(
			skel,
			"Chest",
			Vector3(
				-lean * 0.38 + sin(t * 13.4 + 0.4) * 4.0 * w * wr,
				sin(t * 9.1) * 6.2 * w * wr,
				sin(t * 6.8 + 1.2) * 3.6 * w * wr
			)
		)
		_add_deg(
			skel,
			"Neck",
			Vector3(
				8.0 * w + head_impact * 0.6 * p + 7.0 * c + sin(t * 15.0) * 3.0 * w * wr,
				sin(t * 16.5) * 8.0 * w * wr + 12.0 * p,
				sin(t * 12.2) * 4.5 * w * wr
			)
		)
		_add_deg(
			skel,
			"Head",
			Vector3(
				12.0 * w + head_impact * p + 6.0 * c + sin(t * 18.0) * 4.5 * w * wr,
				sin(t * 21.0 + 0.6) * 10.0 * w * wr,
				sin(t * 14.5) * 5.5 * w * wr
			)
		)
		var arm_l := 10.0 * w + 18.0 * p + 6.0 * c
		var arm_r := 11.0 * w + 16.0 * p + 7.0 * c
		_add_deg(
			skel,
			"LeftUpperArm",
			Vector3(
				-arm_l * 0.35 + sin(t * 14.0) * 5.0 * w * wr,
				arm_l * 0.55 + sin(t * 10.5) * 6.0 * w * wr,
				8.0 * w + 10.0 * p + sin(t * 12.8) * 4.0 * w * wr
			)
		)
		_add_deg(
			skel,
			"RightUpperArm",
			Vector3(
				-arm_r * 0.32 + sin(t * 13.2 + 1.1) * 5.2 * w * wr,
				-arm_r * 0.52 + sin(t * 9.6) * 5.8 * w * wr,
				-8.5 * w - 9.0 * p + sin(t * 11.4) * 4.2 * w * wr
			)
		)
		_add_deg(skel, "LeftLowerArm", Vector3(12.0 * w + 8.0 * p + sin(t * 17.0) * 6.0 * w * wr, 0.0, 0.0))
		_add_deg(skel, "RightLowerArm", Vector3(11.0 * w + 9.0 * p + sin(t * 15.5 + 0.7) * 6.2 * w * wr, 0.0, 0.0))
		_add_deg(skel, "LeftUpperLeg", Vector3(6.0 * c + 3.0 * w, 0.0, 3.0 * c))
		_add_deg(skel, "RightUpperLeg", Vector3(7.0 * c + 3.2 * w, 0.0, -3.2 * c))
		_add_deg(skel, "LeftLowerLeg", Vector3(-8.0 * c - 2.0 * w, 0.0, 0.0))
		_add_deg(skel, "RightLowerLeg", Vector3(-9.0 * c - 2.2 * w, 0.0, 0.0))

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
