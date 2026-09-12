extends Node3D

const CombatLayout := preload("res://scripts/combat_layout.gd")
const CAPTURE_FPS := 12
const CAPTURE_WIDTH := 480
const CAPTURE_HEIGHT := 270
const CAPTURE_MAX_SEC := 4.0
const CAPTURE_MIN_SEC := 1.6
const CAPTURE_MAX_LOOPS := 3

@onready var _anchor: Node3D = $VfxAnchor
@onready var _camera_rig: Node3D = $CameraRig
@onready var _ui: CanvasLayer = $UI

var _current_id: String = ""
var _instance: Node = null


func _ready() -> void:
	VfxBridge.register_studio(self)
	VfxBridge.playback_changed.connect(_on_playback_changed)
	var args := OS.get_cmdline_user_args()
	if "--capture" in args:
		await _run_capture()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_pause"):
		if get_tree().paused:
			VfxBridge.play()
		else:
			VfxBridge.pause()
	elif event.is_action_pressed("restart_effect"):
		VfxBridge.restart()
	elif event.is_action_pressed("reset_camera"):
		if _camera_rig.has_method("reset_view"):
			_camera_rig.reset_view()
		_apply_effect_camera()


func select_effect(effect_id: String) -> void:
	_current_id = effect_id
	_spawn_current()
	# Tile snap is deferred in effect units; focus after that.
	call_deferred("_apply_effect_camera")


func restart_effect() -> void:
	_spawn_current()
	call_deferred("_apply_effect_camera")


func _apply_effect_camera() -> void:
	if _camera_rig == null:
		return
	var dist := 8.0
	if _instance != null and is_instance_valid(_instance):
		var hinted: Variant = _instance.get("studio_camera_distance")
		if hinted is float and (hinted as float) > 0.5:
			dist = hinted as float
	var focus := _duo_focus_point()
	if _camera_rig.has_method("set_target"):
		_camera_rig.set_target(focus)
	if _camera_rig.has_method("set_distance"):
		_camera_rig.set_distance(dist)


func _duo_focus_point() -> Vector3:
	if _instance == null or not is_instance_valid(_instance):
		return Vector3(0.0, 0.0, 0.0)
	var player := _instance.get_node_or_null("Player") as Node3D
	var scarecrow := _instance.get_node_or_null("Scarecrow") as Node3D
	if player == null or scarecrow == null:
		return Vector3(0.0, 0.0, 0.0)
	return (player.global_position + scarecrow.global_position) * 0.5


func get_animation_player() -> AnimationPlayer:
	if _instance == null or not is_instance_valid(_instance):
		return null
	if _instance.has_method("get_playback_player"):
		var from_preview: Variant = _instance.call("get_playback_player")
		if from_preview is AnimationPlayer:
			return from_preview as AnimationPlayer
	if _instance is AnimationPlayer:
		return _instance as AnimationPlayer
	var found := _instance.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		return null
	return found[0] as AnimationPlayer


func get_playback_length() -> float:
	var player := get_animation_player()
	if player == null or player.current_animation.is_empty():
		return 0.0
	return maxf(player.current_animation_length, 0.0)


func get_playback_time() -> float:
	var player := get_animation_player()
	if player == null or player.current_animation.is_empty():
		return 0.0
	return player.current_animation_position


func seek_playback(time: float) -> void:
	var player := get_animation_player()
	if player == null:
		return
	player.seek(clampf(time, 0.0, get_playback_length()), true)


func _spawn_current() -> void:
	_clear_anchor()
	var path := VfxBridge.scene_path_for(_current_id)
	if path.is_empty():
		return
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("Failed to load effect scene: %s" % path)
		return
	_instance = packed.instantiate()
	_anchor.add_child(_instance)
	_freeze_fx(get_tree().paused)


func _freeze_fx(frozen: bool) -> void:
	if _instance == null or not is_instance_valid(_instance):
		return
	var vp_mode := SubViewport.UPDATE_DISABLED if frozen else SubViewport.UPDATE_ALWAYS
	for node in _instance.find_children("*", "SubViewport", true, false):
		var vp := node as SubViewport
		if vp:
			vp.render_target_update_mode = vp_mode
	var speed := 0.0 if frozen else 1.0
	for node in _instance.find_children("*", "GPUParticles3D", true, false):
		var gpu := node as GPUParticles3D
		if gpu:
			gpu.speed_scale = speed


func _on_playback_changed(is_paused: bool, _time_scale: float) -> void:
	_freeze_fx(is_paused)


func _clear_anchor() -> void:
	if _instance != null and is_instance_valid(_instance):
		_instance.queue_free()
		_instance = null
	for child in _anchor.get_children():
		child.queue_free()


func _run_capture() -> void:
	_ui.visible = false
	var capture_root := _capture_root()
	DirAccess.make_dir_recursive_absolute(capture_root)
	await get_tree().process_frame
	await get_tree().process_frame
	for effect in VfxBridge.get_effects():
		var effect_id := String(effect.get("id", ""))
		if effect_id.is_empty():
			continue
		if not _capture_filter().is_empty() and effect_id != _capture_filter():
			continue
		await _capture_effect(effect_id, capture_root)
	get_tree().quit()


func _capture_filter() -> String:
	var args := OS.get_cmdline_user_args()
	var idx := args.find("--capture")
	if idx >= 0 and idx + 1 < args.size() and not str(args[idx + 1]).begins_with("--"):
		return str(args[idx + 1])
	return ""


func _capture_root() -> String:
	var res := ProjectSettings.globalize_path("res://")
	return res.path_join("..").path_join("tmp").path_join("capture").simplify_path()


func _capture_effect(effect_id: String, capture_root: String) -> void:
	var dest_dir := capture_root.path_join(effect_id)
	DirAccess.make_dir_recursive_absolute(dest_dir)
	_clear_pngs(dest_dir)
	select_effect(effect_id)
	await get_tree().process_frame
	await _await_vfx_warm()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_apply_effect_camera()
	var player := get_animation_player()
	var clip := _capture_animation_clip(player)
	if player != null and not clip.is_empty():
		player.play(clip)
		player.seek(0.0, true)
	_reset_fx_for_capture()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var fps := _capture_fps_for(effect_id)
	var length := _capture_length(_capture_loops_for(effect_id))
	var count := clampi(
		int(round(length * float(fps))),
		8,
		int(CAPTURE_MAX_SEC * float(CAPTURE_MAX_LOOPS) * float(fps))
	)
	var dt := 1.0 / float(fps)
	var saved := 0
	for i in count:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img == null:
			push_error("Viewport capture failed for %s frame %s" % [effect_id, i])
			break
		img.resize(CAPTURE_WIDTH, CAPTURE_HEIGHT, Image.INTERPOLATE_LANCZOS)
		var path := dest_dir.path_join("%04d.png" % i)
		var err := img.save_png(path)
		if err != OK:
			push_error("Failed to save %s (%s)" % [path, err])
			break
		saved += 1
		if i + 1 < count:
			await get_tree().create_timer(dt).timeout
	print("Captured %s frames @%sfps for %s -> %s" % [saved, fps, effect_id, dest_dir])


func _capture_fps_for(effect_id: String) -> int:
	for effect in VfxBridge.get_effects():
		if String(effect.get("id", "")) != effect_id:
			continue
		var raw: Variant = effect.get("capture_fps", effect.get("thumb_fps", CAPTURE_FPS))
		return clampi(int(raw), 8, 60)
	return CAPTURE_FPS


func _capture_loops_for(effect_id: String) -> int:
	for effect in VfxBridge.get_effects():
		if String(effect.get("id", "")) != effect_id:
			continue
		return clampi(int(effect.get("capture_loops", 1)), 1, CAPTURE_MAX_LOOPS)
	return 1


func _capture_length(loops: int = 1) -> float:
	var anim := get_playback_length()
	var visual := _visual_end_time()
	var cycle := anim
	if visual > 0.5:
		var padded := visual + 0.12
		# Keep a short clip's tail, but don't pad a long idle loop to 4s.
		if anim > 0.05 and anim <= visual + 0.8:
			cycle = maxf(padded, anim)
		else:
			cycle = padded
	if cycle <= 0.05:
		cycle = CAPTURE_MIN_SEC
	cycle = clampf(cycle, CAPTURE_MIN_SEC, CAPTURE_MAX_SEC)
	# Discrete looping casts (e.g. lightning) need multiple cycles to match live studio.
	return clampf(cycle * float(maxi(loops, 1)), CAPTURE_MIN_SEC, CAPTURE_MAX_SEC * float(CAPTURE_MAX_LOOPS))


func _visual_end_time() -> float:
	if _instance == null or not is_instance_valid(_instance):
		return 0.0
	var best := 0.0
	var nodes: Array = [_instance]
	nodes.append_array(_instance.find_children("*", "", true, false))
	for node in nodes:
		if node == null:
			continue
		for key in ["emit_end", "hit_end"]:
			var value: Variant = node.get(key)
			if value is float:
				best = maxf(best, value as float)
	return best


func _await_vfx_warm() -> void:
	if _instance == null or not is_instance_valid(_instance):
		return
	if _instance.has_method("ensure_vfx_warm"):
		await _instance.ensure_vfx_warm()
		return
	for node in _instance.find_children("*", "", true, false):
		if node.has_method("ensure_vfx_warm"):
			await node.ensure_vfx_warm()
			return


func _reset_fx_for_capture() -> void:
	if _instance == null or not is_instance_valid(_instance):
		return
	# Drop any particles that may have spawned before the capture seek(0).
	for node in _instance.find_children("*", "GPUParticles3D", true, false):
		var gpu := node as GPUParticles3D
		if gpu == null:
			continue
		gpu.emitting = false
		gpu.restart()
	for node in _instance.find_children("*", "SubViewport", true, false):
		var vp := node as SubViewport
		if vp:
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _capture_animation_clip(player: AnimationPlayer) -> StringName:
	if player != null and not player.current_animation.is_empty():
		return player.current_animation
	if _instance != null and is_instance_valid(_instance) and _instance.has_method("get_playback_clip"):
		var clip: Variant = _instance.call("get_playback_clip")
		if clip is StringName and not (clip as StringName).is_empty():
			return clip as StringName
		if clip is String and not str(clip).is_empty():
			return StringName(str(clip))
	return &""


func _clear_pngs(dest_dir: String) -> void:
	var dir := DirAccess.open(dest_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".png"):
			dir.remove(name)
		name = dir.get_next()
	dir.list_dir_end()
