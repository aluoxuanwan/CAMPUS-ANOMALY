class_name Player
extends CharacterBody2D
## 主角控制器。移动、瞄准、武器攻击、冲刺无敌与主动技能。
##
## 依据 docs/research/技术与动画方案.md 第 4 节：
## 输入缓冲 80 至 120 ms；冲刺有独立无敌窗口；
## 攻击方向、武器方向与身体朝向独立记录。
## 判定使用局内时间，暂停与慢动作不改变冷却结果。

signal aim_changed(direction: Vector2)
## 请求在世界中生成一个持续区域。
signal zone_requested(config: Dictionary)
## 请求生成一个召唤物。
signal deployable_requested(config: Dictionary)
## 状态变化，供 HUD 与动画层使用。
signal state_changed(state_name: String)

enum State { NORMAL, DASH, ATTACK, DEAD }

const BODY_RADIUS := 14.0
const ACCELERATION := 1500.0
const FRICTION := 1900.0
## 攻击前摇与有效窗口期间的移动倍率，让出手有重量感。
const ATTACK_MOVE_SCALE := 0.45
## 冲刺结束后仍允许取消后摇的时间窗口。
const DASH_CANCEL_WINDOW := 0.12

var state: int = State.NORMAL

# --- 输入状态。自检脚本可以直接写入这些字段。 ---
var input_move: Vector2 = Vector2.ZERO
var input_aim_world: Vector2 = Vector2.ZERO
var input_attack_held: bool = false
var input_attack_pressed: bool = false
var input_dash_pressed: bool = false
var input_swap_pressed: bool = false
var input_reload_pressed: bool = false
var input_ability_pressed: int = -1
## 自检或手柄模式下强制使用自动瞄准。
var use_auto_aim: bool = false
## 是否接受真实输入。自检时关闭。
var accepts_device_input: bool = true

var aim_direction: Vector2 = Vector2.RIGHT
var body_facing: Vector2 = Vector2.RIGHT

# --- 武器 ---
var weapon_index: int = 0
var weapon: WeaponDef = null
var attack_phase: int = GameConfig.AttackPhase.IDLE
var attack_timer: float = 0.0
var attack_id: int = 0
var ammo: int = 0
var _magazines: Dictionary = {}
var reload_timer: float = 0.0
var _buffer_timer: float = 0.0
var _empty_click_cooldown: float = 0.0

# --- 冲刺 ---
var dash_cooldown_left: float = 0.0
var dash_time_left: float = 0.0
var invuln_left: float = 0.0
var dash_direction: Vector2 = Vector2.RIGHT
var _dash_ended_at: float = -10.0

# --- 技能冷却 ---
var ability_cooldowns: Dictionary = {}

var status := StatusComponent.new()
# --- 自动瞄准 ---
var _auto_aim_target: Node2D = null
var _auto_aim_sticky_left: float = 0.0
# --- 运动标记 ---
var _motion_marks: Array[Dictionary] = []

var _hit_flash: float = 0.0
var _throttle_accumulator: float = 0.0
## 由外部注入的局内时钟起点。
var game_clock: float = 0.0

func _ready() -> void:
	add_to_group("player")
	collision_layer = GameConfig.bit(GameConfig.LAYER_PLAYER_BODY)
	collision_mask = GameConfig.mask([GameConfig.LAYER_WORLD, GameConfig.LAYER_COVER])
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_build_nodes()
	equip_weapon(0)
	GameEvents.run_started.connect(_on_run_started)

func _on_run_started(_seed_value: int) -> void:
	ability_cooldowns.clear()
	status.clear_all()
	state = State.NORMAL
	attack_phase = GameConfig.AttackPhase.IDLE
	attack_timer = 0.0
	dash_cooldown_left = 0.0
	dash_time_left = 0.0
	invuln_left = 0.0
	reload_timer = 0.0
	_buffer_timer = 0.0
	_motion_marks.clear()
	equip_weapon(0)

func _build_nodes() -> void:
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = BODY_RADIUS
	shape.shape = circle
	add_child(shape)
	status.name = "Status"
	add_child(status)

# --- 输入采集 ---

## 每物理帧由 GameFlow 调用一次，把设备输入转换成请求。
## 自检模式下 GameFlow 直接写字段，本方法会被跳过。
func poll_actions() -> void:
	if not accepts_device_input:
		return
	input_move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	input_aim_world = get_global_mouse_position()
	if Input.is_action_just_pressed("attack_primary"):
		input_attack_pressed = true
	input_attack_held = Input.is_action_pressed("attack_primary") and get_viewport().gui_get_hovered_control() == null
	if get_viewport().gui_get_hovered_control() != null:
		input_attack_pressed = false
	if Input.is_action_just_pressed("dash"):
		input_dash_pressed = true
	if Input.is_action_just_pressed("swap_weapon"):
		input_swap_pressed = true
	if Input.is_action_just_pressed("reload"):
		input_reload_pressed = true
	for slot in range(4):
		if Input.is_action_just_pressed("ability_%d" % (slot + 1)):
			input_ability_pressed = slot

# --- 武器 ---

func equip_weapon(index: int) -> void:
	if RunState.weapon_ids.is_empty():
		return
	if weapon != null:
		_magazines[weapon.id] = ammo
	weapon_index = wrapi(index, 0, RunState.weapon_ids.size())
	var weapon_id: String = RunState.weapon_ids[weapon_index]
	weapon = GameData.get_weapon(weapon_id)
	attack_phase = GameConfig.AttackPhase.IDLE
	attack_timer = 0.0
	ammo = int(_magazines.get(weapon.id, weapon.magazine)) if weapon != null else 0
	reload_timer = 0.0
	GameEvents.player_weapon_swapped.emit(weapon_id)
	queue_redraw()

func swap_weapon() -> void:
	equip_weapon(weapon_index + 1)

# --- 主循环 ---

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	tick_timers(delta)
	_update_aim()
	_update_attack(delta)
	_update_abilities()
	if state == State.DASH:
		_update_dash(delta)
	else:
		_update_movement(delta)
	move_and_slide()
	queue_redraw()

func tick_timers(delta: float) -> void:
	game_clock += delta
	RunState.modifiers.set_clock(game_clock)
	status.tick(delta)
	dash_cooldown_left = maxf(0.0, dash_cooldown_left - delta)
	invuln_left = maxf(0.0, invuln_left - delta)
	_buffer_timer = maxf(0.0, _buffer_timer - delta)
	_hit_flash = maxf(0.0, _hit_flash - delta)
	_empty_click_cooldown = maxf(0.0, _empty_click_cooldown - delta)
	# 词条每秒突发配额按局内时间重置。
	_throttle_accumulator += delta
	if _throttle_accumulator >= 1.0:
		_throttle_accumulator -= 1.0
		RunState.modifiers.reset_burst_window()
	for id in ability_cooldowns.keys():
		var left := float(ability_cooldowns[id]) - delta
		if left <= 0.0:
			ability_cooldowns.erase(id)
		else:
			ability_cooldowns[id] = left
	_track_motion_mark(delta)

func _update_aim() -> void:
	var previous := aim_direction
	if use_auto_aim:
		var target := find_auto_aim_target()
		if target != null:
			aim_direction = (target.global_position - global_position).normalized()
		elif input_move != Vector2.ZERO:
			aim_direction = input_move.normalized()
	else:
		var to_mouse := input_aim_world - global_position
		if to_mouse.length() > 4.0:
			aim_direction = to_mouse.normalized()
	if aim_direction != previous:
		aim_changed.emit(aim_direction)
	if state == State.DASH:
		return
	if input_move.length() > 0.1:
		body_facing = input_move.normalized()
	else:
		body_facing = aim_direction

## 自动瞄准：距离优先，保持目标黏性，避免逐帧切换。
func find_auto_aim_target() -> Node2D:
	if _auto_aim_target != null and is_instance_valid(_auto_aim_target) and _auto_aim_sticky_left > 0.0:
		if global_position.distance_to(_auto_aim_target.global_position) <= GameConfig.AUTOAIM_MAX_RANGE:
			return _auto_aim_target
	var best: Node2D = null
	var best_score := 0.0
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if not (candidate is Node2D) or not is_instance_valid(candidate):
			continue
		var node := candidate as Node2D
		var distance := global_position.distance_to(node.global_position)
		if distance > GameConfig.AUTOAIM_MAX_RANGE:
			continue
		var to_target := (node.global_position - global_position).normalized()
		var facing_bonus := 1.0 + maxf(0.0, aim_direction.dot(to_target)) * 0.6
		var score := facing_bonus * 1000.0 / maxf(40.0, distance)
		if score > best_score:
			best_score = score
			best = node
	if best != _auto_aim_target:
		_auto_aim_target = best
		_auto_aim_sticky_left = GameConfig.AUTOAIM_STICKY_SECONDS
	return _auto_aim_target

# --- 移动 ---

func _update_movement(delta: float) -> void:
	var target_speed := RunState.move_speed()
	if attack_phase != GameConfig.AttackPhase.IDLE:
		target_speed *= ATTACK_MOVE_SCALE
	if input_move.length() < 0.05:
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
	else:
		velocity = velocity.move_toward(input_move.normalized() * target_speed, ACCELERATION * delta)
	if input_dash_pressed:
		input_dash_pressed = false
		try_dash()
	if input_attack_pressed:
		input_attack_pressed = false
		request_attack()
	elif input_attack_held:
		request_attack()
	if input_swap_pressed:
		input_swap_pressed = false
		swap_weapon()
	if input_reload_pressed:
		input_reload_pressed = false
		start_reload()
	_auto_aim_sticky_left = maxf(0.0, _auto_aim_sticky_left - delta)

# --- 冲刺 ---

func try_dash() -> bool:
	if dash_cooldown_left > 0.0 or state == State.DEAD:
		return false
	var direction := input_move.normalized()
	if direction == Vector2.ZERO:
		direction = aim_direction
	dash_direction = direction
	dash_time_left = GameConfig.DASH_DURATION
	invuln_left = maxf(invuln_left, GameConfig.DASH_INVULN_SECONDS)
	dash_cooldown_left = RunState.dash_cooldown()
	state = State.DASH
	attack_phase = GameConfig.AttackPhase.IDLE
	attack_timer = 0.0
	velocity = dash_direction * (GameConfig.DASH_DISTANCE / GameConfig.DASH_DURATION)
	GameEvents.player_dashed.emit(dash_direction)
	state_changed.emit("dash")
	queue_redraw()
	return true

func _update_dash(delta: float) -> void:
	dash_time_left -= delta
	velocity = dash_direction * (GameConfig.DASH_DISTANCE / GameConfig.DASH_DURATION)
	if dash_time_left <= 0.0:
		state = State.NORMAL
		_dash_ended_at = game_clock
		state_changed.emit("normal")
		RunState.modifiers.fire_event(ModifierDef.Trigger.ON_DASH_END, {"player": self}, "dash_end")
		spawn_dash_zone(RunState.modifiers.resolve(0.0, "dash_zone"))

## 冲刺残影类词条：在冲刺结束位置生成短时伤害区域。
func spawn_dash_zone(damage: float) -> void:
	if damage <= 0.0:
		return
	zone_requested.emit({
		"position": global_position,
		"radius": 58.0,
		"damage_per_second": damage * 4.0,
		"duration": 0.9,
		"tick_interval": 0.25,
		"status": "",
		"color": Color(0.95, 0.95, 0.85, 0.35),
		"source": "dash_zone",
	})

# --- 攻击 ---

func request_attack() -> void:
	if state == State.DEAD or weapon == null:
		return
	if attack_phase == GameConfig.AttackPhase.RECOVERY and weapon.dash_cancel_recovery:
		if game_clock - _dash_ended_at <= DASH_CANCEL_WINDOW:
			attack_phase = GameConfig.AttackPhase.IDLE
			attack_timer = 0.0
	if attack_phase != GameConfig.AttackPhase.IDLE or reload_timer > 0.0:
		# 动作未结束时记录请求，最多 100 ms，避免玩家松手后角色继续行动。
		_buffer_timer = GameConfig.INPUT_BUFFER_SECONDS
		return
	_begin_attack()

func start_reload() -> void:
	if weapon == null or weapon.magazine <= 0:
		return
	if reload_timer > 0.0 or ammo >= weapon.magazine:
		return
	reload_timer = weapon.reload_time
	GameEvents.sfx_requested.emit("reload", global_position)

func _begin_attack() -> void:
	attack_id = GameFlow.next_attack_id()
	attack_phase = GameConfig.AttackPhase.WINDUP
	attack_timer = weapon.windup
	state = State.ATTACK
	GameEvents.attack_phase_changed.emit(self, attack_id, GameConfig.AttackPhase.WINDUP)
	state_changed.emit("attack")

func _update_attack(delta: float) -> void:
	if reload_timer > 0.0:
		reload_timer -= delta
		if reload_timer <= 0.0:
			reload_timer = 0.0
			ammo = weapon.magazine
	if attack_phase == GameConfig.AttackPhase.IDLE:
		var wants_attack := input_attack_held or _buffer_timer > 0.0
		if not wants_attack or reload_timer > 0.0:
			return
		_buffer_timer = 0.0
		_begin_attack()
		return
	attack_timer -= delta
	match attack_phase:
		GameConfig.AttackPhase.WINDUP:
			if attack_timer <= 0.0:
				var released := _release_attack()
				if not released:
					# 空仓时提前进入后摇，避免卡在前摇。
					attack_phase = GameConfig.AttackPhase.RECOVERY
					attack_timer = weapon.recovery * 0.5
					GameEvents.attack_phase_changed.emit(self, attack_id, GameConfig.AttackPhase.RECOVERY)
					return
				attack_phase = GameConfig.AttackPhase.ACTIVE
				attack_timer = weapon.active_window
				GameEvents.attack_phase_changed.emit(self, attack_id, GameConfig.AttackPhase.ACTIVE)
		GameConfig.AttackPhase.ACTIVE:
			if weapon.delivery == WeaponDef.Delivery.MELEE:
				_resolve_melee()
			if attack_timer <= 0.0:
				attack_phase = GameConfig.AttackPhase.RECOVERY
				attack_timer = weapon.recovery
				GameEvents.attack_phase_changed.emit(self, attack_id, GameConfig.AttackPhase.RECOVERY)
		GameConfig.AttackPhase.RECOVERY:
			if attack_timer <= 0.0:
				attack_phase = GameConfig.AttackPhase.IDLE
				attack_timer = 0.0
				if state == State.ATTACK:
					state = State.NORMAL
					state_changed.emit("normal")
				GameEvents.attack_phase_changed.emit(self, attack_id, GameConfig.AttackPhase.IDLE)

## 返回假表示本次攻击未能出手，通常是弹匣已空。
func _release_attack() -> bool:
	if weapon == null:
		return false
	if weapon.delivery == WeaponDef.Delivery.PROJECTILE and weapon.magazine > 0:
		if ammo < weapon.ammo_cost:
			if _empty_click_cooldown <= 0.0:
				_empty_click_cooldown = 0.4
				GameEvents.sfx_requested.emit("empty", global_position)
				start_reload()
			return false
		ammo -= weapon.ammo_cost
	RunState.modifiers.fire_event(ModifierDef.Trigger.ON_ATTACK, {"player": self}, "attack_release")
	if weapon.delivery == WeaponDef.Delivery.MELEE:
		return true
	var muzzle := global_position + aim_direction * (BODY_RADIUS + weapon.projectile_radius + 2.0)
	ProjectileFactory.volley(get_parent(), muzzle, aim_direction, weapon.projectiles_per_shot, weapon.spread_degrees, {
		"damage_group": "weapon_projectile",
		"attack_id": attack_id,
		"friendly": true,
		"base_damage": weapon.base_damage,
		"speed": weapon.projectile_speed,
		"lifetime": weapon.projectile_lifetime,
		"max_distance": weapon.projectile_max_distance,
		"radius": weapon.projectile_radius,
		"boomerang": weapon.boomerang,
		"return_speed_scale": weapon.return_speed_scale,
		"ricochet": weapon.ricochet,
		"ricochet_max": weapon.ricochet_max_bounces,
		"applies_status": weapon.applies_status,
		"status_layers": weapon.status_layers,
		"knockback": weapon.knockback,
		"crit_chance": weapon.crit_chance,
		"crit_multiplier": weapon.crit_multiplier,
		"heavy_impact": weapon.heavy_impact,
		"owner": self,
		"color": _weapon_color(),
	})
	GameEvents.sfx_requested.emit("weapon_fire", global_position)
	return true

func _resolve_melee() -> void:
	var hits := AttackResolver.arc_attack(
		self, attack_id, global_position, aim_direction,
		weapon.melee_radius, weapon.melee_arc_degrees, weapon.base_damage,
		"enemies", weapon.knockback, weapon.crit_chance, weapon.crit_multiplier,
		weapon.applies_status, weapon.status_layers, "weapon_melee"
	)
	if hits > 0:
		GameEvents.hitstop_requested.emit(GameConfig.HITSTOP_HEAVY_MS if weapon.heavy_impact else GameConfig.HITSTOP_LIGHT_MS)
		GameEvents.camera_shake_requested.emit(GameConfig.CAMERA_SHAKE_HEAVY if weapon.heavy_impact else GameConfig.CAMERA_SHAKE_LIGHT)

func _weapon_color() -> Color:
	if weapon == null:
		return Color(1, 1, 1)
	match weapon.id:
		"chalk_rapid":
			return Color(0.98, 0.96, 0.88)
		"basketball_boomerang":
			return Color(0.95, 0.62, 0.28)
		_:
			return Color(0.85, 0.9, 0.95)

# --- 主动技能 ---

func _update_abilities() -> void:
	if input_ability_pressed < 0:
		return
	var slot := input_ability_pressed
	input_ability_pressed = -1
	use_ability(slot)

func use_ability(slot: int) -> bool:
	if slot < 0 or slot >= RunState.ability_ids.size():
		return false
	var ability_id: String = RunState.ability_ids[slot]
	if ability_cooldowns.has(ability_id):
		return false
	var def := GameData.get_ability(ability_id)
	if def == null:
		return false
	ability_cooldowns[ability_id] = maxf(def.min_cooldown, def.cooldown)
	if def.grants_invulnerability:
		invuln_left = maxf(invuln_left, 0.25)
	if def.move_speed_bonus != 0.0:
		RunState.modifiers.add_temporary("move_speed", def.move_speed_bonus * RunState.BASE_MOVE_SPEED, def.duration, ability_id)
	_apply_ability(def, ability_id)
	GameEvents.player_ability_used.emit(ability_id, RunState.ability_ids.size())
	return true

func _apply_ability(def: AbilityDef, ability_id: String) -> void:
	match def.kind:
		AbilityDef.Kind.DASH_STRIKE:
			try_dash()
			AttackResolver.arc_attack(
				self, GameFlow.next_attack_id(), global_position, aim_direction,
				def.radius, 360.0, def.damage, "enemies", def.knockback, 0.05, 1.8, "", 0, "ability_dash_strike"
			)
			GameEvents.camera_shake_requested.emit(GameConfig.CAMERA_SHAKE_LIGHT)
		AbilityDef.Kind.DEPLOY_TURRET:
			deployable_requested.emit({
				"kind": "turret",
				"position": global_position + aim_direction * 34.0,
				"duration": def.duration,
				"radius": def.radius,
				"damage": maxf(4.0, def.damage),
				"fire_interval": 0.55,
				"color": def.color,
			})
		AbilityDef.Kind.DECOY:
			deployable_requested.emit({
				"kind": "decoy",
				"position": global_position,
				"duration": def.duration,
				"radius": def.radius,
				"health": 40.0,
				"color": def.color,
			})
		AbilityDef.Kind.FLASH:
			AttackResolver.arc_attack(
				self, GameFlow.next_attack_id(), global_position, aim_direction,
				def.radius, 360.0, def.damage, "enemies", def.knockback, 0.0, 1.0, "", 0, "ability_flash"
			)
			for candidate in get_tree().get_nodes_in_group("enemies"):
				if candidate is Enemy and global_position.distance_to(candidate.global_position) <= def.radius and AttackResolver.line_of_sight(self, global_position, candidate.global_position):
					if candidate.has_method("apply_status"):
						candidate.status.stun(def.stun_seconds)
			GameEvents.screen_flash_requested.emit(def.color, 0.18)
		AbilityDef.Kind.ORBITAL:
			zone_requested.emit({
				"position": global_position + aim_direction * def.radius,
				"radius": 46.0,
				"damage_per_second": def.damage * 3.0,
				"duration": def.duration,
				"tick_interval": 0.2,
				"status": "",
				"color": def.color,
				"source": "orbital",
			})
		AbilityDef.Kind.ZONE:
			zone_requested.emit({
				"position": global_position,
				"radius": def.radius,
				"damage_per_second": maxf(5.0, def.damage),
				"duration": def.duration,
				"tick_interval": def.tick_interval,
				"status": "inked",
				"color": def.color,
				"source": "ink_zone",
			})

func ability_cooldown_ratio(slot: int) -> float:
	if slot < 0 or slot >= RunState.ability_ids.size():
		return 0.0
	var ability_id: String = RunState.ability_ids[slot]
	var def := GameData.get_ability(ability_id)
	if def == null:
		return 0.0
	var left := float(ability_cooldowns.get(ability_id, 0.0))
	if left <= 0.0:
		return 0.0
	return clampf(left / maxf(0.001, def.cooldown), 0.0, 1.0)

func ability_ready(slot: int) -> bool:
	if slot < 0 or slot >= RunState.ability_ids.size():
		return false
	return not ability_cooldowns.has(RunState.ability_ids[slot])

# --- 运动标记 ---

## 篮球命中留下的运动标记，冲刺经过时缩短冲刺冷却。
func spawn_motion_mark() -> void:
	pass # 篮球命中位置由投射物传入。

func add_motion_mark(point: Vector2) -> void:
	_motion_marks.append({"position": point, "life": 6.0})

func _track_motion_mark(delta: float) -> void:
	if _motion_marks.is_empty():
		return
	var reward := RunState.modifiers.resolve(0.0, "dash_cooldown_on_mark")
	var kept: Array[Dictionary] = []
	var consumed := false
	for mark in _motion_marks:
		var position: Vector2 = mark["position"]
		if state == State.DASH and reward > 0.0 and global_position.distance_to(position) <= 26.0:
			dash_cooldown_left = maxf(0.0, dash_cooldown_left - reward)
			consumed = true
			continue
		mark["life"] = float(mark["life"]) - delta
		if float(mark["life"]) > 0.0:
			kept.append(mark)
	_motion_marks = kept
	if consumed:
		GameEvents.floating_text_requested.emit(global_position, "冷却缩短", Color(0.6, 0.9, 1.0))

# --- 受伤与无敌 ---

func is_invulnerable() -> bool:
	return invuln_left > 0.0 or state == State.DEAD

func apply_status(status_id: String, amount: int) -> void:
	status.add(status_id, amount, 0.0)

func combat_tags() -> PackedStringArray:
	var tags := status.tag_list()
	if state == State.DASH:
		tags.append("dashing")
	return tags

## 敌人攻击命中玩家时调用。返回实际扣除值。
func receive_damage(amount: int, _source: Node, _attack_id: int, is_crit: bool, _direction: Vector2, _knockback: float, _group: String) -> int:
	# 本局已结束时不再结算，避免失败界面上继续弹出提示。
	if not RunState.is_active:
		return 0
	if is_invulnerable():
		GameEvents.floating_text_requested.emit(global_position, "闪避", Color(0.7, 0.9, 1.0))
		return 0
	var dealt := RunState.apply_player_damage(float(amount))
	if dealt > 0:
		_hit_flash = 0.12
		invuln_left = maxf(invuln_left, 0.5)
		RunState.add_run_tag("受伤")
		GameEvents.camera_shake_requested.emit(GameConfig.CAMERA_SHAKE_HEAVY if is_crit else GameConfig.CAMERA_SHAKE_LIGHT)
		GameEvents.hitstop_requested.emit(GameConfig.HITSTOP_LIGHT_MS)
		queue_redraw()
	return dealt

func heal(amount: float) -> void:
	var gained := RunState.heal(amount)
	if gained > 0.0:
		GameEvents.floating_text_requested.emit(global_position - Vector2(0, 24), "+%d" % int(round(gained)), Color(0.5, 0.95, 0.6))

func grant_shield(amount: float, duration: float) -> void:
	RunState.add_shield(amount, duration)

# --- 表现 ---

func _draw() -> void:
	var body_color := Color(0.42, 0.72, 0.95)
	if _hit_flash > 0.0:
		body_color = Color(1.0, 0.55, 0.55)
	elif is_invulnerable():
		body_color = body_color.lerp(Color(1, 1, 1), 0.45)
	var bob := sin(game_clock * 15.0) * minf(2.0, velocity.length() / 120.0)
	draw_set_transform(Vector2(0, 13), 0.0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, 20, Color(0.02, 0.08, 0.09, 0.28))
	draw_set_transform(Vector2.ZERO)
	draw_rect(Rect2(-10, 4 + bob, 8, 12), Color("#223845"))
	draw_rect(Rect2(3, 4 - bob, 8, 12), Color("#223845"))
	draw_rect(Rect2(-11, 13 + bob, 10, 5), Color("#f1e8cc"))
	draw_rect(Rect2(3, 13 - bob, 10, 5), Color("#f1e8cc"))
	draw_style_box(_uniform_box(body_color), Rect2(-14, -11 + bob * 0.4, 28, 25))
	draw_line(Vector2(-11, -4), Vector2(11, -4), Color("#f0eee3"), 3)
	draw_line(Vector2(0, -9), Vector2(0, 10), Color("#294654"), 2)
	draw_circle(Vector2(0, -16 + bob * 0.4), 10, Color("#edc5a0"))
	draw_arc(Vector2(0, -17 + bob * 0.4), 10, PI, TAU, 12, Color("#263339"), 7)
	var eye := Vector2(0, -16) + aim_direction * 5.0
	draw_circle(eye + Vector2(-3, 0), 1.5, Color("#263339"))
	draw_circle(eye + Vector2(3, 0), 1.5, Color("#263339"))
	for mark in _motion_marks:
		draw_arc(to_local(mark["position"]), 18, 0, TAU, 20, Color("#edc173"), 2)
	var weapon_color := _weapon_color()
	if attack_phase == GameConfig.AttackPhase.ACTIVE and weapon != null and weapon.delivery == WeaponDef.Delivery.MELEE:
		var half := deg_to_rad(weapon.melee_arc_degrees) * 0.5
		draw_arc(Vector2.ZERO, weapon.melee_radius, aim_direction.angle() - half, aim_direction.angle() + half, 18, weapon_color, 4.0)
	else:
		draw_line(aim_direction * (BODY_RADIUS - 2.0), aim_direction * (BODY_RADIUS + 12.0), weapon_color, 3.0)
	if RunState.shield > 0.0:
		draw_arc(Vector2.ZERO, BODY_RADIUS + 7.0, 0.0, TAU, 24, Color(0.6, 0.9, 1.0, 0.75), 2.0)
	if status.is_stunned():
		draw_arc(Vector2.ZERO, BODY_RADIUS + 4.0, 0.0, TAU, 16, Color(1.0, 0.9, 0.4), 1.5)

func _uniform_box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color.darkened(0.12)
	box.border_color = Color("#21383e")
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	return box

func debug_line() -> String:
	return "状态 %d 武器 %s 弹药 %d/%d 冲刺 %.2f 无敌 %.2f 词条 %s" % [
		state,
		weapon.id if weapon != null else "无",
		ammo,
		weapon.magazine if weapon != null else 0,
		dash_cooldown_left,
		invuln_left,
		RunState.modifiers.describe(),
	]
