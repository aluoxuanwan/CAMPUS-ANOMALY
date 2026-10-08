class_name RoomGenerator
extends RefCounted
## 房间攻击性内容生成。
##
## 依据 docs/research/技术与动画方案.md 第 5 节与
## docs/research/玩法机制与校园设计.md 第 4 节：
## 房间图先检查连通与奖励规则，再给节点填入人工布局模板与敌人组合；
## 生成器设置威胁预算与高控制敌人上限；
## 连续出现远射与封路时，必须留有移动解法。

const MIN_SPAWN_DISTANCE := 190.0
const HIGH_CONTROL_FAMILIES := [EnemyDef.Family.SHOOTER, EnemyDef.Family.ZONE, EnemyDef.Family.SUMMONER]
const MAX_HIGH_CONTROL := 2

## 生成一组敌人投放计划。
## 返回数组，每项包含 enemy_id、cell、family、wave。
static func build_encounter(room: RoomDef, rng: RandomNumberGenerator, room_index: int, difficulty: float) -> Array:
	var plan: Array = []
	var floor_cells := free_cells(room)
	if floor_cells.is_empty():
		return plan
	var player_cell: Vector2i = room.spawn_player
	var budget := maxi(3, int(round(float(room.threat_budget) * difficulty)))
	var wave_count := maxi(1, room.waves)
	var per_wave_budget := maxi(2, int(ceil(float(budget) / float(wave_count))))
	var families := _family_sequence(room, rng, room_index)
	var family_index := 0
	var high_control_used := 0
	for wave in range(wave_count):
		var spent := 0
		var safety := 0
		while spent < per_wave_budget and safety < 40:
			safety += 1
			var family: int = families[family_index % families.size()]
			family_index += 1
			var ids := GameData.enemy_ids_by_family(family)
			if ids.is_empty():
				continue
			var enemy_id: String = ids[rng.randi() % ids.size()]
			var enemy_def := GameData.get_enemy(enemy_id)
			if enemy_def == null:
				continue
			if not room.allow_high_control and HIGH_CONTROL_FAMILIES.has(family):
				continue
			if HIGH_CONTROL_FAMILIES.has(family):
				if high_control_used >= MAX_HIGH_CONTROL:
					continue
				high_control_used += 1
			if spent + enemy_def.threat > per_wave_budget + 1:
				continue
			var cell := _pick_cell(floor_cells, room, player_cell, rng)
			if cell == Vector2i(-9999, -9999):
				continue
			plan.append({
				"enemy_id": enemy_id,
				"cell": cell,
				"family": family,
				"wave": wave,
			})
			spent += enemy_def.threat
	return plan

## 按房间顺序安排家族，保证一局内六个家族都会出现。
static func _family_sequence(room: RoomDef, rng: RandomNumberGenerator, room_index: int) -> Array:
	var order: Array = [EnemyDef.Family.CHASER]
	if room.course_tags.has("lab"):
		order.append(EnemyDef.Family.ZONE)
	if room.course_tags.has("gym"):
		order.append(EnemyDef.Family.DASHER)
	if room.course_tags.has("library"):
		order.append(EnemyDef.Family.SHIELD)
	order.append(EnemyDef.Family.SHOOTER)
	if room.threat_budget >= 5:
		order.append(EnemyDef.Family.SUMMONER)
	order.append(EnemyDef.Family.SHIELD)
	order.append(EnemyDef.Family.DASHER)
	# 用房间编号旋转起始位置，让不同房间的组合不同。
	var shift := room_index % order.size()
	var rotated: Array = []
	for index in range(order.size()):
		rotated.append(order[(index + shift) % order.size()])
	return rotated

## 选择满足距离要求的出生格。
static func _pick_cell(floor_cells: Array, room: RoomDef, player_cell: Vector2i, rng: RandomNumberGenerator) -> Vector2i:
	var attempts := 0
	while attempts < 24:
		attempts += 1
		var cell: Vector2i = floor_cells[rng.randi() % floor_cells.size()]
		var cell_position := Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5) * float(room.tile_size)
		var player_position := Vector2(float(player_cell.x) + 0.5, float(player_cell.y) + 0.5) * float(room.tile_size)
		if cell_position.distance_to(player_position) >= MIN_SPAWN_DISTANCE:
			return cell
	return Vector2i(-9999, -9999)

## 计算可站立的格集合。墙体与掩体都不计入。
static func free_cells(room: RoomDef) -> Array:
	var blocked := blocked_cells(room)
	var out: Array = []
	for y in range(1, room.grid_size.y - 1):
		for x in range(1, room.grid_size.x - 1):
			var cell := Vector2i(x, y)
			if blocked.has(cell):
				continue
			out.append(cell)
	return out

## 返回被墙体或掩体占据的格集合。
static func blocked_cells(room: RoomDef) -> Dictionary:
	var blocked: Dictionary = {}
	var x := 0
	while x < room.grid_size.x:
		blocked[Vector2i(x, 0)] = true
		blocked[Vector2i(x, room.grid_size.y - 1)] = true
		x += 1
	var y := 0
	while y < room.grid_size.y:
		blocked[Vector2i(0, y)] = true
		blocked[Vector2i(room.grid_size.x - 1, y)] = true
		y += 1
	for entry in room.walls:
		var cell := parse_cell(str(entry))
		if cell.x >= 0:
			blocked[cell] = true
	for entry in room.covers:
		var cover := parse_cover(str(entry))
		if cover.is_empty():
			continue
		var cell: Vector2i = cover["cell"]
		if int(cover["active"]) != 0:
			blocked[cell] = true
	return blocked

static func parse_cell(text: String) -> Vector2i:
	var parts := text.split(",")
	if parts.size() < 2:
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))

static func parse_cover(text: String) -> Dictionary:
	var parts := text.split(",")
	if parts.size() < 2:
		return {}
	return {
		"cell": Vector2i(int(parts[0]), int(parts[1])),
		"active": int(parts[2]) if parts.size() >= 3 else 1,
	}
