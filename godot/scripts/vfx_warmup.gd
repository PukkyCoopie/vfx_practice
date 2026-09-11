class_name VfxWarmup
extends RefCounted

## Compatibility compiles shaders on first actual draw. Warm copies live in a
## private off-screen SubViewport so the studio scene never emits or shows them.
const HIDE_LAYER := 1 << 19
const VISIBLE_LAYER := 1
const VIEW_NAME := "_VfxWarmupView"


static func apply_camera_mask(camera: Camera3D) -> void:
	if camera == null:
		return
	camera.cull_mask = camera.cull_mask & ~HIDE_LAYER


static func wait_draw(node: Node) -> void:
	var tree := node.get_tree()
	if tree == null:
		return
	var vp := _ensure_view(node)
	if vp:
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for _i in 3:
		await tree.process_frame
		await RenderingServer.frame_post_draw
	if is_instance_valid(vp):
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


static func warm_nodes(host: Node, visuals: Array) -> void:
	var vp := _ensure_view(host)
	if vp == null:
		return
	var temps: Array[Node] = []
	var slot := 0.0
	for item in visuals:
		if item == null or not is_instance_valid(item):
			continue
		var dummy: Node3D = null
		if item is GPUParticles3D:
			dummy = _clone_gpu(item as GPUParticles3D)
		elif item is MeshInstance3D:
			dummy = _clone_mesh(item as MeshInstance3D)
		if dummy == null:
			continue
		dummy.position = Vector3(slot, 0.0, 0.0)
		vp.add_child(dummy)
		if dummy is GPUParticles3D:
			(dummy as GPUParticles3D).restart()
		temps.append(dummy)
		slot += 0.45
	await wait_draw(host)
	for dummy in temps:
		if is_instance_valid(dummy):
			dummy.queue_free()


static func _clone_mesh(src: MeshInstance3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = src.mesh
	mi.material_override = src.material_override
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 1
	return mi


static func _clone_gpu(src: GPUParticles3D) -> GPUParticles3D:
	var gpu := GPUParticles3D.new()
	gpu.amount = mini(src.amount, 6)
	gpu.lifetime = 0.2
	gpu.one_shot = false
	gpu.explosiveness = 0.0
	gpu.emitting = true
	gpu.visibility_aabb = AABB(Vector3(-2.0, -2.0, -2.0), Vector3(4.0, 4.0, 4.0))
	gpu.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gpu.draw_pass_1 = src.draw_pass_1
	gpu.material_override = src.material_override
	gpu.process_material = src.process_material
	gpu.transform_align = src.transform_align
	gpu.layers = 1
	return gpu


static func _ensure_view(node: Node) -> SubViewport:
	var tree := node.get_tree()
	if tree == null:
		return null
	var vp := tree.root.get_node_or_null(VIEW_NAME) as SubViewport
	if vp == null or not is_instance_valid(vp):
		vp = SubViewport.new()
		vp.name = VIEW_NAME
		vp.size = Vector2i(128, 128)
		vp.transparent_bg = true
		vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.own_world_3d = true
		vp.handle_input_locally = false
		vp.gui_disable_input = true
		var cam := Camera3D.new()
		cam.name = "Cam"
		cam.current = true
		cam.cull_mask = 0xFFFFF
		cam.position = Vector3(0.0, 0.25, 2.4)
		vp.add_child(cam)
		tree.root.add_child(vp)
		cam.look_at(Vector3.ZERO)
	return vp
