extends Node3D

const CombatLayout := preload("res://scripts/combat_layout.gd")

@onready var _anchor: Node3D = $VfxAnchor
@onready var _camera_rig: Node3D = $CameraRig
@onready var _ui: CanvasLayer = $UI

var _current_id: String = ""
var _instance: Node = null


func _ready() -> void:
	VfxBridge.register_studio(self)
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
	var out_dir := ProjectSettings.globalize_path("res://ui/thumbs")
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
		var wait := 0.7
		if effect_id == "flame_breath":
			wait = 2.05
		await get_tree().create_timer(wait).timeout
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
