extends Node3D

const CombatLayout := preload("res://scripts/combat_layout.gd")

@export var animation_name: StringName = &"spelling_idle"
@export var apply_toon: bool = true
@export var apply_combat_layout: bool = true
@export var studio_camera_distance: float = 0.0

var _player: AnimationPlayer
var _clip: StringName = &""


func _ready() -> void:
	if apply_combat_layout:
		CombatLayout.apply_duo(self)
	if apply_toon:
		_apply_toon()
	_player = _find_animation_player(self)
	if _player == null:
		push_warning("Player preview: AnimationPlayer not found")
		return
	_clip = _resolve_animation(_player, animation_name)
	if _clip == &"":
		push_warning("Player preview: animation not found: %s" % animation_name)
		return
	var anim := _player.get_animation(_clip)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR
	if not _player.animation_finished.is_connected(_on_animation_finished):
		_player.animation_finished.connect(_on_animation_finished)
	_player.seek(0.0, true)
	_player.stop()
	call_deferred("_play_after_warm")


func ensure_vfx_warm() -> void:
	for node in find_children("*", "", true, false):
		if node != self and node.has_method("ensure_vfx_warm"):
			await node.ensure_vfx_warm()
	await VfxWarmup.wait_draw(self)


func _play_after_warm() -> void:
	if not is_inside_tree():
		return
	await ensure_vfx_warm()
	if is_instance_valid(_player) and _clip != &"":
		_player.play(_clip)


func get_playback_player() -> AnimationPlayer:
	return _player


func _apply_toon() -> void:
	var player_model := get_node_or_null("Player/Model")
	if player_model:
		ToonStyle.apply_unit(player_model, true)
	var scarecrow_model := get_node_or_null("Scarecrow/Model")
	if scarecrow_model:
		ToonStyle.apply_unit(scarecrow_model, true)


func _on_animation_finished(anim_name: StringName) -> void:
	if _player == null or _clip == &"":
		return
	if anim_name == _clip:
		_player.play(_clip)


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.find_children("*", "AnimationPlayer", true, false):
		return child as AnimationPlayer
	return null


func _resolve_animation(player: AnimationPlayer, wanted: StringName) -> StringName:
	var target := String(wanted).to_lower()
	var snake := target.replace("/", "_")
	for n in player.get_animation_list():
		var current := String(n).to_lower()
		if current == target or current == snake or current.get_file() == snake:
			return StringName(n)
	var suffix := target.get_file()
	for n in player.get_animation_list():
		var current := String(n).to_lower()
		if current.ends_with("/" + suffix) or current.ends_with("_" + suffix) or current == suffix:
			return StringName(n)
	return &""
