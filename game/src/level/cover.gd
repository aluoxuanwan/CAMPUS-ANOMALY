class_name Cover
extends StaticBody2D
## 可破坏掩体。课桌、书架与实验台共用这一实现。
##
## 依据 docs/research/技术与动画方案.md 第 5 节：
## 可破坏物要有明确的受击与消失规则，避免碰撞留在原地或破坏后把出口封住。

signal destroyed(cover: Cover)

var health: float = 30.0
var max_health: float = 30.0
var active: bool = true
var blocks_projectiles: bool = true
var cell: Vector2i = Vector2i.ZERO
var size: Vector2 = Vector2(42, 42)
var tint: Color = Color(0.72, 0.58, 0.38)
var _flash: float = 0.0

func configure(cell_position: Vector2i, cover_size: float, cover_health: float, cover_tint: Color) -> void:
	cell = cell_position
	size = Vector2(cover_size, cover_size)
	health = cover_health
	max_health = cover_health
	tint = cover_tint

func _ready() -> void:
	add_to_group("covers")
	collision_layer = GameConfig.bit(GameConfig.LAYER_COVER) if active else 0
	visible = active
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	add_child(shape)

## 铃声阶段切换时改变掩体状态。取消激活会同时关闭碰撞。
func set_active(value: bool) -> void:
	if active == value:
		return
	if value and is_inside_tree():
		for actor in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("enemies"):
			if actor is Node2D and actor.global_position.distance_to(global_position) < size.length() * 0.5 + 20.0:
				return
	active = value
	collision_layer = GameConfig.bit(GameConfig.LAYER_COVER) if value else 0
	visible = value
	queue_redraw()

## 投射物撞击掩体时调用。
func receive_level_hit(amount: float, _direction: Vector2) -> void:
	if not active:
		return
	health -= maxf(1.0, amount * 0.5)
	_flash = 0.08
	if health <= 0.0:
		break_cover()
	queue_redraw()

## 近战或范围伤害对掩体的结算。
func receive_damage(amount: int, _source: Node, _attack_id: int, _is_crit: bool, _direction: Vector2, _knockback: float, _group: String) -> int:
	if not active:
		return 0
	health -= float(amount)
	_flash = 0.08
	if health <= 0.0:
		break_cover()
	queue_redraw()
	return amount

func break_cover() -> void:
	if not active:
		return
	active = false
	collision_layer = 0
	visible = false
	GameEvents.sfx_requested.emit("cover_break", global_position)
	destroyed.emit(self)
	queue_free()

func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		queue_redraw()

func _draw() -> void:
	if not active:
		return
	var color := tint
	if _flash > 0.0:
		color = Color(1, 1, 1)
	var rect := Rect2(-size * 0.5, size)
	draw_rect(Rect2(rect.position + Vector2(4, 7), rect.size), Color(0.05, 0.1, 0.08, 0.25))
	draw_rect(rect, Color("#725842"))
	draw_rect(Rect2(rect.position + Vector2(2, 2), rect.size - Vector2(4, 9)), color)
	draw_rect(Rect2(rect.position + Vector2(7, 8), Vector2(17, 20)), Color("#e7dcc1"))
	draw_line(rect.position + Vector2(15, 8), rect.position + Vector2(15, 28), Color("#b3a285"), 1)
	draw_rect(Rect2(rect.position + Vector2(29, 12), Vector2(3, 17)), Color("#536c7a"))
	draw_rect(Rect2(rect.position + Vector2(8, 37), Vector2(27, 7)), color.darkened(0.25))
	if health < max_health:
		var ratio := clampf(health / max_health, 0.0, 1.0)
		var bar := Rect2(Vector2(-size.x * 0.5, -size.y * 0.5 - 7.0), Vector2(size.x * ratio, 3.0))
		draw_rect(bar, Color(0.95, 0.8, 0.4))
