extends Node

signal effect_changed(effect_id: String)
signal playback_changed(is_paused: bool, time_scale: float)

var _effects: Array = []
var _current_id: String = ""
var _studio: Node = null
var _cb_select: Variant
var _cb_pause: Variant
var _cb_play: Variant
var _cb_speed: Variant
var _cb_restart: Variant


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_catalog()
	if OS.has_feature("web"):
		_bind_web()


func _bind_web() -> void:
	_cb_select = JavaScriptBridge.create_callback(_on_js_select)
	_cb_pause = JavaScriptBridge.create_callback(_on_js_pause)
	_cb_play = JavaScriptBridge.create_callback(_on_js_play)
	_cb_speed = JavaScriptBridge.create_callback(_on_js_speed)
	_cb_restart = JavaScriptBridge.create_callback(_on_js_restart)
	var window_obj: Variant = JavaScriptBridge.get_interface("window")
	if window_obj == null:
		return
	window_obj.vfxSelect = _cb_select
	window_obj.vfxPause = _cb_pause
	window_obj.vfxPlay = _cb_play
	window_obj.vfxSetSpeed = _cb_speed
	window_obj.vfxRestart = _cb_restart
	window_obj.vfxReady = true


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
	return String(_effects[0].get("id", ""))


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


func _on_js_select(args: Array) -> void:
	if args.size() > 0:
		select(str(args[0]))


func _on_js_pause(_args: Array) -> void:
	pause()


func _on_js_play(_args: Array) -> void:
	play()


func _on_js_speed(args: Array) -> void:
	if args.size() > 0:
		setSpeed(float(args[0]))


func _on_js_restart(_args: Array) -> void:
	restart()


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
