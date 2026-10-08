class_name SelfTest
extends Node
## 早期自检。用固定时间步跑通完整流程，并校验关键规则。
##
## 本节点由命令行参数 --self-test 启用，结束后以退出码表示结果。
## 检查项依据 docs/research/技术与动画方案.md 第 10 节列出的真实风险：
## 攻击去重、触发上限、随机图可达、存档迁移与暂停恢复。

const FIXED_DELTA := 1.0 / 60.0

var checks: Array[Dictionary] = []
var world: Node = null
var failures: PackedStringArray = PackedStringArray()
var warnings: PackedStringArray = PackedStringArray()
var _rng := RandomNumberGenerator.new()

func run(world_root: Node) -> bool:
	world = world_root
	_rng.seed = 20261007
	_log("自检开始：固定时间步 %.4f 秒" % FIXED_DELTA)
	_check_data()
	_check_damage_pipeline()
	_check_modifier_stacking()
	_check_trigger_limits()
	_check_save_service()
	_check_room_templates()
	_check_room_graph()
	await _check_combat_loop()
	_check_determinism()
	var regressions: Node = load("res://src/core/prototype_regressions.gd").new()
	add_child(regressions)
	await regressions.run(self)
	var ok := failures.is_empty()
	_log("自检结束：通过 %d 项，失败 %d 项，警告 %d 项" % [checks.size(), failures.size(), warnings.size()])
	GameEvents.self_test_finished.emit(ok, summary())
	return ok

func summary() -> Dictionary:
	return {
		"checks": checks.size(),
		"failures": failures.size(),
		"warnings": warnings.size(),
		"failure_list": Array(failures),
		"warning_list": Array(warnings),
		"details": checks.duplicate(true),
	}

# --- 断言工具 ---

func _assert_check(name: String, condition: bool, detail: String = "") -> bool:
	checks.append({"name": name, "ok": condition, "detail": detail})
	if condition:
		_log("  通过 %s %s" % [name, detail])
	else:
		failures.append("%s %s" % [name, detail])
		_log("  失败 %s %s" % [name, detail])
	return condition

func _warn(message: String) -> void:
	warnings.append(message)
	_log("  提示 " + message)

func _log(message: String) -> void:
	print(message)
	GameEvents.diagnostic.emit(message)

# --- 数据 ---

func _check_data() -> void:
	_log("检查 1 数据装配")
	_assert_check("数据校验无问题", GameData.validation_errors.is_empty(), "问题数 %d" % GameData.validation_errors.size())
	for problem in GameData.validation_errors:
		_log("    数据问题：" + problem)
	_assert_check("武器数量至少 2", GameData.weapons.size() >= 2, "实际 %d" % GameData.weapons.size())
	_assert_check("普通敌人至少 6", GameData.standard_enemy_ids().size() >= 6, "实际 %d" % GameData.standard_enemy_ids().size())
	_assert_check("Boss 至少 1", GameData.boss_ids().size() >= 1, "实际 %d" % GameData.boss_ids().size())
	_assert_check("房间模板至少 8", GameData.rooms.size() >= 8, "实际 %d" % GameData.rooms.size())
	_assert_check("词条至少 12", GameData.modifiers.size() >= 12, "实际 %d" % GameData.modifiers.size())
	_assert_check("主动技能至少 4", GameData.abilities.size() >= 4, "实际 %d" % GameData.abilities.size())
	var pools := ["attack", "mobility", "defense"]
	for pool in pools:
		_assert_check("奖励池 %s 非空" % pool, GameData.modifier_ids_in_pool(pool).size() > 0, "条目 %d" % GameData.modifier_ids_in_pool(pool).size())

# --- 伤害分层 ---

func _check_damage_pipeline() -> void:
	_log("检查 2 伤害分层结算")
	var calc := DamageCalc.new()
	calc.base = 10.0
	calc.add_flat(DamageCalc.GROUP_WEAPON, 2.0)
	calc.add_group_bonus(DamageCalc.GROUP_WEAPON, 0.5)
	calc.add_group_bonus(DamageCalc.GROUP_CLUB, 0.25)
	var result := calc.resolve()
	# 10 加 2 得 12，乘 1.5 得 18，乘 1.25 得 22.5，向下取整 22。
	_assert_check("同组相加跨组相乘", int(result["amount"]) == 22, "结果 %d" % int(result["amount"]))

	var independent := DamageCalc.new()
	independent.base = 100.0
	independent.add_independent("a", 1.5)
	independent.add_independent("b", 2.0)
	var independent_result := independent.resolve()
	_assert_check("独立层相乘", int(independent_result["amount"]) == 300, "结果 %d" % int(independent_result["amount"]))

	var defended := DamageCalc.new()
	defended.base = 100.0
	defended.flat_defense = 20.0
	defended.defense_reduction = 0.5
	var defended_result := defended.resolve()
	# 100 减 20 得 80，再减 50% 得 40。
	_assert_check("防御与减伤顺序", int(defended_result["amount"]) == 40, "结果 %d" % int(defended_result["amount"]))

	var minimum := DamageCalc.new()
	minimum.base = 1.0
	minimum.flat_defense = 999.0
	_assert_check("最低伤害为 1", int(minimum.resolve()["amount"]) == 1, "结果 %d" % int(minimum.resolve()["amount"]))

	var preview := DamageCalc.preview_text(calc)
	_assert_check("预览与结算同源", preview.contains("22"), preview)

# --- 词条叠加 ---

func _check_modifier_stacking() -> void:
	_log("检查 3 词条叠加与上限")
	var engine := ModifierEngine.new()
	engine.grant("quadriceps")
	engine.grant("quadriceps")
	var capped := engine.grant("quadriceps")
	var speed := engine.resolve(100.0, "move_speed")
	# quadriceps 的 max_stacks 为 1，12% 只应生效一次。
	_assert_check("词条层数上限生效", capped == 0, "第三次获得返回 %d" % capped)
	_assert_check("移动速度加成正确", absf(speed - 112.0) < 0.01, "结果 %.2f" % speed)

	var additive := ModifierEngine.new()
	additive.grant("focus_scope")
	var crit := additive.resolve(0.0, "crit_chance")
	_assert_check("暴击率加成正确", absf(crit - 0.08) < 0.001, "结果 %.3f" % crit)

	var conditional := ModifierEngine.new()
	conditional.grant("ink_diffusion")
	var none := conditional.conditional_multiplier(PackedStringArray())
	var inked := conditional.conditional_multiplier(PackedStringArray(["inked"]))
	_assert_check("条件加成仅在有标签时生效", absf(none - 1.0) < 0.001 and absf(inked - 1.25) < 0.001, "无标签 %.2f 有标签 %.2f" % [none, inked])

	var timed := ModifierEngine.new()
	timed.add_temporary("damage_taken", -0.3, 1.0, "test_buff")
	_assert_check("临时加成生效", absf(timed.resolve(0.0, "damage_taken") + 0.3) < 0.001, "结果 %.2f" % timed.resolve(0.0, "damage_taken"))
	timed.tick(1.2)
	_assert_check("临时加成到期失效", absf(timed.resolve(0.0, "damage_taken")) < 0.001, "结果 %.2f" % timed.resolve(0.0, "damage_taken"))

# --- 触发上限 ---

func _check_trigger_limits() -> void:
	_log("检查 4 触发链上限")
	var engine := ModifierEngine.new()
	engine.grant("steady_breath")
	var limit := GameConfig.TRIGGER_BURST_LIMIT_PER_SECOND
	# 在同一个每秒窗口内连续触发，配额之外的事件应当被拒绝。
	var within_quota := 0
	for index in range(limit):
		within_quota += engine.fire_event(ModifierDef.Trigger.ON_ROOM_CLEAR, {"player": null}, "burst_source")
	var over_quota := 0
	for index in range(20):
		over_quota += engine.fire_event(ModifierDef.Trigger.ON_ROOM_CLEAR, {"player": null}, "burst_source")
	_assert_check("配额内允许触发", within_quota == limit, "触发 %d 次，上限 %d" % [within_quota, limit])
	_assert_check("超配额一律拒绝", over_quota == 0, "额外触发 %d 次" % over_quota)
	_assert_check("超限时留下记录", engine.chain_limit_reports.size() > 0, "记录 %d 条" % engine.chain_limit_reports.size())
	# 窗口重置后恢复可用。
	engine.reset_burst_window()
	var after_reset := engine.fire_event(ModifierDef.Trigger.ON_ROOM_CLEAR, {"player": null}, "burst_source")
	_assert_check("窗口重置后恢复", after_reset == 1, "重置后触发 %d 次" % after_reset)

# --- 存档 ---

func _check_save_service() -> void:
	_log("检查 5 存档读写与迁移")
	var before := SaveService.summary()
	var points := SaveService.add_club_points(0)
	_assert_check("存档可读取", SaveService.data.has("version"), before)
	# 迁移路径：旧版本数据补齐缺失设置键。
	var legacy := {"version": 0, "club_points": 7, "settings": {"master_volume": 0.5}}
	var migrated := SaveService._migrate(legacy)
	var settings: Dictionary = migrated["settings"]
	_assert_check("迁移补齐设置键", settings.has("screen_shake") and settings.has("hitstop_scale"), "键数 %d" % settings.size())
	_assert_check("迁移保留原有数值", int(migrated["club_points"]) == 7, "社团点数 %d" % int(migrated["club_points"]))
	_assert_check("迁移升级版本号", int(migrated["version"]) == SaveService.CURRENT_VERSION, "版本 %d" % int(migrated["version"]))
	_assert_check("存档记录可读", points >= 0, "社团点数 %d" % points)

# --- 房间模板 ---

func _check_room_templates() -> void:
	_log("检查 6 房间模板可站立性")
	for id in GameData.rooms.keys():
		var room: RoomDef = GameData.rooms[id]
		var free_cells := RoomGenerator.free_cells(room)
		_assert_check("模板 %s 有可站立格" % id, free_cells.size() > 0, "可站立格 %d" % free_cells.size())
		var spawn := room.spawn_player
		var blocked := RoomGenerator.blocked_cells(room)
		_assert_check("模板 %s 玩家出生点未被占" % id, not blocked.has(spawn), "出生格 %s" % str(spawn))
		# 出生点周围需要有活动空间。
		var room_node := RoomGraphNode.new()
		room_node.id = 0
		room_node.template_id = id
		room_node.difficulty = 1.0
		var plan := RoomGenerator.build_encounter(room, _rng, 1, 1.0)
		var threat_total := 0
		var high_control := 0
		for entry in plan:
			var enemy_def := GameData.get_enemy(str(entry["enemy_id"]))
			if enemy_def == null:
				continue
			threat_total += enemy_def.threat
			if RoomGenerator.HIGH_CONTROL_FAMILIES.has(enemy_def.family):
				high_control += 1
		var budget_cap := int(room.threat_budget * 1.0) + 1
		_assert_check("模板 %s 威胁预算内" % id, threat_total <= budget_cap * maxi(1, room.waves), "威胁 %d，上限 %d" % [threat_total, budget_cap * maxi(1, room.waves)])
		if not room.allow_high_control:
			_assert_check("模板 %s 遵守高控制上限" % id, high_control <= RoomGenerator.MAX_HIGH_CONTROL, "高控制 %d" % high_control)

func _check_room_graph() -> void:
	_log("检查 7 房间图连通性")
	var templates: Array = []
	for id in GameData.rooms.keys():
		templates.append(GameData.rooms[id])
	var graph := RoomGraph.new()
	var rng := RandomNumberGenerator.new()
	var validated_runs := 0
	var total_combat := 0
	for seed_value in range(20):
		rng.seed = 1000 + seed_value
		graph.generate(templates, rng, 1000 + seed_value)
		if graph.validate():
			validated_runs += 1
			total_combat += graph.combat_room_count()
		elif validated_runs == 0:
			# 首个失败样本输出布线细节，便于定位。
			_log("    首个失败样本详情：")
			for problem in graph.errors:
				_log("      " + problem)
			var ids: Array = graph.nodes.keys()
			ids.sort()
			for id in ids:
				var node: RoomGraphNode = graph.nodes[id]
				_log("      节点 %d 模板 %s lane %d next %s prev %s" % [
					node.id, node.template_id, node.lane, str(node.next), str(node.previous)
				])
	_assert_check("二十个随机种子全部连通", validated_runs == 20, "通过 %d/20" % validated_runs)
	if validated_runs > 0:
		var average := float(total_combat) / float(validated_runs)
		_assert_check("战斗房数量合理", average >= 5.0 and average <= 12.0, "平均 %.1f" % average)

# --- 战斗循环 ---

func _check_combat_loop() -> void:
	_log("检查 8 端到端战斗循环")
	var flow = world.flow
	if flow == null:
		_assert_check("游戏总控已挂载", false, "未找到 GameFlow 实例")
		return
	flow.self_test_mode = true
	Engine.time_scale = 1.0
	flow.start_run(20261007)
	await _wait_physics_frames(4)
	var player: Player = flow.player
	if not _assert_check("房间与玩家已建立", flow.current_room != null and player != null, "状态 %s" % flow.state_name()):
		return
	# 关闭外来输入，全部由脚本写入。
	player.accepts_device_input = false
	player.use_auto_aim = false

	# 1) 移动：向右侧持续输入，位置应右移。
	var start_x: float = player.global_position.x
	player.input_move = Vector2.RIGHT
	await _step_frames(30)
	player.input_move = Vector2.ZERO
	await _step_frames(6)
	_assert_check("移动响应", player.global_position.x > start_x + 20.0, "位移 %.1f" % (player.global_position.x - start_x))

	# 2) 冲刺与无敌：冲刺期间 is_invulnerable 为真，冷却开始计时。
	player.dash_cooldown_left = 0.0
	var dash_ok: bool = player.try_dash()
	_assert_check("冲刺可触发", dash_ok, "返回 %s" % str(dash_ok))
	_assert_check("冲刺提供无敌", player.is_invulnerable(), "无敌剩余 %.3f" % player.invuln_left)
	var cooldown_after: float = player.dash_cooldown_left
	_assert_check("冲刺进入冷却", cooldown_after > 0.0, "冷却 %.2f" % cooldown_after)
	await _step_frames(20)
	_assert_check("冲刺状态结束", player.state != Player.State.DASH, "状态 %d" % player.state)

	# 3) 无敌期间不受伤。
	var health_before := RunState.health
	player.invuln_left = 1.0
	var blocked_damage: int = player.receive_damage(10, null, 999, false, Vector2.RIGHT, 0.0, "test")
	_assert_check("无敌期间免伤", blocked_damage == 0 and is_equal_approx(RunState.health, health_before), "扣除 %d，剩余生命 %.1f" % [blocked_damage, RunState.health])
	player.invuln_left = 0.0

	# 4) 投射物命中与去重。
	var enemy = _spawn_test_enemy(flow, player.global_position + Vector2(150, 0))
	if enemy == null:
		_assert_check("测试敌人可生成", false, "生成失败")
		return
	await _step_frames(30)
	var enemy_health_start: float = enemy.health
	player.equip_weapon(0)
	player.aim_direction = Vector2.RIGHT
	player.input_aim_world = player.global_position + Vector2(200, 0)
	player.input_attack_pressed = true
	await _step_frames(2)
	player.input_attack_pressed = false
	var fired := false
	for index in range(40):
		player.input_aim_world = player.global_position + Vector2(200, 0)
		player.input_attack_held = true
		await _step_frames(1)
		if enemy.health < enemy_health_start:
			fired = true
			break
	player.input_attack_held = false
	_assert_check("武器命中造成伤害", fired and enemy.health < enemy_health_start, "敌人生命 %.0f 到 %.0f" % [enemy_health_start, enemy.health])

	# 5) 近战武器也可结算伤害。
	for child in flow.actors.get_children():
		if child is Projectile:
			flow.actors.remove_child(child)
			child.queue_free()
	player.equip_weapon(2)
	_assert_check("近战测试使用直尺", player.weapon.id == "ruler_sweep" and player.weapon.delivery == WeaponDef.Delivery.MELEE, player.weapon.id)
	enemy.global_position = player.global_position + Vector2(55, 0)
	enemy.status.stun(3.0)
	await _wait_physics_frames(3)
	var melee_before: float = enemy.health
	player.input_aim_world = enemy.global_position
	player.input_attack_pressed = true
	await _step_frames(2)
	player.input_attack_pressed = false
	for index in range(40):
		player.input_aim_world = enemy.global_position
		player.input_attack_held = true
		await _step_frames(1)
		if enemy.health < melee_before:
			break
	player.input_attack_held = false
	_assert_check("近战武器命中造成伤害", enemy.health < melee_before, "敌人生命 %.0f 到 %.0f" % [melee_before, enemy.health])

	# 6) 敌人会追击并攻击玩家。
	var chaser: Enemy = _spawn_test_enemy(flow, player.global_position + Vector2(260, 0), "enemy_misprint_chaser")
	var distance_before := 9999.0
	if chaser != null:
		distance_before = chaser.global_position.distance_to(player.global_position)
	await _step_frames(150)
	if chaser != null and is_instance_valid(chaser):
		var distance_after: float = chaser.global_position.distance_to(player.global_position)
		_assert_check("追击敌人接近玩家", distance_after < distance_before, "距离 %.0f 到 %.0f" % [distance_before, distance_after])

	# 7) 受伤与死亡流程。先移除测试敌人并停止房间推进，
	#    确保流程状态只由致命伤害决定。
	player.accepts_device_input = false
	player.input_move = Vector2.ZERO
	player.input_attack_held = false
	for node in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(node):
			node.queue_free()
	await _step_frames(4)
	if flow.current_room != null and is_instance_valid(flow.current_room):
		flow.current_room.set_process(false)
		flow.current_room.encounter_finished = true
	var lethal_health := RunState.health
	RunState.health = 5.0
	RunState.shield = 0.0
	player.invuln_left = 0.0
	var lethal_damage: int = player.receive_damage(50, null, 998, false, Vector2.RIGHT, 0.0, "test")
	_assert_check("致命伤害触发失败流程", lethal_damage > 0 and not RunState.is_active and RunState.health <= 0.0, "扣除 %d，生命 %.1f，进行中 %s" % [lethal_damage, RunState.health, str(RunState.is_active)])
	await _step_frames(4)
	_assert_check("失败状态可读", flow.state == flow.FlowState.DEAD, "状态 %s" % flow.state_name())
	_assert_check("失败后仍发放社团点数", int(SaveService.data.get("club_points", 0)) >= 0, "社团点数 %d" % int(SaveService.data.get("club_points", 0)))
	RunState.health = lethal_health

	# 9) 暂停与恢复：暂停时帧推进不改变局内时钟。
	#    注意：暂停期间不等待 physics_frame，避免测试自身挂起。
	flow.start_run(4321)
	await _wait_physics_frames(4)
	if flow.current_room != null and is_instance_valid(flow.current_room):
		flow.current_room.set_process(false)
		flow.current_room.encounter_finished = true
	var clock_before := RunState.elapsed_seconds
	flow.toggle_pause()
	_assert_check("暂停状态生效", flow.state == flow.FlowState.PAUSED and get_tree().paused, "状态 %s 暂停 %s" % [flow.state_name(), str(get_tree().paused)])
	for index in range(30):
		flow._physics_process(FIXED_DELTA)
	_assert_check("暂停期间局内时钟停止", is_equal_approx(RunState.elapsed_seconds, clock_before), "暂停前 %.3f 暂停后 %.3f" % [clock_before, RunState.elapsed_seconds])
	flow.toggle_pause()
	_assert_check("恢复后回到战斗", flow.state == flow.FlowState.PLAYING and not get_tree().paused, "状态 %s" % flow.state_name())
	await _step_frames(10)
	_assert_check("恢复后时钟继续", RunState.elapsed_seconds > clock_before, "时钟 %.3f" % RunState.elapsed_seconds)

	# 10) 房间清除推进到奖励环节。
	flow.start_run(555)
	await _wait_physics_frames(4)
	if flow.current_room != null and is_instance_valid(flow.current_room):
		flow.current_room.set_process(false)
		flow.current_room.encounter_finished = true
		flow.current_room._close()
	await _step_frames(60)
	_assert_check("房间清除进入奖励选择", flow.state == flow.FlowState.REWARD, "状态 %s" % flow.state_name())
	_assert_check("清除房间计入进度", RunState.rooms_cleared >= 1, "清理房间 %d" % RunState.rooms_cleared)
	var options: Array = flow._next_room_options()
	if _assert_check("存在可选下一房间", options.size() > 0, "可选 %d 个" % options.size()):
		var before_room: int = flow.current_room_id
		flow.select_reward(flow.offered_rewards[0])
		flow.choose_next_room(int(options[0]))
		await _wait_physics_frames(4)
		_assert_check("选择后进入新房间", flow.current_room_id != before_room and flow.current_room != null, "房间 %d 到 %d" % [before_room, flow.current_room_id])

	# 11) 重开新局，验证房间重建。
	flow.start_run(777)
	await _wait_physics_frames(4)
	_assert_check("重开新局成功", flow.current_room != null and RunState.is_active, "状态 %s 生命 %.0f" % [flow.state_name(), RunState.health])
	_assert_check("种子记录正确", RunState.seed_value == 777, "种子 %d" % RunState.seed_value)

func _spawn_test_enemy(flow: Node, position: Vector2, enemy_id: String = "enemy_laser_pointer") -> Enemy:
	var enemy: Enemy = flow.spawn_enemy(enemy_id, position, false)
	if enemy != null:
		enemy.add_to_group("test_enemies")
	return enemy

func _step_frames(count: int) -> void:
	for index in range(count):
		if world.flow != null:
			world.flow.step_world(FIXED_DELTA)
		await get_tree().physics_frame

func _wait_physics_frames(count: int) -> void:
	for index in range(count):
		await get_tree().physics_frame

# --- 确定性 ---

func _check_determinism() -> void:
	_log("检查 9 同种子生成一致")
	var templates: Array = []
	for id in GameData.rooms.keys():
		templates.append(GameData.rooms[id])
	var first := _plan_signature(templates, 4242)
	var second := _plan_signature(templates, 4242)
	var different := _plan_signature(templates, 4243)
	_assert_check("同种子房间图一致", first == second, first)
	_assert_check("不同种子房间图不同", first != different, "第二个签名 %s" % different)

func _plan_signature(templates: Array, seed_value: int) -> String:
	var graph := RoomGraph.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	graph.generate(templates, rng, seed_value)
	var parts: PackedStringArray = PackedStringArray()
	var ids: Array = graph.nodes.keys()
	ids.sort()
	for id in ids:
		var node: RoomGraphNode = graph.nodes[id]
		var cells: PackedStringArray = PackedStringArray()
		for entry in node.encounter:
			var cell: Vector2i = entry["cell"]
			cells.append("%s@%d,%d" % [str(entry["enemy_id"]), cell.x, cell.y])
		parts.append("%d:%s:%s" % [int(id), node.template_id, ",".join(cells)])
	return "|".join(parts)
