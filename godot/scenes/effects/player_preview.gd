extends Node3D

@export var animation_name: StringName = &"standing_idle"
@export var spelling_library: AnimationLibrary


func _ready() -> void:
	var player := _find_animation_player(self)
	if player == null:
		push_warning("Player preview: AnimationPlayer not found")
		return
	if spelling_library != null and not player.has_animation_library("spelling"):
		player.add_animation_library("spelling", spelling_library)
	var clip := _resolve_animation(player, animation_name)
	if clip == &"":
		push_warning("Player preview: animation not found: %s" % animation_name)
		return
	var anim := player.get_animation(clip)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR
	player.play(clip)


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.find_children("*", "AnimationPlayer", true, false):
		return child as AnimationPlayer
	return null


func _resolve_animation(player: AnimationPlayer, wanted: StringName) -> StringName:
	var target := String(wanted).to_lower()
	for n in player.get_animation_list():
		if String(n).to_lower() == target:
			return StringName(n)
	for n in player.get_animation_list():
		if target in String(n).to_lower():
			return StringName(n)
	return &""
