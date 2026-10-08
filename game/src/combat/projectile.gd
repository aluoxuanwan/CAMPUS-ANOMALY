class_name Projectile
extends Node2D
## 投射物。支持直线、回旋、反弹与穿透命中记录。
##
## 依据 docs/research/技术与动画方案.md 第 4 节：
## 高速投射物应检查上一帧到本帧的扫掠路径，以防穿过薄墙和小敌人。
## 每次攻击带 attack_id，对同一目标命中去重。

## 命中目标时发出，供表现层播放音效与特效。
signal impact(world_position: Vector2, target: Node)

## 伤害分组标签，用于触发链来源标识。
var damage_group: String = "projectile"
## 本次攻击的唯一编号。
var attack_id: int = 0
## 是否属于玩家阵营，决定命中哪一组目标。
var friendly: bool = true
## 基础伤害。
var base_damage: float = 8.0
## 飞行速度。
var speed: float = 600.0
## 剩余寿命。
var lifetime: float = 0.6
## 最大飞行距离，到达后回收或折返。
var max_distance: float = 320.0
## 碰撞半径。
var radius: float = 7.0
## 是否回旋。
var boomerang: bool = false
## 折返后的速度系数。
var return_speed_scale: float = 0.85
## 是否撞墙反弹。
var ricochet: bool = false
## 反弹次数上限。
var ricochet_max: int = 2
## 命中是否附加状态。
var applies_status: String = ""
var status_layers: int = 1
## 击退强度。
var knockback: float = 120.0
var crit_chance: float = 0.05
var crit_multiplier: float = 1.8
## 命中停顿档位。
var heavy_impact: bool = false
## 发射者，用于回旋折返与归属判定。
var owner_node: Node2D = null
## 反弹次数，供粉笔解析类词条读取。
var bounce_count: int = 0
## 该投射物是否允许再次触发词条。
var allow_chain: bool = false

var _direction: Vector2 = Vector2.RIGHT
var _travelled: float = 0.0
var _returning: bool = false
var _hit_targets: Array[int] = []
var _color: Color = Color(1, 1, 1)
var _dead: bool = false
var _sweep_position := Vector2.ZERO

func setup(config: Dictionary) -> void:
	damage_group = str(config.get("damage_group", "projectile"))
	attack_id = int(config.get("attack_id", 0))
	friendly = bool(config.get("friendly", true))
	base_damage = float(config.get("base_damage", 8.0))
	speed = float(config.get("speed", 600.0))
	lifetime = float(config.get("lifetime", 0.6))
	max_distance = float(config.get("max_distance", 320.0))
	radius = float(config.get("radius", 7.0))
	boomerang = bool(config.get("boomerang", false))
	return_speed_scale = float(config.get("return_speed_scale", 0.85))
	ricochet = bool(config.get("ricochet", false))
	ricochet_max = int(config.get("ricochet_max", 2))
	applies_status = str(config.get("applies_status", ""))
	status_layers = int(config.get("status_layers", 1))
	knockback = float(config.get("knockback", 120.0))
	crit_chance = float(config.get("crit_chance", 0.05))
	crit_multiplier = float(config.get("crit_multiplier", 1.8))
	heavy_impact = bool(config.get("heavy_impact", false))
	owner_node = config.get("owner")
	allow_chain = bool(config.get("allow_chain", false))
	_color = config.get("color", Color(1.0, 0.95, 0.8))
	_direction = (config.get("direction", Vector2.RIGHT) as Vector2).normalized()
	rotation = _direction.angle()
	z_index = 6
	queue_redraw()

func _physics_process(delta: float) -> void:
	if _dead:
		return
	lifetime -= delta
	if lifetime <= 0.0:
		_despawn()
		return

	var previous := global_position
	if _returning:
		if owner_node != null and is_instance_valid(owner_node):
			var to_owner: Vector2 = (owner_node.global_position - global_position)
			if to_owner.length() <= radius + 14.0:
				_despawn()
				return
			_direction = to_owner.normalized()
		else:
			_despawn()
			return
	var step := _direction * speed * delta
	if _returning:
		step *= return_speed_scale
	var next := previous + step
	_travelled += step.length()
	rotation = _direction.angle()

	if not _resolve_sweep(previous, next):
		return
	global_position = _sweep_position

	if boomerang and not _returning and _travelled >= max_distance:
		_returning = true
		_hit_targets.clear()
		attack_id = GameFlow.next_attack_id()
		if owner_node != null and is_instance_valid(owner_node):
			_direction = (owner_node.global_position - global_position).normalized()

	if not boomerang and _travelled >= max_distance:
		_despawn()

## 扫掠查询。返回真表示投射物继续飞行。
func _resolve_sweep(from: Vector2, to: Vector2) -> bool:
	_sweep_position = to
	var space := get_world_2d().direct_space_state
	var obstacles := GameConfig.mask([GameConfig.LAYER_WORLD, GameConfig.LAYER_COVER])
	var targets := GameConfig.mask([GameConfig.LAYER_ENEMY_BODY]) if friendly else GameConfig.mask([GameConfig.LAYER_PLAYER_BODY])
	var query := PhysicsRayQueryParameters2D.create(from, to, targets | obstacles)
	query.collide_with_bodies = true
	var excluded: Array[RID] = []
	if owner_node is CollisionObject2D:
		excluded.append(owner_node.get_rid())
	for id in _hit_targets:
		var old_target = instance_from_id(id)
		if old_target is CollisionObject2D:
			excluded.append(old_target.get_rid())
	query.exclude = excluded
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider = hit.get("collider")
	var point: Vector2 = hit.get("position", to)
	var normal: Vector2 = hit.get("normal", -_direction)
	if collider != null and is_instance_valid(collider) and _is_target(collider):
		var target_id: int = (collider as Node).get_instance_id()
		if not _hit_targets.has(target_id):
			_hit_targets.append(target_id)
			_apply_hit(collider, point)
		# 该投射物已经记录过此目标，继续飞行以免卡在目标体内。
		if not boomerang:
			global_position = point
			_despawn()
			return false
		return true
	# 撞到墙体或掩体。
	var level_hit: bool = collider != null and is_instance_valid(collider) and collider.has_method("receive_level_hit")
	if level_hit:
		collider.receive_level_hit(base_damage, _direction)
	if ricochet and bounce_count < ricochet_max:
		bounce_count += 1
		_direction = _direction.bounce(normal).normalized()
		_sweep_position = point + _direction * (radius + 1.0)
		queue_redraw()
		return true
	global_position = point
	_despawn()
	return false

func _is_target(node: Node) -> bool:
	if friendly:
		return node.is_in_group("enemies")
	return node.is_in_group("player")

## 派发一次命中。回旋投射物命中后继续飞行，其余由寿命与距离决定回收。
func _apply_hit(target: Node, point: Vector2) -> void:
	var tags := PackedStringArray()
	if target.has_method("combat_tags"):
		tags = target.combat_tags()
	# 粉笔解析类词条按反弹次数提高本次伤害。
	var bounce_bonus := 1.0 + RunState.modifiers.resolve(0.0, "ricochet_damage") * float(bounce_count)
	var calc := AttackResolver.build_damage(base_damage, tags, crit_chance, crit_multiplier, bounce_bonus)
	if not friendly:
		calc = DamageCalc.new()
		calc.base = base_damage
	var result := calc.resolve()
	var applied := 0
	if target.has_method("receive_damage"):
		applied = target.receive_damage(
			result["amount"], owner_node, attack_id, result["is_crit"], _direction, knockback, damage_group
		)
	if applied > 0:
		if not applies_status.is_empty() and target.has_method("apply_status"):
			target.apply_status(applies_status, status_layers)
		if friendly and boomerang and owner_node is Player and RunState.modifiers.stack_count("sports_mark") > 0:
			owner_node.add_motion_mark(point)
		GameEvents.attack_landed.emit(attack_id, owner_node, target, applied, result["is_crit"], damage_group)
		GameEvents.hitstop_requested.emit(GameConfig.HITSTOP_HEAVY_MS if heavy_impact else GameConfig.HITSTOP_LIGHT_MS)
		impact.emit(point, target)

func _despawn() -> void:
	if _dead:
		return
	_dead = true
	queue_free()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, _color)
	draw_circle(Vector2.ZERO, radius * 0.55, _color.lightened(0.35))
	draw_arc(Vector2.ZERO, radius, -0.6, 0.6, 8, _color.darkened(0.4), 1.5)
