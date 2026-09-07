extends Node

signal effect_changed(effect_id: String)
signal playback_changed(is_paused: bool, time_scale: float)

var _effects: Array = []
var _current_id: String = ""
var _studio: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_catalog()


func register_studio(studio: Node) -> void:
	_studio = studio
	var start_id := _current_id
	if start_id.is_empty():
		start_id = get_default_id()
	if not start_id.is_empty():
		select(start_id)


func get_effects() -> Array:
	return _effects


func get_default_id() -> String:
	if _effects.is_empty():
		return ""
	return String(_effects[_effects.size() - 1].get("id", ""))


func scene_path_for(effect_id: String) -> String:
	for effect in _effects:
		if String(effect.get("id", "")) == effect_id:
			return String(effect.get("scene", ""))
	return ""


func get_current_id() -> String:
	return _current_id


func select(effect_id: String) -> void:
	var path := scene_path_for(effect_id)
	if path.is_empty():
		push_warning("Unknown effect id: %s" % effect_id)
		return
	_current_id = effect_id
	if _studio and _studio.has_method("select_effect"):
		_studio.select_effect(effect_id)
	effect_changed.emit(effect_id)


func pause() -> void:
	get_tree().paused = true
	playback_changed.emit(true, Engine.time_scale)


func play() -> void:
	get_tree().paused = false
	playback_changed.emit(false, Engine.time_scale)


func setSpeed(scale: float) -> void:
	Engine.time_scale = maxf(scale, 0.01)
	playback_changed.emit(get_tree().paused, Engine.time_scale)


func restart() -> void:
	get_tree().paused = false
	if _studio and _studio.has_method("restart_effect"):
		_studio.restart_effect()
	playback_changed.emit(false, Engine.time_scale)


func thumb_path_for(thumb_name: String) -> String:
	if thumb_name.is_empty():
		return ""
	return "res://ui/thumbs/%s" % thumb_name


func _load_catalog() -> void:
	var file := FileAccess.open("res://data/effects.json", FileAccess.READ)
	if file == null:
		push_error("Missing res://data/effects.json")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		_effects = parsed
	else:
		push_error("effects.json must be a JSON array")
