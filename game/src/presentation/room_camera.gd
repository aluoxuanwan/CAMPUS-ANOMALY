class_name CameraDirector
extends Camera2D
## 完整展示教室，给上下界面留出空间。
var shake_strength := 0.0
var shake_setting := 1.0
var room_size := Vector2(1152, 672)
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	position_smoothing_enabled = false
	_rng.randomize()
	GameEvents.camera_shake_requested.connect(_on_shake_requested)
	get_viewport().size_changed.connect(_fit)

func set_follow(_node: Node2D) -> void:
	pass

func clamp_to_room(value: Vector2) -> void:
	room_size = value
	_fit()

func _fit() -> void:
	var viewport := get_viewport_rect().size
	var scale_value := minf((viewport.x - 64.0) / room_size.x, (viewport.y - 204.0) / room_size.y)
	zoom = Vector2.ONE * maxf(0.1, scale_value)
	position = room_size * 0.5
	offset = Vector2.ZERO

func _on_shake_requested(strength: float) -> void:
	shake_strength = maxf(shake_strength, strength * shake_setting)

func _process(delta: float) -> void:
	shake_strength = maxf(0.0, shake_strength - delta * 45.0)
	offset = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * shake_strength
