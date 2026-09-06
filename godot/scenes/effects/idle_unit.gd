extends Node3D

const TileSnap := preload("res://scripts/tile_snap.gd")

@export var animation_name: StringName = &"idle"
@export var apply_toon: bool = true

var _player: AnimationPlayer
var _clip: StringName = &""


func _ready() -> void:
	if apply_toon:
		call_deferred("_apply_toon")
	_player = _find_animation_player(self)
	if _player == null:
		return
	_clip = _resolve_idle(_player, animation_name)
	if _clip == &"":
		return
	var anim := _player.get_animation(_clip)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR
	if not _player.animation_finished.is_connected(_on_animation_finished):
		_player.animation_finished.connect(_on_animation_finished)
	_player.play(_clip)
	call_deferred("_snap_to_tile")


func _snap_to_tile() -> void:
	TileSnap.snap(self, 2.0)


func _apply_toon() -> void:
	ToonStyle.apply_unit(self, true)


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


func _resolve_idle(player: AnimationPlayer, wanted: StringName) -> StringName:
	var target := String(wanted).to_lower()
	var names := player.get_animation_list()
	for n in names:
		if String(n).to_lower() == target:
			return StringName(n)
	for n in names:
		if "idle" in String(n).to_lower():
			return StringName(n)
	if names.size() > 0:
		return StringName(names[0])
	return &""
