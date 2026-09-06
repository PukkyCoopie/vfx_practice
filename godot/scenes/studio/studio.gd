extends Node3D

@onready var _anchor: Node3D = $VfxAnchor
@onready var _camera_rig: Node3D = $CameraRig
@onready var _ui: CanvasLayer = $UI

var _current_id: String = ""
var _instance: Node = null


func _ready() -> void:
	VfxBridge.register_studio(self)
	if "--capture" in OS.get_cmdline_user_args():
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


func select_effect(effect_id: String) -> void:
	_current_id = effect_id
	_spawn_current()


func restart_effect() -> void:
	_spawn_current()


func get_animation_player() -> AnimationPlayer:
	if _instance == null or not is_instance_valid(_instance):
		return null
	if _instance is AnimationPlayer:
		return _instance as AnimationPlayer
	var found := _instance.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		return null
	return found[0] as AnimationPlayer


func get_playback_length() -> float:
	var player := get_animation_player()
	if player == null:
		return 0.0
	return maxf(player.current_animation_length, 0.0)


func get_playback_time() -> float:
	var player := get_animation_player()
	if player == null:
		return 0.0
	return player.current_animation_position


func seek_playback(time: float) -> void:
	var player := get_animation_player()
	if player == null:
		return
	player.seek(time, true)


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


func _clear_anchor() -> void:
	if _instance != null and is_instance_valid(_instance):
		_instance.queue_free()
		_instance = null
	for child in _anchor.get_children():
		child.queue_free()


func _run_capture() -> void:
	_ui.visible = false
	var project_root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var out_dir := project_root.path_join("../web/public/thumbs")
	DirAccess.make_dir_recursive_absolute(out_dir)
	await get_tree().process_frame
	await get_tree().process_frame
	for effect in VfxBridge.get_effects():
		var effect_id := String(effect.get("id", ""))
		if effect_id.is_empty():
			continue
		select_effect(effect_id)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().create_timer(0.7).timeout
		var img := get_viewport().get_texture().get_image()
		if img == null:
			push_error("Viewport capture failed for %s" % effect_id)
			continue
		img.resize(640, 360, Image.INTERPOLATE_LANCZOS)
		var dest := out_dir.path_join("%s.webp" % effect_id)
		var err := img.save_webp(dest, true, 0.9)
		if err != OK:
			push_error("Failed to save %s (%s)" % [dest, err])
		else:
			print("Captured %s -> %s" % [effect_id, dest])
	get_tree().quit()
