class_name AttackResolver
extends RefCounted
## 近战查询与伤害派发的公共入口。
##
## 依据 docs/research/技术与动画方案.md 第 4 节：
## 近战使用扇形查询；每次攻击带 attack_id，对同一目标设置命中去重，
## 避免在连续多个物理帧重复扣血。墙、角色身体、攻击命中框与受伤框使用独立碰撞层。

## 一次扇形查询并派发伤害。返回命中的目标数量。
## 参数 origin 为攻击起点，direction 为单位方向，radius 为半径，arc_degrees 为张角。
static func arc_attack(
	attacker: Node2D,
	attack_id: int,
	origin: Vector2,
	direction: Vector2,
	radius: float,
	arc_degrees: float,
	base_damage: float,
	target_group: String,
	knockback: float,
	crit_chance: float,
	crit_multiplier: float,
	applies_status: String,
	status_layers: int,
	damage_group: String,
	target_tags_of_interest: bool = true
) -> int:
	if attacker == null or not is_instance_valid(attacker):
		return 0
	var dir := direction.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var half_arc := deg_to_rad(arc_degrees) * 0.5
	var space := attacker.get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, origin)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = GameConfig.bit(GameConfig.LAYER_PLAYER_BODY) if target_group == "player" else GameConfig.bit(GameConfig.LAYER_ENEMY_BODY)
	var hits := space.intersect_shape(query, 32)

	var hit_count := 0
	for hit in hits:
		var collider = hit.get("collider")
		if collider == null or not is_instance_valid(collider):
			continue
		if not collider.is_in_group(target_group):
			continue
		if collider.has_method("was_hit_by") and collider.was_hit_by(attack_id):
			continue
		var to_target: Vector2 = (collider.global_position - origin)
		if to_target.length() > 0.001:
			var angle := absf(dir.angle_to(to_target.normalized()))
			if angle > half_arc:
				continue
		if not line_of_sight(attacker, origin, collider.global_position):
			continue
		var target_tags := PackedStringArray()
		if target_tags_of_interest and collider.has_method("combat_tags"):
			target_tags = collider.combat_tags()
		var computed := _build_damage(base_damage, damage_group, target_tags, crit_chance, crit_multiplier)
		if target_group == "player":
			computed = DamageCalc.new()
			computed.base = base_damage
		var result := computed.resolve()
		if collider.has_method("receive_damage"):
			var applied: int = collider.receive_damage(
				result["amount"], attacker, attack_id, result["is_crit"], dir, knockback, damage_group
			)
			if applied > 0:
				hit_count += 1
				if not applies_status.is_empty() and collider.has_method("apply_status"):
					collider.apply_status(applies_status, status_layers)
				GameEvents.attack_landed.emit(attack_id, attacker, collider, applied, result["is_crit"], damage_group)
	return hit_count

static func line_of_sight(attacker: Node2D, origin: Vector2, destination: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(origin, destination, GameConfig.mask([GameConfig.LAYER_WORLD, GameConfig.LAYER_COVER]))
	return attacker.get_world_2d().direct_space_state.intersect_ray(query).is_empty()

static func build_damage(base_damage: float, target_tags: PackedStringArray, crit_chance: float, crit_multiplier: float, global_multiplier: float = 1.0) -> DamageCalc:
	var calc := DamageCalc.new()
	calc.base = base_damage
	var engine := RunState.modifiers
	# 同组加成相加，跨组相乘。武器组使用 damage，社团组与持续伤害区使用 club_damage。
	calc.add_group_bonus(DamageCalc.GROUP_WEAPON, engine.resolve(0.0, "damage"))
	calc.add_group_bonus(DamageCalc.GROUP_CLUB, engine.resolve(0.0, "club_damage"))
	var conditional := engine.conditional_multiplier(target_tags)
	if absf(conditional - 1.0) > 0.0001:
		calc.add_independent("conditional_tags", conditional)
	if absf(global_multiplier - 1.0) > 0.0001:
		calc.add_independent("situational", global_multiplier)
	var total_crit := crit_chance + engine.resolve(0.0, "crit_chance")
	calc.set_crit(total_crit, crit_multiplier, RunState.rng.randf())
	return calc

static func _build_damage(base_damage: float, damage_group: String, target_tags: PackedStringArray, crit_chance: float, crit_multiplier: float) -> DamageCalc:
	return build_damage(base_damage, target_tags, crit_chance, crit_multiplier)
