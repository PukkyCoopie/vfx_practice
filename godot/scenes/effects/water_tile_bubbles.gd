extends Node2D
## Six reusable bubble sprites and at most two departure ripples.
var target: Control
var side := 109.5
var _bubbles: Array[Dictionary] = []
var _ripples: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _spawn_timer := 0.08

func setup(holder: Control) -> void:
	target = holder
	_rng.seed = 3917
	var texture := _bubble_texture()
	for i in 6:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.visible = false
		add_child(sprite)
		_bubbles.append({"sprite": sprite, "age": 0.0, "life": 0.0, "origin": Vector2.ZERO, "velocity": Vector2.ZERO, "radius": 1.0, "phase": 0.0})

func advance(delta: float, tile_side: float, velocity: Vector2) -> void:
	side = tile_side
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn(velocity)
		_spawn_timer = _rng.randf_range(0.30, 0.46)
	for bubble in _bubbles:
		if bubble.age >= bubble.life:
			continue
		bubble.age += delta
		var age: float = bubble.age
		var t: float = minf(age / bubble.life, 1.0)
		var sprite: Sprite2D = bubble.sprite
		sprite.visible = t < 1.0
		# Origins stay in canvas space: released bubbles do not follow a dragged tile.
		sprite.position = bubble.origin + bubble.velocity * age + Vector2(sin(age * 3.2 + bubble.phase) - sin(bubble.phase), -age * age * 1.2) * side * 0.035
		var scale_factor: float = lerpf(0.55, 1.0, smoothstep(0.0, 0.18, t)) * lerpf(1.0, 0.6, smoothstep(0.65, 1.0, t))
		sprite.scale = Vector2.ONE * bubble.radius * 2.0 / 48.0 * scale_factor
		sprite.modulate.a = smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.65, 1.0, t)) * 0.90
	for i in range(_ripples.size() - 1, -1, -1):
		_ripples[i].age += delta
		if _ripples[i].age >= 0.55:
			_ripples.remove_at(i)
	queue_redraw()

func _spawn(velocity: Vector2) -> void:
	for bubble in _bubbles:
		if bubble.age < bubble.life:
			continue
		var edge := _rng.randi_range(0, 3)
		var normal := Vector2.UP.rotated(edge * PI * 0.5)
		var source := normal * 0.49 + normal.orthogonal() * _rng.randf_range(-0.34, 0.34)
		bubble.origin = target.position + target.size * 0.5 + source * side
		bubble.velocity = normal * side * _rng.randf_range(0.11, 0.20) + Vector2.UP * side * 0.09 + velocity.limit_length(side * 2.0) * 0.035
		bubble.age = 0.0
		bubble.life = _rng.randf_range(1.35, 1.85)
		bubble.radius = side * _rng.randf_range(0.040, 0.066)
		bubble.phase = _rng.randf_range(0.0, TAU)
		if _ripples.size() < 2:
			_ripples.append({"point": source, "age": 0.0})
		return

func _draw() -> void:
	if target == null:
		return
	var center := target.position + target.size * 0.5
	for ripple in _ripples:
		var t: float = ripple.age / 0.55
		var point: Vector2 = ripple.point
		# A short inward-facing arc keeps the departure ripple near the water edge.
		var inward := (-point).angle()
		draw_arc(center + point * side, side * lerpf(0.025, 0.12, t), inward - 1.1, inward + 1.1, 16, Color(0.60, 0.94, 1.0, sin(t * PI) * 0.44), maxf(side * 0.009, 0.7), true)

func _bubble_texture() -> Texture2D:
	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	for y in 48:
		for x in 48:
			var p := (Vector2(x, y) + Vector2.ONE * 0.5 - Vector2.ONE * 24.0) / 24.0
			var r := p.length()
			var rim := exp(-pow((r - 0.80) / 0.11, 2.0))
			var lighting := 0.55 + 0.45 * pow(maxf(0.0, p.normalized().dot(Vector2(-0.6, -0.8))), 2.0)
			var glint := exp(-p.distance_squared_to(Vector2(-0.30, -0.49)) / 0.015)
			var alpha := clampf(rim * lighting * 0.86 + glint * 0.95, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.65 + glint * 0.3, 0.93 + glint * 0.07, 1.0, alpha))
	return ImageTexture.create_from_image(img)
