class_name Deployable
extends CharacterBody2D
## 召唤物。机器人社炮台与戏剧社诱饵共用这一实现。
##
## 依据 docs/research/玩法机制与校园设计.md 第 3 节：
## 首版实现四项主动能力，用于验证控制、召唤与范围能力是否容易理解。

enum Kind { TURRET, DECOY }

var kind: int = Kind.TURRET
var radius: float = 260.0
var duration: float = 8.0
var fire_interval: float = 0.55
var damage: float = 7.0
var health: float = 40.0
var max_health: float = 40.0
var color: Color = Color(0.6, 0.85, 0.95)

var _life_left: float = 0.0
var _fire_left: float = 0.0
var _taunted: Array[Node] = []
var _flash: float = 0.0

func _ready() -> void:
	if kind == Kind.DECOY:
		add_to_group("player")
		collision_layer = GameConfig.bit(GameConfig.LAYER_PLAYER_BODY)
		collision_mask = 0
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 13.0
		shape.shape = circle
		add_child(shape)
	else:
		collision_layer = 0
		collision_mask = 0

func configure(config: Dictionary) -> void:
	var kind_name := str(config.get("kind", "turret"))
	kind = Kind.TURRET if kind_name == "turret" else Kind.DECOY
	radius = float(config.get("radius", 260.0))
	duration = float(config.get("duration", 8.0))
	fire_interval = float(config.get("fire_interval", 0.55))
	damage = float(config.get("damage", 7.0))
	health = float(config.get("health", 40.0))
	max_health = health
	color = config.get("color", color)
	_life_left = duration
	_fire_left = fire_interval
	add_to_group("deployables")
	z_index = 2
	queue_redraw()

func _process(delta: float) -> void:
	_life_left -= delta
	_flash = maxf(0.0, _flash - delta)
	if kind == Kind.TURRET:
		_fire_left -= delta
		if _fire_left <= 0.0:
			_fire_left = fire_interval
			_fire()
	else:
		_maintain_taunt()
	if _life_left <= 0.0:
		_release()
	queue_redraw()

func _fire() -> void:
	var target := _nearest_enemy()
	if target == null:
		return
	var direction := (target.global_position - global_position).normalized()
	ProjectileFactory.volley(get_parent(), global_position + direction * 14.0, direction, 1, 0.0, {
		"damage_group": "ability_turret",
		"attack_id": GameFlow.next_attack_id(),
		"friendly": true,
		"base_damage": damage,
		"speed": 560.0,
		"lifetime": 1.0,
		"max_distance": radius,
		"radius": 5.0,
		"knockback": 40.0,
		"crit_chance": 0.05,
		"crit_multiplier": 1.8,
		"owner": self,
		"color": color,
	})

func _nearest_enemy() -> Node2D:
	var best: Node2D = null
	var best_distance := radius
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if not (candidate is Node2D) or not is_instance_valid(candidate):
			continue
		var node := candidate as Node2D
		var distance := global_position.distance_to(node.global_position)
		if distance < best_distance and AttackResolver.line_of_sight(self, global_position, node.global_position):
			best_distance = distance
			best = node
	return best

## 诱饵吸引范围内敌人的注意，诱饵消失后目标回到玩家。
func _maintain_taunt() -> void:
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(candidate) or not candidate.has_method("set_target"):
			continue
		var node := candidate as Node2D
		var distance := global_position.distance_to(node.global_position)
		if distance <= radius:
			if not _taunted.has(candidate):
				_taunted.append(candidate)
			candidate.set_target(self)
	for candidate in _taunted.duplicate():
		if not is_instance_valid(candidate):
			_taunted.erase(candidate)
			continue
		var node := candidate as Node2D
		if global_position.distance_to(node.global_position) > radius:
			candidate.set_target(GameFlow.player)
			_taunted.erase(candidate)

func _release() -> void:
	for node in _taunted:
		if is_instance_valid(node) and node.has_method("set_target"):
			node.set_target(GameFlow.player)
	_taunted.clear()
	queue_free()

func receive_damage(amount: int, _source: Node, _attack_id: int, _is_crit: bool, _direction: Vector2, _knockback: float, _group: String) -> int:
	if kind != Kind.DECOY:
		return 0
	health -= float(amount)
	_flash = 0.1
	if health <= 0.0:
		_release()
	return amount

func combat_tags() -> PackedStringArray:
	var tags := PackedStringArray(["deployable"])
	return tags

func _draw() -> void:
	var body := color
	if _flash > 0.0:
		body = Color(1, 1, 1)
	if kind == Kind.TURRET:
		draw_rect(Rect2(-9, -9, 18, 18), body.darkened(0.3))
		draw_rect(Rect2(-11, -11, 22, 22), body, false, 2.0)
		var target := _nearest_enemy()
		if target != null:
			draw_line(Vector2.ZERO, (target.global_position - global_position).normalized() * 16.0, body.lightened(0.4), 3.0)
	else:
		draw_circle(Vector2.ZERO, 13.0, body.darkened(0.3))
		draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 20, body, 2.0)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(body.r, body.g, body.b, 0.18), 1.0)
	# 剩余时间指示。
	var ratio := clampf(_life_left / maxf(0.001, duration), 0.0, 1.0)
	draw_rect(Rect2(-12, 16, 24.0 * ratio, 3.0), body)
