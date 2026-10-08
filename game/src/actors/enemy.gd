class_name Enemy
extends CharacterBody2D
## 普通敌人的有限状态机。
##
## 依据 docs/research/技术与动画方案.md 第 5 节：
## 状态从出现、寻找位置、准备攻击、攻击、恢复、被控制到死亡；
## 感知与路径规划错峰执行，每 0.1 至 0.3 秒更新一次意图；
## 追击敌人在合适距离分散站位，减少全部叠在一点的情况。

signal defeated(enemy: Enemy)

enum EnemyState { SPAWNING, SEEKING, WINDUP, ATTACKING, RECOVERING, CONTROLLED, DEAD }

const SEPARATION_RADIUS := 34.0
const SEPARATION_STRENGTH := 220.0
const INTENT_INTERVAL_MIN := 0.12
const INTENT_INTERVAL_MAX := 0.26

var def: EnemyDef = null
var state: int = EnemyState.SPAWNING
var health: float = 1.0
var target: Node2D = null
var status := StatusComponent.new()

## 攻击阶段计时。
var state_timer: float = 0.0
var attack_left: float = 0.0
## 当前攻击的唯一编号。
var attack_id: int = 0
## 已命中过的攻击编号，用于命中去重。
var _hit_attack_ids: Array[int] = []
var _hit_window_timer: float = 0.0

var intent_timer: float = 0.0
var intent_direction: Vector2 = Vector2.ZERO
var home_position: Vector2 = Vector2.ZERO
## 受限区域，敌人不会离出生点太远。
var leash_radius: float = 900.0

var _flash: float = 0.0
var _spawn_scale: float = 0.0
var _charge_direction: Vector2 = Vector2.ZERO
var _charge_time_left: float = 0.0
var _contact_cooldown: float = 0.0
var _game_clock: float = 0.0
## 是否为精英，精英增加一项可见规则。
var is_elite: bool = false

func _ready() -> void:
	add_to_group("enemies")
	collision_layer = GameConfig.bit(GameConfig.LAYER_ENEMY_BODY)
	collision_mask = GameConfig.mask([GameConfig.LAYER_WORLD, GameConfig.LAYER_COVER, GameConfig.LAYER_ENEMY_BODY])
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	status.name = "Status"
	add_child(status)
	home_position = global_position
	_build_shape()

func _build_shape() -> void:
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = def.body_radius if def != null else 15.0
	shape.shape = circle
	add_child(shape)

## 由生成器调用，写入定义与初始参数。
func configure(enemy_def: EnemyDef, elite: bool = false) -> void:
	def = enemy_def
	is_elite = elite
	var health_scale := 1.6 if elite else 1.0
	health = def.max_health * health_scale
	leash_radius = 900.0
	state = EnemyState.SPAWNING
	state_timer = 0.45
	_spawn_scale = 0.0
	queue_redraw()

func set_target(node: Node2D) -> void:
	target = node

func _physics_process(delta: float) -> void:
	if state == EnemyState.DEAD:
		return
	_game_clock += delta
	status.tick(delta)
	state_timer = maxf(0.0, state_timer - delta)
	attack_left = maxf(0.0, attack_left - delta)
	_flash = maxf(0.0, _flash - delta)
	_contact_cooldown = maxf(0.0, _contact_cooldown - delta)
	if _hit_window_timer > 0.0:
		_hit_window_timer -= delta
		if _hit_window_timer <= 0.0:
			_hit_attack_ids.clear()

	if status.is_stunned():
		if state != EnemyState.CONTROLLED:
			state = EnemyState.CONTROLLED
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		move_and_slide()
		queue_redraw()
		return
	if state == EnemyState.CONTROLLED:
		state = EnemyState.SEEKING

	match state:
		EnemyState.SPAWNING:
			_spawn_scale = minf(1.0, _spawn_scale + delta * 4.0)
			velocity = Vector2.ZERO
			if state_timer <= 0.0:
				state = EnemyState.SEEKING
		EnemyState.SEEKING:
			_tick_seeking(delta)
		EnemyState.WINDUP:
			_tick_windup(delta)
		EnemyState.ATTACKING:
			_tick_attacking(delta)
		EnemyState.RECOVERING:
			_tick_recovering(delta)
	move_and_slide()
	queue_redraw()

# --- 状态逻辑 ---

func _tick_seeking(delta: float) -> void:
	intent_timer -= delta
	if intent_timer <= 0.0:
		intent_timer = randf_range(INTENT_INTERVAL_MIN, INTENT_INTERVAL_MAX)
		_intent()
	var pursued := _pursuit_velocity(delta)
	velocity = velocity.move_toward(pursued, 1200.0 * delta)
	if attack_left <= 0.0 and _in_attack_condition():
		_begin_windup()

## 每 0.1 至 0.3 秒重新评估意图，避免每帧重算。
func _intent() -> void:
	if target == null or not is_instance_valid(target):
		intent_direction = Vector2.ZERO
		return
	intent_direction = (target.global_position - global_position).normalized()
	if GameFlow.current_room != null and not _has_line_of_sight():
		intent_direction = GameFlow.current_room.navigation_direction(global_position, target.global_position)

## 各家族的移动方式。
func _pursuit_velocity(delta: float) -> Vector2:
	if target == null or not is_instance_valid(target):
		return Vector2.ZERO
	var to_target := target.global_position - global_position
	var distance := to_target.length()
	var direction := to_target.normalized()
	if not _has_line_of_sight():
		direction = intent_direction
	match def.family:
		EnemyDef.Family.SHOOTER:
			# 远射敌人先保持射程，再修正位置。
			if distance < def.preferred_distance * 0.75:
				direction = -direction
			elif distance < def.preferred_distance:
				direction = direction.rotated(PI * 0.5)
		EnemyDef.Family.SHIELD:
			direction = direction
		EnemyDef.Family.ZONE:
			if distance < def.preferred_distance * 0.6:
				direction = -direction
		EnemyDef.Family.SUMMONER:
			if distance < def.preferred_distance * 0.8:
				direction = -direction
		_:
			if distance <= def.preferred_distance:
				direction = Vector2.ZERO
	var speed := def.move_speed
	if GameFlow.current_room != null:
		speed *= GameFlow.current_room.enemy_speed_scale
	if state == EnemyState.SEEKING and def.family == EnemyDef.Family.DASHER:
		speed *= 0.85
	var desired := direction * speed
	# 与同伴分离，避免全部叠在一点。
	desired += _separation() * SEPARATION_STRENGTH
	# 保持在受限区域内。
	var from_home := global_position - home_position
	if from_home.length() > leash_radius:
		desired += -from_home.normalized() * speed
	return desired

func _separation() -> Vector2:
	var push := Vector2.ZERO
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if candidate == self or not (candidate is Node2D) or not is_instance_valid(candidate):
			continue
		var node := candidate as Node2D
		var offset: Vector2 = global_position - node.global_position
		var distance: float = offset.length()
		if distance > 0.001 and distance < SEPARATION_RADIUS:
			push += offset.normalized() * (1.0 - distance / SEPARATION_RADIUS)
	return push

func _in_attack_condition() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var distance := global_position.distance_to(target.global_position)
	match def.family:
		EnemyDef.Family.SHOOTER:
			return distance <= def.attack_range and _has_line_of_sight()
		EnemyDef.Family.ZONE:
			return distance <= def.attack_range and _has_line_of_sight()
		EnemyDef.Family.SUMMONER:
			return distance <= def.attack_range
		EnemyDef.Family.CHASER, EnemyDef.Family.SHIELD:
			return distance <= def.attack_range * 0.55 + def.body_radius
		EnemyDef.Family.DASHER:
			return distance <= def.attack_range and distance > 60.0
	return distance <= def.attack_range * 0.5

## 视线检查：墙体与掩体会阻挡远程敌人。
func _has_line_of_sight() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		global_position, target.global_position,
		GameConfig.mask([GameConfig.LAYER_WORLD, GameConfig.LAYER_COVER])
	)
	query.collide_with_bodies = true
	return space.intersect_ray(query).is_empty()

func _begin_windup() -> void:
	state = EnemyState.WINDUP
	state_timer = def.attack_windup
	velocity = Vector2.ZERO
	if def.family == EnemyDef.Family.DASHER and target != null and is_instance_valid(target):
		_charge_direction = (target.global_position - global_position).normalized()
	GameEvents.sfx_requested.emit("enemy_windup", global_position)

func _tick_windup(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, 1400.0 * delta)
	if state_timer <= 0.0:
		state = EnemyState.ATTACKING
		state_timer = 0.16 if def.family != EnemyDef.Family.DASHER else 0.0
		_perform_attack()

func _tick_attacking(delta: float) -> void:
	match def.family:
		EnemyDef.Family.DASHER:
			velocity = _charge_direction * def.move_speed * 3.4
			_charge_time_left -= delta
			_try_contact_damage()
			if _charge_time_left <= 0.0:
				_begin_recovery(0.7)
		_:
			velocity = velocity.move_toward(Vector2.ZERO, 1400.0 * delta)
			if state_timer <= 0.0:
				_begin_recovery(def.attack_cooldown)

func _tick_recovering(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, 800.0 * delta)
	if state_timer <= 0.0:
		state = EnemyState.SEEKING
		attack_left = def.attack_cooldown

func _begin_recovery(seconds: float) -> void:
	state = EnemyState.RECOVERING
	state_timer = seconds
	velocity *= 0.3

# --- 攻击执行 ---

func _perform_attack() -> void:
	attack_id = GameFlow.next_attack_id()
	match def.family:
		EnemyDef.Family.CHASER:
			_do_melee_strike(def.attack_damage)
		EnemyDef.Family.SHIELD:
			_do_melee_strike(def.attack_damage)
		EnemyDef.Family.SHOOTER:
			_do_shot()
		EnemyDef.Family.ZONE:
			_do_zone()
		EnemyDef.Family.SUMMONER:
			_do_summon()
		EnemyDef.Family.DASHER:
			_charge_time_left = 0.5
			GameEvents.sfx_requested.emit("enemy_charge", global_position)

func _do_melee_strike(damage: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var direction := (target.global_position - global_position).normalized()
	AttackResolver.arc_attack(
		self, attack_id, global_position, direction, def.body_radius + 34.0, 130.0,
		damage, "player", 130.0, 0.0, 1.0, "", 0, "enemy_melee"
	)

func _do_shot() -> void:
	if target == null or not is_instance_valid(target):
		return
	var direction := (target.global_position - global_position).normalized()
	ProjectileFactory.volley(self.get_parent(), global_position + direction * (def.body_radius + 6.0), direction, 1, 0.0, {
		"damage_group": "enemy_projectile",
		"attack_id": attack_id,
		"friendly": false,
		"base_damage": def.attack_damage,
		"speed": 460.0,
		"lifetime": 1.5,
		"max_distance": def.attack_range,
		"radius": 6.0,
		"knockback": 80.0,
		"crit_chance": 0.0,
		"crit_multiplier": 1.0,
		"owner": self,
		"color": def.color.lightened(0.2),
	})
	GameEvents.sfx_requested.emit("enemy_shot", global_position)

func _do_zone() -> void:
	if target == null or not is_instance_valid(target):
		return
	var landing := target.global_position
	GameEvents.sfx_requested.emit("enemy_zone", landing)
	var director := GameFlow
	if director != null and director.has_method("spawn_zone"):
		director.spawn_zone({
			"position": landing,
			"radius": 60.0,
			"damage_per_second": def.attack_damage * 2.6,
			"duration": 2.4,
			"tick_interval": 0.4,
			"status": "inked",
			"color": Color(0.35, 0.3, 0.6, 0.4),
			"source": "enemy_zone",
			"hostile_to_player": true,
		})

func _do_summon() -> void:
	if get_tree().get_nodes_in_group("minions").size() >= 8:
		return
	var director := GameFlow
	if director == null or not director.has_method("spawn_enemy"):
		return
	var count := 2
	for index in range(count):
		var angle := TAU * float(index) / float(count) + randf() * 0.5
		var spawn_position := global_position + Vector2.RIGHT.rotated(angle) * 38.0
		var minion: Enemy = director.spawn_enemy("enemy_misprint_chaser", spawn_position, true)
		if minion != null:
			minion.home_position = global_position
	GameEvents.sfx_requested.emit("enemy_summon", global_position)

func _try_contact_damage() -> void:
	if target == null or not is_instance_valid(target) or _contact_cooldown > 0.0:
		return
	if global_position.distance_to(target.global_position) <= def.body_radius + 20.0:
		_contact_cooldown = 0.6
		if target.has_method("receive_damage"):
			target.receive_damage(int(def.attack_damage), self, attack_id, false, _charge_direction, 200.0, "enemy_charge")

# --- 受伤 ---

## 命中去重：同一 attack_id 只会对本体结算一次。
func was_hit_by(incoming_attack_id: int) -> bool:
	return _hit_attack_ids.has(incoming_attack_id)

func receive_damage(amount: int, source: Node, incoming_attack_id: int, is_crit: bool, direction: Vector2, knockback: float, group: String) -> int:
	if state == EnemyState.DEAD:
		return 0
	_hit_attack_ids.append(incoming_attack_id)
	_hit_window_timer = 0.35
	var final_amount := float(amount)
	# 盾卫的正面减伤：攻击方向与盾牌朝向同向时触发。
	if def.front_shield_reduction > 0.0:
		var facing := intent_direction
		if facing == Vector2.ZERO and target != null and is_instance_valid(target):
			facing = (target.global_position - global_position).normalized()
		if facing.dot(-direction.normalized()) > 0.35:
			final_amount *= (1.0 - def.front_shield_reduction)
			GameEvents.floating_text_requested.emit(global_position + Vector2(0, -20), "格挡", Color(0.9, 0.85, 0.6))
	final_amount = maxf(1.0, final_amount - def.flat_defense)
	final_amount *= (1.0 - def.defense_reduction)
	var dealt := int(maxf(1.0, floorf(final_amount)))
	health -= float(dealt)
	_flash = 0.1
	RunState.damage_dealt += dealt
	# 受击位移。
	if knockback > 0.0 and direction != Vector2.ZERO:
		velocity += direction.normalized() * knockback
	GameEvents.floating_text_requested.emit(
		global_position + Vector2(0, -def.body_radius - 6.0),
		"%d" % dealt,
		Color(1.0, 0.85, 0.3) if is_crit else Color(1.0, 1.0, 1.0)
	)
	# 受击后开始还击，避免敌人被无限连打。
	if state == EnemyState.SEEKING and attack_left > 0.0:
		attack_left = minf(attack_left, 0.35)
	if health <= 0.0:
		_die()
	return dealt

func apply_status(status_id: String, amount: int) -> void:
	if status_id == "stunned":
		status.stun(1.5)
	else:
		status.add(status_id, amount, 5.0)
	queue_redraw()

func combat_tags() -> PackedStringArray:
	var tags := status.tag_list()
	return tags

func heal(amount: float) -> void:
	health = minf(def.max_health, health + amount)

func _die() -> void:
	if state == EnemyState.DEAD:
		return
	state = EnemyState.DEAD
	collision_layer = 0
	collision_mask = 0
	RunState.note_kill()
	GameEvents.entity_died.emit(self, def.has_tag("boss"))
	GameEvents.hitstop_requested.emit(GameConfig.HITSTOP_HEAVY_MS if is_elite else GameConfig.HITSTOP_LIGHT_MS)
	defeated.emit(self)
	queue_free()

func health_ratio() -> float:
	if def == null or def.max_health <= 0.0:
		return 0.0
	return clampf(health / (def.max_health * (1.6 if is_elite else 1.0)), 0.0, 1.0)

# --- 表现 ---

func _draw() -> void:
	if def == null:
		return
	var radius := def.body_radius * (0.6 + 0.4 * _spawn_scale)
	var body := def.color
	if is_elite:
		body = body.lerp(Color(1.0, 0.85, 0.4), 0.35)
	if _flash > 0.0:
		body = Color(1, 1, 1)
	# 前摇提示：外圈随剩余时间收紧，让危险方向可以预先读到。
	if state == EnemyState.WINDUP:
		var total := maxf(0.001, def.attack_windup)
		var progress := 1.0 - clampf(state_timer / total, 0.0, 1.0)
		var telegraph := body.lerp(Color(1.0, 0.25, 0.25), 0.6)
		draw_arc(Vector2.ZERO, radius + 10.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 24, telegraph, 3.0)
	draw_set_transform(Vector2(3, radius * 0.7), 0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, radius * 1.15, Color(0.02, 0.07, 0.07, 0.28))
	draw_set_transform(Vector2.ZERO)
	match def.family:
		EnemyDef.Family.CHASER:
			draw_rect(Rect2(-radius, -radius, radius * 2, radius * 2), body.darkened(0.25))
			draw_rect(Rect2(-radius + 4, -radius + 3, radius * 1.7, radius * 1.65), Color("#e5d5bb"))
			draw_line(Vector2(-radius + 5, -radius), Vector2(-radius + 5, radius), body, 4)
			draw_line(Vector2(-5, -3), Vector2(-1, 0), Color("#4b3d40"), 2)
			draw_line(Vector2(3, 0), Vector2(7, -3), Color("#4b3d40"), 2)
		EnemyDef.Family.SHOOTER:
			draw_circle(Vector2.ZERO, radius, body.darkened(0.2))
			draw_circle(intent_direction * radius * 0.5, radius * 0.35, body.lightened(0.6))
		EnemyDef.Family.SHIELD:
			draw_rect(Rect2(-radius, -radius * 0.8, radius * 2, radius * 1.6), Color("#9d7c51"))
			draw_rect(Rect2(-radius + 3, -radius * 0.8 + 3, radius * 2 - 6, radius * 1.6 - 6), body)
			var facing := intent_direction if intent_direction != Vector2.ZERO else Vector2.RIGHT
			draw_line(facing.rotated(-0.9) * radius, facing.rotated(0.9) * radius, Color(0.95, 0.9, 0.7), 5.0)
		EnemyDef.Family.ZONE:
			for index in range(5):
				draw_circle(Vector2.RIGHT.rotated(index * TAU / 5) * radius * 0.5, radius * 0.7, body.darkened(0.2))
			draw_arc(Vector2.ZERO, radius * 0.7, 0.0, TAU, 12, body.lightened(0.4), 2.0)
		EnemyDef.Family.SUMMONER:
			draw_rect(Rect2(-radius, -radius * 0.8, radius * 2, radius * 1.6), body.darkened(0.25))
			draw_rect(Rect2(-radius * 0.7, -radius, radius * 1.4, radius * 0.4), Color("#e5e1cb"))
			draw_rect(Rect2(-radius * 0.6, 0, radius * 1.2, radius * 0.3), Color("#34464d"))
		EnemyDef.Family.DASHER:
			draw_set_transform(Vector2.ZERO, intent_direction.angle())
			draw_rect(Rect2(-radius, -radius * 0.6, radius * 2, radius * 1.2), body)
			draw_line(Vector2(-radius, radius * 0.6), Vector2(radius, radius * 0.6), Color("#f4e9cc"), 4)
			for index in range(3):
				draw_line(Vector2(-7 + index * 5, -7), Vector2(-5 + index * 5, 5), Color("#f4e9cc"), 2)
			draw_set_transform(Vector2.ZERO)
	if status.has("inked"):
		draw_arc(Vector2.ZERO, radius + 4.0, 0.0, TAU, 16, Color(0.45, 0.4, 0.85), 2.0)
	if status.is_stunned():
		draw_arc(Vector2.ZERO, radius + 7.0, 0.0, TAU, 16, Color(1.0, 0.9, 0.4), 2.0)
	_draw_health_bar(radius)

func _draw_health_bar(radius: float) -> void:
	if health_ratio() >= 1.0 and state == EnemyState.SPAWNING:
		return
	var width := radius * 2.2
	var height := 4.0
	var origin := Vector2(-width * 0.5, -radius - 12.0)
	draw_rect(Rect2(origin, Vector2(width, height)), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(origin, Vector2(width * health_ratio(), height)), Color(0.9, 0.35, 0.35))

func debug_line() -> String:
	return "%s 生命 %.0f/%.0f 状态 %d 距离 %.0f" % [
		def.display_name if def != null else "未配置",
		health,
		def.max_health if def != null else 0.0,
		state,
		global_position.distance_to(target.global_position) if target != null and is_instance_valid(target) else -1.0,
	]
