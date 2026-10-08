class_name Room
extends Node2D
## 单个房间实例。负责几何搭灰盒、投放敌人、波次推进与铃声阶段机制。
##
## 依据 docs/research/玩法机制与校园设计.md 第 3 节：
## 普通房间有课堂与课间两种阶段，铃声前显示倒计时和地面提示，
## 阶段切换改变课桌掩体、移动通道或奖励方式；
## Boss 的切换按固定阶段执行，避免随机铃声把关键攻击变成无法预判的组合。

signal closed(room: Room)
signal enemy_registered(enemy: Enemy)
## 铃声阶段切换，供表现层与 HUD 使用。
signal bell_phase_changed(phase: int)

const BELL_PHASE_SECONDS := 17.0
const BELL_WARNING_SECONDS := 3.0
const WAVE_DELAY := 0.9
const START_GRACE_SECONDS := 0.8

var template: RoomDef = null
var node_data: RoomGraphNode = null

var player: Node2D = null
var covers: Array[Cover] = []
var enemies: Array[Enemy] = []
var bell_phase_timer: float = 0.0
var bell_phase: int = GameConfig.BellPhase.CLASS
var boss: Boss = null

var encounter_plan: Array = []
var current_wave: int = -1
var total_waves: int = 1
var wave_delay_left: float = 0.0
var grace_left: float = 0.0
var is_closed: bool = false
var encounter_finished: bool = false
## 房间变化倍率，用于阶段效果。
var enemy_speed_scale: float = 1.0

var _tile: int = 48
var _origin: Vector2 = Vector2.ZERO
var navigation := AStarGrid2D.new()

func setup(room_template: RoomDef, graph_node: RoomGraphNode) -> void:
	template = room_template
	node_data = graph_node
	_tile = room_template.tile_size
	_origin = Vector2.ZERO

func build() -> void:
	if template == null:
		push_error("[Room] 缺少房间模板")
		return
	_build_floor()
	_build_walls()
	_build_covers()
	_build_navigation()
	encounter_plan = node_data.encounter if node_data != null else []
	total_waves = 1
	for entry in encounter_plan:
		total_waves = maxi(total_waves, int(entry.get("wave", 0)) + 1)
	if template.waves > 1:
		total_waves = maxi(total_waves, template.waves)
	bell_phase_timer = BELL_PHASE_SECONDS
	grace_left = START_GRACE_SECONDS
	queue_redraw()

# --- 几何 ---

func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5) * float(_tile)

func world_size() -> Vector2:
	return template.pixel_size()

func _build_floor() -> void:
	# 地面与网格线由 _draw 完成，这里只保留扩展点。
	pass

func _build_walls() -> void:
	var blocked := RoomGenerator.blocked_cells(template)
	for cell in blocked.keys():
		var wall := StaticBody2D.new()
		wall.collision_layer = GameConfig.bit(GameConfig.LAYER_WORLD)
		wall.collision_mask = 0
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(_tile, _tile)
		shape.shape = rect
		wall.add_child(shape)
		wall.position = cell_to_world(cell)
		add_child(wall)

func _build_covers() -> void:
	for entry in template.covers:
		var parsed := RoomGenerator.parse_cover(str(entry))
		if parsed.is_empty():
			continue
		var cover := Cover.new()
		var cell: Vector2i = parsed["cell"]
		cover.position = cell_to_world(cell)
		cover.configure(cell, float(_tile) - 8.0, 28.0, _cover_tint())
		cover.set_active(int(parsed["active"]) != 0)
		add_child(cover)
		covers.append(cover)
		cover.destroyed.connect(func(_cover): _build_navigation())

func _build_navigation() -> void:
	navigation.region = Rect2i(Vector2i.ZERO, template.grid_size)
	navigation.cell_size = Vector2(_tile, _tile)
	navigation.offset = Vector2(_tile, _tile) * 0.5
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation.update()
	for cell in RoomGenerator.blocked_cells(template):
		navigation.set_point_solid(cell)
	for cover in covers:
		if is_instance_valid(cover) and cover.active:
			navigation.set_point_solid(cover.cell)

func navigation_direction(from: Vector2, destination: Vector2) -> Vector2:
	var first := Vector2i(from / float(_tile))
	var last := Vector2i(destination / float(_tile))
	if not navigation.is_in_boundsv(first) or not navigation.is_in_boundsv(last):
		return (destination - from).normalized()
	var path := navigation.get_point_path(first, last, true)
	if path.size() > 1:
		return (path[1] - from).normalized()
	return (destination - from).normalized()

func _cover_tint() -> Color:
	match template.kind:
		GameConfig.RoomKind.BOSS:
			return Color(0.68, 0.66, 0.74)
		_:
			return Color(0.72, 0.58, 0.38)

# --- 玩家与敌人 ---

func place_player(player_node: Node2D) -> void:
	player = player_node
	player_node.global_position = cell_to_world(template.spawn_player)

## 由战斗总控创建敌人并交给房间登记。
func register_enemy(enemy: Enemy) -> void:
	if not enemies.has(enemy):
		enemies.append(enemy)
		enemy.set_target(player)
		enemy.defeated.connect(_on_enemy_defeated)
		enemy_registered.emit(enemy)

## 按计划投放指定波次的敌人。
func spawn_wave(wave: int) -> int:
	var spawned := 0
	for entry in encounter_plan:
		if int(entry.get("wave", 0)) != wave:
			continue
		var director := GameFlow
		if director == null or not director.has_method("spawn_enemy"):
			continue
		var cell: Vector2i = entry["cell"]
		var enemy: Enemy = director.spawn_enemy(str(entry["enemy_id"]), cell_to_world(cell), false)
		if enemy != null:
			spawned += 1
	GameEvents.room_wave_spawned.emit(node_data.id if node_data != null else -1, wave, spawned)
	return spawned

func spawn_boss() -> void:
	var director := GameFlow
	if director == null or not director.has_method("spawn_boss"):
		return
	var ids := GameData.boss_ids()
	if ids.is_empty():
		push_error("[Room] 数据中没有 Boss 定义")
		return
	var spawn_cell := Vector2i(template.grid_size.x - 5, int(template.grid_size.y / 2))
	boss = director.spawn_boss(ids[0], cell_to_world(spawn_cell), self)
	if boss != null:
		register_enemy(boss)

func is_combat_room() -> bool:
	if template.kind == GameConfig.RoomKind.REST or template.kind == GameConfig.RoomKind.SHOP:
		return false
	return true

func tick(delta: float) -> void:
	if is_closed:
		return
	grace_left = maxf(0.0, grace_left - delta)
	_update_waves(delta)
	_update_bell(delta)
	if bell_warning_active():
		queue_redraw()

func _update_waves(delta: float) -> void:
	if not is_combat_room():
		return
	if wave_delay_left > 0.0:
		wave_delay_left = maxf(0.0, wave_delay_left - delta)
		if wave_delay_left <= 0.0 and current_wave + 1 < total_waves:
			current_wave += 1
			spawn_wave(current_wave)
	enemies = enemies.filter(func(enemy): return is_instance_valid(enemy) and enemy.state != Enemy.EnemyState.DEAD)
	if current_wave < 0 and grace_left <= 0.0:
		if template.kind == GameConfig.RoomKind.BOSS:
			spawn_boss()
			current_wave = 0
		else:
			current_wave = 0
			spawn_wave(0)
		return
	if current_wave >= 0 and enemies.is_empty() and wave_delay_left <= 0.0:
		if current_wave + 1 < total_waves:
			wave_delay_left = WAVE_DELAY
		elif not encounter_finished:
			encounter_finished = true
			_close()

func _on_enemy_defeated(_enemy: Enemy) -> void:
	enemies = enemies.filter(func(item): return is_instance_valid(item) and item.state != Enemy.EnemyState.DEAD)
	if is_combat_room() and enemies.is_empty() and current_wave + 1 >= total_waves and not encounter_finished:
		encounter_finished = true
		_close()

func _close() -> void:
	if is_closed:
		return
	is_closed = true
	GameEvents.room_cleared.emit(node_data.id if node_data != null else -1)
	closed.emit(self)

# --- 铃声阶段 ---

func _update_bell(delta: float) -> void:
	if template.kind == GameConfig.RoomKind.BOSS:
		# Boss 房的铃声由 Boss 阶段控制器触发。
		return
	if template.kind == GameConfig.RoomKind.REST or template.kind == GameConfig.RoomKind.SHOP:
		return
	if not is_combat_room():
		return
	bell_phase_timer -= delta
	GameEvents.bell_countdown.emit(maxf(0.0, bell_phase_timer))
	if bell_phase_timer <= 0.0:
		_shift_bell_phase()

func _shift_bell_phase() -> void:
	bell_phase = GameConfig.BellPhase.BREAK if bell_phase == GameConfig.BellPhase.CLASS else GameConfig.BellPhase.CLASS
	bell_phase_timer = BELL_PHASE_SECONDS
	_apply_cover_phase()
	_build_navigation()
	# 课间阶段敌人移动更快，玩家获得更开阔的空间。
	enemy_speed_scale = 1.18 if bell_phase == GameConfig.BellPhase.BREAK else 1.0
	GameEvents.bell_phase_changed.emit(bell_phase, BELL_PHASE_SECONDS)
	GameEvents.sfx_requested.emit("bell", global_position + world_size() * 0.5)
	bell_phase_changed.emit(bell_phase)
	queue_redraw()

## 由 Boss 阶段控制器调用，按固定阶段执行掩体转换。
func force_bell_shift() -> void:
	_shift_bell_phase()

func _apply_cover_phase() -> void:
	var source := template.break_phase_covers if bell_phase == GameConfig.BellPhase.BREAK else template.class_phase_covers
	if source.is_empty():
		return
	var states: Dictionary = {}
	for entry in source:
		var parsed := RoomGenerator.parse_cover(str(entry))
		if parsed.is_empty():
			continue
		states[parsed["cell"]] = int(parsed["active"]) != 0
	for cover in covers:
		if not is_instance_valid(cover):
			continue
		if states.has(cover.cell):
			cover.set_active(bool(states[cover.cell]))

func bell_warning_active() -> bool:
	return bell_phase_timer <= BELL_WARNING_SECONDS

func bell_progress() -> float:
	return clampf(1.0 - bell_phase_timer / BELL_PHASE_SECONDS, 0.0, 1.0)

# --- 表现 ---

func _draw() -> void:
	var size := world_size()
	# 地板底色按房间类型区分。
	var floor_color := Color("#718d82")
	if template.kind == GameConfig.RoomKind.BOSS:
		floor_color = Color("#927f78")
	draw_rect(Rect2(Vector2.ZERO, size), floor_color)
	for x in range(1, template.grid_size.x - 1):
		for y in range(1, template.grid_size.y - 1):
			if (x + y) % 2 == 0:
				draw_rect(Rect2(x * _tile, y * _tile, _tile, _tile), floor_color.lightened(0.035))
	# 网格线。
	var grid_color := Color(1, 1, 1, 0.045)
	for x in range(template.grid_size.x + 1):
		var px := float(x * _tile)
		draw_line(Vector2(px, 0), Vector2(px, size.y), grid_color, 1.0)
	for y in range(template.grid_size.y + 1):
		var py := float(y * _tile)
		draw_line(Vector2(0, py), Vector2(size.x, py), grid_color, 1.0)
	# 墙体。
	var blocked := RoomGenerator.blocked_cells(template)
	for cell in blocked.keys():
		var rect := Rect2(Vector2(float(cell.x) * _tile, float(cell.y) * _tile), Vector2(_tile, _tile))
		draw_rect(rect, Color("#bdbaa0"))
		draw_rect(Rect2(rect.position + Vector2(3, 3), rect.size - Vector2(6, 6)), Color("#d5ceb2"))
		draw_line(rect.position + Vector2(0, _tile - 4), rect.end - Vector2(0, 4), Color("#657569"), 5)
	# 黑板和窗户置于墙体范围内。
	draw_rect(Rect2(340, 4, 450, 38), Color("#b29670"))
	draw_rect(Rect2(347, 8, 436, 29), Color("#26483e"))
	draw_string(_get_font(), Vector2(365, 29), "课外行动  ·  CAMPUS ANOMALY", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("#e3e8d2"))
	for x in [96, 240, 864, 1008]:
		draw_rect(Rect2(x, 9, 68, 29), Color("#537e87"))
		draw_rect(Rect2(x + 4, 12, 60, 22), Color("#9dc4bf"))
		draw_line(Vector2(x + 34, 12), Vector2(x + 34, 34), Color("#dce3cb"), 3)
	draw_rect(Rect2(size.x - 78, size.y * 0.5 - 35, 26, 70), Color("#be9c74"))
	draw_circle(Vector2(size.x - 57, size.y * 0.5), 3, Color("#f3d080"))
	# 铃声预警：地面提示在切换前出现，让阶段变化可以预判。
	if bell_warning_active() and is_combat_room():
		var pulse := 0.4 + 0.2 * sin(Time.get_ticks_msec() * 0.012)
		draw_rect(Rect2(Vector2(48, 48), size - Vector2(96, 96)), Color(1.0, 0.85, 0.4, pulse), false, 5)
	# 出生点标记。
	var spawn := cell_to_world(template.spawn_player)
	draw_arc(spawn, 18.0, 0.0, TAU, 24, Color(0.4, 0.8, 1.0, 0.5), 2.0)
	# 房间类型标注。
	var label := ""
	if node_data != null:
		label = "%s · %s" % [template.display_name, node_data.display_kind()]
	if not label.is_empty():
		draw_string(_get_font(), Vector2(65, 80), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("#ecedd7"))

var _font: Font = null

func _get_font() -> Font:
	if _font == null:
		var system_font := SystemFont.new()
		system_font.font_names = PackedStringArray(["Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC", "Arial"])
		_font = system_font
	return _font
