extends Node
## 回归用真实场景和碰撞体检查已发现故障。
var tester: SelfTest

class HealProbe extends Node:
	var calls := 0
	func heal(_value: float) -> void:
		calls += 1

func check(title: String, result: bool, detail: String = "") -> void:
	tester._assert_check(title, result, detail)

func run(owner: SelfTest) -> void:
	tester = owner
	process_mode = Node.PROCESS_MODE_ALWAYS
	var flow := GameFlow
	flow.self_test_mode = true
	tester._log("检查 10 原型故障回归")
	# 真正执行回血效果的次数，不能通过空上下文得到成功计数。
	var receiver := HealProbe.new()
	add_child(receiver)
	var engine := ModifierEngine.new()
	engine.grant("steady_breath")
	for index in range(44):
		engine.fire_event(ModifierDef.Trigger.ON_ROOM_CLEAR, {"player": receiver}, "heal_regression")
	check("触发配额限制实际回血次数", receiver.calls == 24, str(receiver.calls))
	engine.reset_burst_window()
	engine.fire_event(ModifierDef.Trigger.ON_ROOM_CLEAR, {"player": receiver}, "heal_regression")
	check("重置配额后实际回血恢复", receiver.calls == 25)
	# 文件隔离和实际读写。
	check("验证使用独立存档", SaveService.SAVE_PATH.begins_with("user://qa/"), SaveService.SAVE_PATH)
	var saved_data := SaveService.data.duplicate(true)
	SaveService.data["club_points"] = 123
	check("存档写入成功", SaveService.save())
	SaveService.data.clear()
	SaveService.load_or_create()
	check("存档回读保留数据", int(SaveService.data.get("club_points", 0)) == 123)
	SaveService.save() # 让备份也保存已知有效值。
	var file := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	SaveService.load_or_create()
	check("损坏主存档恢复有效备份", int(SaveService.data.get("club_points", 0)) == 123)
	check("恢复后有效备份仍可读取", not SaveService._read_json(SaveService.BACKUP_PATH).is_empty())
	SaveService.data = saved_data
	SaveService.save()
	flow.start_run(101)
	await tester._wait_physics_frames(3)
	var player: Player = flow.player
	player.accepts_device_input = false
	check("玩家只由总控推进物理", not player.is_physics_processing())
	var clock := player.game_clock
	await tester._step_frames(60)
	check("六十帧只推进一秒玩家计时", absf(player.game_clock - clock - 1.0) < 0.002, "%.4f" % (player.game_clock - clock))
	check("房间实际生成敌人", flow.current_room.enemies.size() > 0, str(flow.current_room.enemies.size()))
	check("有敌人时房间保持开放", not flow.current_room.is_closed)
	# 隔离战斗场地中的生成与角色行动。
	flow.current_room.grace_left = 1000.0
	flow.current_room.encounter_finished = true
	flow.current_room.current_wave = -1
	for enemy in flow.current_room.enemies:
		flow.actors.remove_child(enemy)
		enemy.queue_free()
	flow.current_room.enemies.clear()
	# 空旷角落进行真实近战查询。
	player.global_position = Vector2(160, 160)
	player.velocity = Vector2.ZERO
	var target := flow.spawn_enemy("enemy_misprint_chaser", Vector2(210, 160), false)
	target.health = 200.0
	target.status.stun(100.0)
	player.equip_weapon(2)
	player.aim_direction = Vector2.RIGHT
	player.attack_id = flow.next_attack_id()
	await tester._wait_physics_frames(3)
	var before := target.health
	player._resolve_melee()
	var after := target.health
	check("直尺扇形造成真实近战伤害", before - after >= 21.0, str(before - after))
	player._resolve_melee()
	check("同一次扇形攻击不重复扣血", is_equal_approx(after, target.health))
	# 敌人近战必须能击中真实玩家。
	target.status.clear_all()
	target.global_position = Vector2(188, 160)
	await tester._wait_physics_frames(2)
	RunState.health = 100.0
	player.invuln_left = 0.0
	target.attack_id = flow.next_attack_id()
	target._do_melee_strike(10.0)
	check("敌人近战可伤害玩家", RunState.health < 100.0)
	# 敌方投射物不继承玩家暴击或伤害加成。
	RunState.health = 100.0
	player.invuln_left = 0.0
	RunState.modifiers.add_temporary("damage", 5.0, 10.0, "regression")
	RunState.modifiers.add_temporary("crit_chance", 1.0, 10.0, "regression")
	var hostile := Projectile.new()
	hostile.setup({"friendly": false, "base_damage": 10.0, "owner": target, "attack_id": flow.next_attack_id()})
	flow.effects.add_child(hostile)
	hostile._apply_hit(player, player.global_position)
	check("敌方投射物不继承玩家加成", is_equal_approx(RunState.health, 90.0), str(RunState.health))
	hostile.queue_free()
	RunState.modifiers.clear()
	RunState.grant_modifier("painkiller")
	RunState.health = 50.0
	RunState.note_kill()
	check("击杀回血词条实际生效", is_equal_approx(RunState.health, 53.0))
	RunState.grant_modifier("steady_breath")
	RunState.note_room_cleared()
	check("清房回血词条实际生效", is_equal_approx(RunState.health, 59.0))
	RunState.modifiers.clear()
	RunState.grant_modifier("lab_safety")
	RunState.modifiers.fire_event(ModifierDef.Trigger.ON_DAMAGED, {"player": player}, "reactive_test")
	check("临时防御减少受到的伤害", is_equal_approx(RunState.damage_taken_multiplier(), 0.8))
	RunState.tick_timers(2.1)
	check("临时防御到期恢复正常", is_equal_approx(RunState.damage_taken_multiplier(), 1.0))
	target.status.stun(0.2)
	target.status.tick(0.21)
	check("眩晕到期解除", not target.status.is_stunned())
	player.equip_weapon(0)
	player.ammo = 3
	player.equip_weapon(1)
	player.equip_weapon(0)
	check("切换武器保留弹匣", player.ammo == 3)
	# 真正对墙体做高速扫掠，反弹后应留在墙内一侧。
	var shot := Projectile.new()
	shot.setup({"owner": player, "direction": Vector2.LEFT, "speed": 3000.0, "ricochet": true, "attack_id": flow.next_attack_id(), "max_distance": 2000.0, "lifetime": 2.0})
	shot.global_position = Vector2(60, 100)
	flow.actors.add_child(shot)
	shot.set_physics_process(false)
	await tester._wait_physics_frames(2)
	shot._physics_process(0.1)
	check("高速扫掠识别墙体反弹", shot.bounce_count == 1)
	check("反弹位置留在房间内", shot.global_position.x >= 48.0, str(shot.global_position))
	shot.queue_free()
	var cover := flow.current_room.covers[0]
	var route := flow.current_room.navigation_direction(cover.position - Vector2(48, 0), cover.position + Vector2(48, 0))
	check("寻路绕开中间课桌", absf(route.y) > 0.1, str(route))
	# 铃声、技能与暂停。
	var phase := flow.current_room.bell_phase
	flow.current_room.force_bell_shift()
	check("铃声阶段切换", flow.current_room.bell_phase != phase)
	check("课间移动倍率生效", flow.current_room.enemy_speed_scale > 1.0)
	player.use_ability(1)
	var left := float(player.ability_cooldowns.get("club_robotics_turret", 0.0))
	flow.toggle_pause()
	await tester._wait_physics_frames(10)
	check("暂停时技能冷却保持", is_equal_approx(float(player.ability_cooldowns.get("club_robotics_turret", 0.0)), left))
	flow.toggle_pause()
	# 奖励不允许跳过或重复选取。
	flow.current_room._close()
	flow._process_room_clear(1.0)
	var old_room := flow.current_room_id
	var next_room: int = flow._next_room_options()[0]
	flow.choose_next_room(next_room)
	check("未选奖励不能进入下一房", flow.current_room_id == old_room)
	check("无效奖励被拒绝", not flow.select_reward("unknown"))
	check("有效奖励可领取", flow.select_reward(flow.offered_rewards[0]))
	check("奖励不能重复领取", not flow.select_reward(flow.offered_rewards[0]))
	flow.ui_layer.close_modal()
	flow.choose_next_room(next_room)
	await tester._wait_physics_frames(3)
	check("选奖励后可以进房", flow.current_room_id == next_room and not get_tree().paused)
	check("换房清空旧召唤物和区域", flow.effects.get_child_count() == 0)
	check("换房清空旧敌人和子弹", flow.actors.get_child_count() == 2)
	# 以伤害注入验证完整六节路线。此项验证流程，不代表人工通关。
	flow.start_run(303)
	await tester._wait_physics_frames(2)
	var cleared := 0
	while cleared < 6 and flow.state == GameFlow.FlowState.PLAYING:
		flow.current_room.tick(1.0)
		# 清理所有波次，不依靠空房直接触发。
		for wave in range(5):
			for enemy in flow.current_room.enemies.duplicate():
				if is_instance_valid(enemy):
					if enemy is Boss:
						enemy.transition_left = 0.0
					enemy.receive_damage(99999, flow.player, flow.next_attack_id(), false, Vector2.RIGHT, 0.0, "qa_flow")
			if flow.current_room.is_closed:
				break
			flow.current_room.tick(1.0)
		cleared += 1
		if flow.state == GameFlow.FlowState.VICTORY:
			break
		flow._process_room_clear(1.0)
		if flow.state != GameFlow.FlowState.REWARD:
			break
		flow.select_reward(flow.offered_rewards[0])
		flow.ui_layer.close_modal()
		flow.choose_next_room(flow._next_room_options()[0])
		await tester._wait_physics_frames(2)
	check("六节路线实际生成并清理波次", cleared == 6, str(cleared))
	check("Boss 击败后进入通关", flow.state == GameFlow.FlowState.VICTORY, flow.state_name())
	var records: Dictionary = SaveService.data["records"]
	var runs := int(records["total_runs"])
	check("同一局结算不会重复发放", RunState.settle_rewards(true) == 0 and int(SaveService.data["records"]["total_runs"]) == runs)
	get_tree().paused = false

