extends SceneTree
## Run with Godot --path godot --script ../tools/tests/fire_tile_motion_check.gd
var failures := 0
var studio: Node
var effect: Node
var motion: Node

func _initialize() -> void:
	call_deferred("run")

func verify(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func step(seconds: float = 0.05) -> void:
	await create_timer(seconds).timeout
	await RenderingServer.frame_post_draw

func mouse(point: Vector2, pressed: bool) -> void:
	var hover := InputEventMouseMotion.new()
	hover.position = point
	hover.global_position = point
	root.push_input(hover, true)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = pressed
	root.push_input(event, true)

func move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)

func run() -> void:
	root.size = Vector2i(1000, 700)
	studio = load("res://scenes/studio/studio.tscn").instantiate()
	root.add_child(studio)
	await step(0.15)
	effect = studio._instance
	motion = effect._motion
	var bridge := root.get_node("VfxBridge")
	verify(effect._side == 109.5, "Waw tile dimensions changed")
	verify(effect._letter_viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "Static letter mask must use on-demand rendering after initialization")
	verify(not effect._sparks.local_coords, "Top particles must stay in world space")
	for sparks in effect._side_sparks:
		verify(not sparks.local_coords, "Side particles must stay in world space")
	var start: Vector2 = motion.center
	var camera_yaw: float = studio._camera_rig.yaw_degrees
	# GUI receives the press; it must pause without moving the tile.
	var button: Control = studio._ui._play_btn
	mouse(button.get_global_rect().get_center(), true)
	mouse(button.get_global_rect().get_center(), false)
	await step()
	verify(paused, "GUI play button did not receive click")
	verify(motion.center == start and not motion.flying, "GUI click launched flight")
	bridge.play()
	# Blank-space click and retarget use the real input dispatch path.
	mouse(Vector2(830, 290), true)
	mouse(Vector2(830, 290), false)
	await step(0.08)
	verify(motion.flying and motion.center.x > start.x, "Blank-space flight failed")
	verify(effect._wind_strength > 0.1, "Flight did not produce wind")
	verify(effect._letter_viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "Resume must not redraw the static letter every frame")
	verify(effect._mat.get_shader_parameter("flow_direction").x < -0.1, "Rightward travel must push flame left")
	bridge.pause()
	var frozen: Vector2 = motion.center
	var flame_time: float = effect._time
	await step(0.12)
	verify(motion.center == frozen and effect._time == flame_time, "Pause did not freeze motion and effect")
	bridge.play()
	mouse(Vector2(430, 450), true)
	mouse(Vector2(430, 450), false)
	await step(0.8)
	verify(motion.center.distance_to(Vector2(430, 450)) < 0.1, "Flight retarget missed endpoint")
	# A grab must preserve its offset and can release over GUI.
	var grab: Vector2 = motion.center + Vector2(20, 10)
	mouse(grab, true)
	verify(motion.dragging, "Tile press did not start dragging")
	move(grab + Vector2(150, -60))
	verify(motion.center.distance_to(Vector2(580, 390)) < 0.1, "Drag offset was not preserved")
	mouse(Vector2(120, 120), false)
	verify(not motion.dragging, "Release over GUI stuck the drag")
	verify(is_equal_approx(studio._camera_rig.yaw_degrees, camera_yaw), "Tile input moved the camera")
	await step(1.2)
	verify(effect._wind_strength < 0.01, "Wind did not settle after stopping")
	verify(effect._mat.get_shader_parameter("flow_direction").distance_to(Vector2.UP * -1.0) < 0.04, "Flames did not return upward")
	# Grab a moving tile: animation must stop without snapping its center.
	motion.fly_to(Vector2(760, 280))
	await step(0.06)
	var intercept: Vector2 = motion.center
	mouse(intercept, true)
	verify(motion.dragging and not motion.flying, "Grab did not interrupt flight")
	verify(motion.center.distance_to(intercept) < 0.1, "Flight grab snapped center")
	move(Vector2(1400, 1000))
	verify(motion.center.x <= 1000 - effect._side * 0.5, "Drag escaped right edge")
	verify(motion.center.y <= 700 - effect._side * 0.5, "Drag escaped bottom edge")
	bridge.pause()
	verify(not motion.dragging, "Pausing left a stuck mouse grab")
	mouse(motion.center, false)
	bridge.play()
	await step(1.2)
	# Resize is a layout operation, not an impulse of wind.
	root.size = Vector2i(800, 600)
	await step(0.15)
	verify(motion.center.x <= 800 - effect._side * 0.5, "Resize left tile outside viewport")
	verify(effect._motion_velocity.length() < 0.01, "Resize generated false velocity")
	studio.restart_effect()
	await step(0.15)
	effect = studio._instance
	verify(effect._motion.center.distance_to(Vector2(400, 300)) < 0.1, "Restart did not recenter")
	print("Motion checks complete: %s failures" % failures)
	quit(1 if failures else 0)
