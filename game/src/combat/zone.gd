class_name Zone
extends Node2D
## 持续伤害区域。墨迹、冲刺残影、轨道弹与敌人危险区共用这一实现。
##
## 依据 docs/research/技术与动画方案.md 第 4 节：
## 同一来源的多次命中需要合并停顿请求，这里按 tick_interval 结算，
## 每次结算使用独立 attack_id，避免逐帧重复扣血。

var radius: float = 90.0
var damage_per_second: float = 8.0
var duration: float = 3.0
var tick_interval: float = 0.4
var hostile_to_player: bool = false
var applies_status: String = ""
var status_layers: int = 1
var source_id: String = "zone"
var color: Color = Color(0.4, 0.35, 0.7, 0.35)

var _tick_left: float = 0.0
var _life_left: float = 0.0
var _pulse: float = 0.0

func configure(config: Dictionary) -> void:
	radius = float(config.get("radius", 90.0))
	damage_per_second = float(config.get("damage_per_second", 8.0))
	duration = float(config.get("duration", 3.0))
	tick_interval = maxf(0.08, float(config.get("tick_interval", 0.4)))
	hostile_to_player = bool(config.get("hostile_to_player", false))
	applies_status = str(config.get("status", ""))
	status_layers = int(config.get("status_layers", 1))
	source_id = str(config.get("source", "zone"))
	color = config.get("color", color)
	_life_left = duration
	_tick_left = tick_interval * 0.5
	z_index = 1
	queue_redraw()

func _process(delta: float) -> void:
	_life_left -= delta
	_tick_left -= delta
	_pulse += delta * 3.0
	if _tick_left <= 0.0:
		_tick_left = tick_interval
		_apply_tick()
	if _life_left <= 0.0:
		queue_free()
	queue_redraw()

func _apply_tick() -> void:
	var amount := damage_per_second * tick_interval
	var groups := ["player"] if hostile_to_player else ["enemies"]
	var attack_id := GameFlow.next_attack_id()
	for group_name in groups:
		for candidate in get_tree().get_nodes_in_group(group_name):
			if not (candidate is Node2D) or not is_instance_valid(candidate):
				continue
			var node := candidate as Node2D
			if global_position.distance_to(node.global_position) > radius + 12.0:
				continue
			var tags := PackedStringArray()
			if node.has_method("combat_tags"):
				tags = node.combat_tags()
			var calc := AttackResolver.build_damage(amount, tags, 0.0, 1.0)
			if hostile_to_player:
				calc = DamageCalc.new()
				calc.base = amount
			var result := calc.resolve()
			if node.has_method("receive_damage"):
				var applied: int = node.receive_damage(
					result["amount"], self, attack_id, false, (node.global_position - global_position).normalized(), 0.0, source_id
				)
				if applied > 0:
					GameEvents.attack_landed.emit(attack_id, self, node, applied, false, source_id)
					if not applies_status.is_empty() and node.has_method("apply_status"):
						node.apply_status(applies_status, status_layers)

func time_left_ratio() -> float:
	if duration <= 0.0:
		return 0.0
	return clampf(_life_left / duration, 0.0, 1.0)

func _draw() -> void:
	var fade := 0.35 + 0.25 * time_left_ratio()
	var fill := Color(color.r, color.g, color.b, color.a * fade)
	draw_circle(Vector2.ZERO, radius, fill)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(color.r, color.g, color.b, 0.85), 2.0)
	for index in range(3):
		var ring_radius := radius * (0.3 + 0.25 * float(index)) + sin(_pulse + float(index)) * 3.0
		draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 24, Color(color.r, color.g, color.b, 0.25), 1.0)
