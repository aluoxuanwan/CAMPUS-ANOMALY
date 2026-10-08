class_name Boss
extends Enemy
## 试卷巨像。教学楼区域 Boss，三个阶段循环执行。
##
## 依据 docs/research/玩法机制与校园设计.md 第 4 节：
## 每个 Boss 围绕一个主要问题设计，再用第二阶段组合已有规则；
## 大攻击通过动作、声音和地面标记预告；阶段切换留出短恢复；
## 玩家死亡后能够指出自己忽略了哪一项提示。

## 阶段切换时发出，供房间规则与 HUD 使用。
signal phase_switched(phase_index: int, phase_name: String)

enum Phase { STRAIGHT, FAN, BELL_SHIFT }

const PHASE_NAMES := ["直线试卷", "扇形组合", "铃声掩体转换"]

var phase: int = Phase.STRAIGHT
var phase_index: int = 0
## 阶段切换期间的无敌与恢复。
var transition_left: float = 0.0
var _shots_in_phase: int = 0
var _boss_room = null

func configure_boss(enemy_def: EnemyDef, room = null) -> void:
	configure(enemy_def, false)
	_boss_room = room
	phase = Phase.STRAIGHT
	phase_index = 0
	transition_left = GameConfig.BOSS_PHASE_TRANSITION_SECONDS

func is_invulnerable_phase() -> bool:
	return transition_left > 0.0

func _physics_process(delta: float) -> void:
	if transition_left > 0.0:
		transition_left = maxf(0.0, transition_left - delta)
		# 阶段切换期间保持静止并显示提示环。
		velocity = velocity.move_toward(Vector2.ZERO, 2000.0 * delta)
		status.tick(delta)
		move_and_slide()
		queue_redraw()
		if transition_left <= 0.0:
			_on_transition_end()
		return
	super._physics_process(delta)

func _on_transition_end() -> void:
	phase_switched.emit(phase_index, PHASE_NAMES[phase_index])
	GameEvents.sfx_requested.emit("boss_phase", global_position)

## Boss 不使用普通敌人的攻击条件，改为按阶段节奏出手。
func _in_attack_condition() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return true

func _pursuit_velocity(delta: float) -> Vector2:
	if target == null or not is_instance_valid(target):
		return Vector2.ZERO
	var to_target := target.global_position - global_position
	var distance := to_target.length()
	var direction := Vector2.ZERO
	if distance > def.preferred_distance:
		direction = to_target.normalized()
	elif distance < def.preferred_distance * 0.6:
		direction = -to_target.normalized()
	return direction * def.move_speed

func _perform_attack() -> void:
	attack_id = GameFlow.next_attack_id()
	_shots_in_phase += 1
	match phase:
		Phase.STRAIGHT:
			_attack_straight()
		Phase.FAN:
			_attack_fan()
		Phase.BELL_SHIFT:
			_attack_bell_shift()
	GameEvents.sfx_requested.emit("boss_attack", global_position)
	# 每个阶段出手若干次后进入下一阶段。
	if _shots_in_phase >= _shots_before_transition():
		_advance_phase()

func _shots_before_transition() -> int:
	if phase == Phase.BELL_SHIFT:
		return 1
	return 3

func _advance_phase() -> void:
	_shots_in_phase = 0
	phase_index = (phase_index + 1) % 3
	phase = phase_index as Phase
	transition_left = GameConfig.BOSS_PHASE_TRANSITION_SECONDS
	state = EnemyState.SEEKING
	GameEvents.hitstop_requested.emit(GameConfig.HITSTOP_LIGHT_MS)

func _attack_straight() -> void:
	if target == null or not is_instance_valid(target):
		return
	var direction := (target.global_position - global_position).normalized()
	# 直线攻击有清晰轨迹，玩家可以侧向闪避。
	for index in range(3):
		var delay_offset := float(index) * 10.0
		ProjectileFactory.volley(self.get_parent(), global_position + direction * (def.body_radius + 8.0 + delay_offset), direction, 1, 0.0, _projectile_config(1.0))
	GameEvents.camera_shake_requested.emit(GameConfig.CAMERA_SHAKE_LIGHT)

func _attack_fan() -> void:
	if target == null or not is_instance_valid(target):
		return
	var direction := (target.global_position - global_position).normalized()
	var count := 7
	ProjectileFactory.fan(self.get_parent(), global_position + direction * (def.body_radius + 8.0), direction, count, 78.0, _projectile_config(1.0))
	GameEvents.camera_shake_requested.emit(GameConfig.CAMERA_SHAKE_HEAVY)

## 铃声到来时转换掩体，Boss 在这段时间不追加攻击。
func _attack_bell_shift() -> void:
	if _boss_room != null and is_instance_valid(_boss_room) and _boss_room.has_method("force_bell_shift"):
		_boss_room.force_bell_shift()
	GameEvents.sfx_requested.emit("bell", global_position)

func _projectile_config(speed_scale: float) -> Dictionary:
	return {
		"damage_group": "boss_projectile",
		"attack_id": attack_id,
		"friendly": false,
		"base_damage": def.attack_damage,
		"speed": 330.0 * speed_scale,
		"lifetime": 3.0,
		"max_distance": 700.0,
		"radius": 9.0,
		"knockback": 120.0,
		"crit_chance": 0.0,
		"crit_multiplier": 1.0,
		"owner": self,
		"color": Color(0.95, 0.92, 0.75),
	}

func receive_damage(amount: int, source: Node, incoming_attack_id: int, is_crit: bool, direction: Vector2, knockback: float, group: String) -> int:
	# 阶段切换期间无敌，避免玩家在无法预判的窗口内被反打。
	if is_invulnerable_phase():
		GameEvents.floating_text_requested.emit(global_position + Vector2(0, -def.body_radius - 10.0), "免疫", Color(0.8, 0.8, 0.9))
		return 0
	return super.receive_damage(amount, source, incoming_attack_id, is_crit, direction, knockback, group)

func current_phase_name() -> String:
	return PHASE_NAMES[phase_index]

func _draw() -> void:
	if def == null:
		return
	var radius := def.body_radius
	var body := def.color
	if _flash > 0.0:
		body = Color(1, 1, 1)
	if transition_left > 0.0:
		var total := maxf(0.001, GameConfig.BOSS_PHASE_TRANSITION_SECONDS)
		var progress := 1.0 - clampf(transition_left / total, 0.0, 1.0)
		draw_arc(Vector2.ZERO, radius + 16.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 32, Color(1.0, 0.4, 0.4), 4.0)
	# 主体用堆叠的纸张轮廓表示。
	draw_rect(Rect2(-radius, -radius * 0.75, radius * 2.0, radius * 1.5), body.darkened(0.25))
	draw_rect(Rect2(-radius * 0.8, -radius * 0.55, radius * 1.6, radius * 1.1), body, false, 3.0)
	for index in range(4):
		var line_y := -radius * 0.35 + float(index) * radius * 0.28
		draw_line(Vector2(-radius * 0.6, line_y), Vector2(radius * 0.6, line_y), Color(0.4, 0.35, 0.3, 0.7), 2.0)
	# 出手前摇提示。
	if state == EnemyState.WINDUP:
		var total_windup := maxf(0.001, def.attack_windup)
		var progress := 1.0 - clampf(state_timer / total_windup, 0.0, 1.0)
		draw_arc(Vector2.ZERO, radius + 8.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 32, Color(1.0, 0.3, 0.3), 5.0)
	if status.is_stunned():
		draw_arc(Vector2.ZERO, radius + 22.0, 0.0, TAU, 24, Color(1.0, 0.9, 0.4), 3.0)
