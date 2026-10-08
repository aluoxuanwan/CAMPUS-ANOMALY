extends Node
## 游戏总控。负责流程状态、房间切换、固定时间步与自检入口。
##
## 依据 docs/research/技术与动画方案.md 第 3 节与第 7 节：
## 暂停、子弹时间与帧率变化统一使用游戏时间；
## 规则推进集中在本节点，表现层只消费事件。
##
## 时间模型：
## - _process 记录真实时间，用于命中停顿等与画面同步的效果。
## - _physics_process 推进局内时间，玩家与敌人由本节点手动步进，
##   保证慢动作与帧率变化不会改变冷却与判定结果。

enum FlowState { BOOT, MENU, COURSE, PLAYING, REWARD, PAUSED, DEAD, VICTORY }

const TILE_HINT := 48

var state: int = FlowState.BOOT
var player: Player = null
var current_room: Room = null
var camera: CameraDirector = null
var graph := RoomGraph.new()
var visited: Array[int] = []
var current_room_id: int = -1
## 自检模式：关闭真实输入与设备相关表现，按固定脚本推进。
var self_test_mode: bool = false
var _next_attack_id: int = 1
var _room_clear_timer: float = 0.0
var _pending_reward: bool = false
## 课表选路：本节点选择的课程标签。
var course_choice: String = ""
var offered_rewards: Array[String] = []
var reward_selected: bool = false
var _elapsed_real: float = 0.0
var _last_real_msec: float = 0.0

# --- 世界容器 ---
var actors: Node2D = null
var effects: Node2D = null
var ui_layer: CanvasLayer = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameEvents.screen_flash_requested.connect(_on_screen_flash)
	GameEvents.run_failed.connect(_on_run_failed)
	_last_real_msec = Time.get_ticks_msec() as float

## 由主场景在构建完世界后调用。
func attach_world(actors_node: Node2D, effects_node: Node2D, ui: CanvasLayer, cam: CameraDirector) -> void:
	actors = actors_node
	effects = effects_node
	ui_layer = ui
	camera = cam

func next_attack_id() -> int:
	_next_attack_id += 1
	return _next_attack_id

func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() as float
	var unscaled := maxf(0.0, (now - _last_real_msec) / 1000.0)
	_last_real_msec = now
	if state == FlowState.PLAYING and not self_test_mode:
		_elapsed_real += unscaled
		_process_room_clear(unscaled)
	# delta 未使用，表现层事件自行按真实时间处理。
	var _ignored := delta

func _physics_process(delta: float) -> void:
	if state != FlowState.PLAYING or self_test_mode:
		return
	step_world(delta)

## 推进一帧规则逻辑。玩家与敌人都由这里手动步进。
func step_world(delta: float) -> void:
	if state != FlowState.PLAYING:
		return
	if self_test_mode:
		_process_room_clear(delta)
		if state != FlowState.PLAYING:
			return
	if player == null or not is_instance_valid(player):
		return
	if current_room != null and is_instance_valid(current_room):
		current_room.tick(delta)
	player.poll_actions()
	player.tick_timers(delta)
	player._update_aim()
	player._update_attack(delta)
	player._update_abilities()
	if player.state == Player.State.DASH:
		player._update_dash(delta)
	else:
		player._update_movement(delta)
	player.move_and_slide()
	player.queue_redraw()
	for node in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(node) and node is Node:
			node._physics_process(delta)
	RunState.tick_timers(delta)

# --- 局流程 ---

func start_run(seed_override: int = 0) -> void:
	get_tree().paused = false
	release_hitstop()
	clear_world()
	RunState.begin_run(seed_override)
	graph = RoomGraph.new()
	var templates: Array = []
	for id in GameData.rooms.keys():
		templates.append(GameData.rooms[id])
	graph.generate(templates, RunState.rng, RunState.seed_value)
	if not graph.validate():
		for problem in graph.errors:
			push_error("[GameFlow] " + problem)
	visited.clear()
	current_room_id = -1
	_room_clear_timer = 0.0
	_pending_reward = false
	course_choice = ""
	state = FlowState.PLAYING
	_enter_room(graph.start_id)

## 进入指定房间。房间切换时强制结束命中停顿，避免残留低时间倍率。
func _enter_room(room_id: int) -> void:
	var node_data := graph.get_node_by_id(room_id)
	if node_data == null:
		push_error("[GameFlow] 房间节点不存在：%d" % room_id)
		return
	var template := GameData.get_room(node_data.template_id)
	if template == null:
		push_error("[GameFlow] 房间模板不存在：%s" % node_data.template_id)
		return
	release_hitstop()
	_destroy_room()
	current_room_id = room_id
	if not visited.has(room_id):
		visited.append(room_id)
	var room := Room.new()
	room.setup(template, node_data)
	actors.add_child(room)
	current_room = room
	room.closed.connect(_on_room_closed)
	room.build()
	if player == null or not is_instance_valid(player):
		player = Player.new()
		player.set_physics_process(false)
		player.zone_requested.connect(_on_zone_requested)
		player.deployable_requested.connect(_on_deployable_requested)
		actors.add_child(player)
		player.set_physics_process(false)
		if camera != null:
			camera.set_follow(player)
			camera.clamp_to_room(room.world_size())
	room.place_player(player)
	if camera != null:
		camera.clamp_to_room(room.world_size())
	GameEvents.room_entered.emit(room_id, node_data.template_id, node_data.display_kind())
	if ui_layer != null and ui_layer.has_method("on_room_entered"):
		ui_layer.on_room_entered(room, node_data)

## 场景切换与暂停时结束命中停顿，避免残留低时间倍率。
func release_hitstop() -> void:
	for node in get_tree().get_nodes_in_group("hitstop"):
		if node.has_method("force_release"):
			node.force_release()

func _destroy_room() -> void:
	for child in actors.get_children():
		if child != player:
			actors.remove_child(child)
			child.queue_free()
	for child in effects.get_children():
		effects.remove_child(child)
		child.queue_free()
	current_room = null

func clear_world() -> void:
	if actors == null:
		return
	for child in actors.get_children():
		actors.remove_child(child)
		child.queue_free()
	if effects != null:
		for child in effects.get_children():
			effects.remove_child(child)
			child.queue_free()
	player = null
	current_room = null

func _on_room_closed(room: Room) -> void:
	# 本局已结束时不再推进流程，避免死亡后仍弹出奖励或通关界面。
	if not RunState.is_active:
		return
	RunState.note_room_cleared()
	var node_data := graph.get_node_by_id(current_room_id)
	var is_boss := node_data != null and node_data.kind == GameConfig.RoomKind.BOSS
	if current_room != null and current_room.boss != null:
		is_boss = true
	if is_boss:
		RunState.add_run_tag("击败试卷巨像")
		RunState.complete_run()
		state = FlowState.VICTORY
		if ui_layer != null and ui_layer.has_method("show_victory"):
			ui_layer.show_victory()
		return
	# 房间结束后进入课表选路与奖励界面。
	_room_clear_timer = GameConfig.ROOM_CLEAR_DELAY
	_pending_reward = true

func _process_room_clear(delta: float) -> void:
	if not _pending_reward:
		return
	_room_clear_timer -= delta
	if _room_clear_timer > 0.0:
		return
	_pending_reward = false
	_open_course_or_reward()

func _open_course_or_reward() -> void:
	var options := _next_room_options()
	if options.is_empty():
		# 没有后续房间时直接结束本局。
		RunState.complete_run()
		state = FlowState.VICTORY
		if ui_layer != null and ui_layer.has_method("show_victory"):
			ui_layer.show_victory()
		return
	reward_selected = false
	roll_rewards()
	state = FlowState.REWARD
	release_hitstop()
	get_tree().paused = true
	if ui_layer != null and ui_layer.has_method("show_reward_screen"):
		ui_layer.show_reward_screen(options)

## 返回可选的下一批房间编号。
func _next_room_options() -> Array[int]:
	var node_data := graph.get_node_by_id(current_room_id)
	if node_data == null:
		return []
	return node_data.next

## 由界面调用：选择下一个房间并应用课表奖励倾向。
func choose_next_room(room_id: int) -> void:
	if state != FlowState.REWARD:
		return
	if not reward_selected:
		return
	if not _next_room_options().has(room_id):
		return
	get_tree().paused = false
	var node_data := graph.get_node_by_id(room_id)
	if node_data != null and not node_data.course_tags.is_empty():
		course_choice = node_data.course_tags[0]
		RunState.add_run_tag("选课:%s" % course_choice)
	_enter_room(room_id)
	state = FlowState.PLAYING

func roll_rewards() -> void:
	offered_rewards.clear()
	var candidates: Array[String] = []
	for id in GameData.modifiers:
		var def := GameData.get_modifier(id)
		if RunState.modifiers.stack_count(id) < def.max_stacks and id != "ink_diffusion":
			candidates.append(id)
	while offered_rewards.size() < 3 and not candidates.is_empty():
		var index := RunState.rng.randi_range(0, candidates.size() - 1)
		offered_rewards.append(candidates.pop_at(index))
	if offered_rewards.is_empty():
		offered_rewards.append("heal")

func select_reward(id: String) -> bool:
	if state != FlowState.REWARD or reward_selected or not offered_rewards.has(id):
		return false
	if id == "heal":
		player.heal(25.0)
	else:
		RunState.grant_modifier(id)
	reward_selected = true
	GameEvents.reward_chosen.emit(id, "战后奖励")
	return true

func reroll_rewards() -> bool:
	if state != FlowState.REWARD or reward_selected or RunState.rerolls_left <= 0:
		return false
	RunState.rerolls_left -= 1
	roll_rewards()
	return true

# --- 暂停 ---

func toggle_pause() -> void:
	if state == FlowState.PLAYING:
		release_hitstop()
		state = FlowState.PAUSED
		get_tree().paused = true
		if ui_layer != null and ui_layer.has_method("show_pause"):
			ui_layer.show_pause(true)
	elif state == FlowState.PAUSED:
		state = FlowState.PLAYING
		get_tree().paused = false
		if ui_layer != null and ui_layer.has_method("show_pause"):
			ui_layer.show_pause(false)

# --- 生成请求 ---

func spawn_enemy(enemy_id: String, world_position: Vector2, is_minion: bool) -> Enemy:
	var def := GameData.get_enemy(enemy_id)
	if def == null:
		push_error("[GameFlow] 敌人定义不存在：%s" % enemy_id)
		return null
	var enemy := Enemy.new()
	enemy.global_position = world_position
	enemy.configure(def, current_room != null and current_room.node_data.kind == GameConfig.RoomKind.ELITE and not is_minion)
	actors.add_child(enemy)
	if is_minion:
		enemy.add_to_group("minions")
	enemy.set_physics_process(false)
	if current_room != null and is_instance_valid(current_room):
		current_room.register_enemy(enemy)
	return enemy

func spawn_boss(enemy_id: String, world_position: Vector2, room: Room) -> Boss:
	var def := GameData.get_enemy(enemy_id)
	if def == null:
		push_error("[GameFlow] Boss 定义不存在：%s" % enemy_id)
		return null
	var boss := Boss.new()
	boss.global_position = world_position
	boss.configure_boss(def, room)
	actors.add_child(boss)
	boss.set_physics_process(false)
	return boss

func spawn_zone(config: Dictionary) -> Zone:
	var zone := Zone.new()
	zone.configure(config)
	var position: Vector2 = config.get("position", Vector2.ZERO)
	zone.global_position = position
	effects.add_child(zone)
	return zone

func _on_zone_requested(config: Dictionary) -> void:
	spawn_zone(config)

func _on_deployable_requested(config: Dictionary) -> void:
	var deployable := Deployable.new()
	deployable.configure(config)
	var position: Vector2 = config.get("position", Vector2.ZERO)
	deployable.global_position = position
	effects.add_child(deployable)

func _on_player_damaged(_amount: int, _remaining: int) -> void:
	if camera != null:
		camera._on_shake_requested(GameConfig.CAMERA_SHAKE_HEAVY)

func _on_screen_flash(_color: Color, _duration: float) -> void:
	if ui_layer != null and ui_layer.has_method("flash"):
		ui_layer.flash(_color, _duration)

# --- 结算 ---

func _on_run_failed(rooms_cleared: int, elapsed: float) -> void:
	var _ignored := Vector2(rooms_cleared, elapsed)
	state = FlowState.DEAD
	var points := RunState.settle_rewards(false)
	if ui_layer != null and ui_layer.has_method("show_death_screen"):
		ui_layer.show_death_screen(points)

func restart_run() -> void:
	get_tree().paused = false
	state = FlowState.BOOT
	start_run(0)

## 供 HUD 读取的进度摘要。
func progress_text() -> String:
	return "第 %d / 6 节" % visited.size()

func state_name() -> String:
	match state:
		FlowState.BOOT:
			return "启动"
		FlowState.MENU:
			return "菜单"
		FlowState.COURSE:
			return "选课"
		FlowState.PLAYING:
			return "战斗"
		FlowState.REWARD:
			return "奖励"
		FlowState.PAUSED:
			return "暂停"
		FlowState.DEAD:
			return "失败"
		FlowState.VICTORY:
			return "通关"
	return "未知"
