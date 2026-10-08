class_name RoomGraph
extends RefCounted
## 一局内的房间图。
##
## 依据 docs/research/技术与动画方案.md 第 5 节：
## 先生成有起点、区域节点、精英、商店、恢复与 Boss 的房间图，
## 检查连通与奖励规则，随后给节点填入人工布局模板、敌人组合和道具。
## 随机种子与生成版本一起记录，方便复现某个不可完成的房间。

const GENERATION_VERSION := 1

var nodes: Dictionary = {}
var start_id: int = 0
var boss_id: int = 0
var seed_value: int = 0
## 生成过程中的校验问题。
var errors: PackedStringArray = PackedStringArray()

## 按模板标识与随机种子构建一局的房间图。
func generate(templates: Array, rng: RandomNumberGenerator, seed_used: int) -> void:
	nodes.clear()
	errors.clear()
	seed_value = seed_used
	var pools := _split_by_kind(templates)
	if pools["combat"].is_empty():
		errors.append("缺少战斗房间模板")
		return
	if pools["boss"].is_empty():
		errors.append("缺少 Boss 房间模板")
		return

	var combat_count := mini(6, pools["combat"].size())
	var shuffled_combat: Array = pools["combat"].duplicate()
	_shuffle(shuffled_combat, rng)

	# 起点。
	start_id = 0
	var start := RoomGraphNode.new()
	start.id = 0
	start.template_id = "room_01_entrance"
	start.kind = GameConfig.RoomKind.START
	start.difficulty = 0.0
	start.course_tags = PackedStringArray(["classroom"])
	nodes[0] = start

	# 两条分支各自串联，随后汇合到精英节点。
	var next_id := 1
	var lane_a: Array[int] = []
	var lane_b: Array[int] = []
	for index in range(combat_count):
		var node := RoomGraphNode.new()
		node.id = next_id
		node.template_id = shuffled_combat[index].id
		node.kind = GameConfig.RoomKind.COMBAT
		node.difficulty = 1.0 + float(index) * 0.14
		node.course_tags = shuffled_combat[index].course_tags
		# 两条分支轮流分配，随后各自串联并汇合到精英节点。
		if index % 2 == 0:
			node.lane = 0
			lane_a.append(next_id)
		else:
			node.lane = 1
			lane_b.append(next_id)
		nodes[next_id] = node
		next_id += 1

	if lane_a.is_empty() and not lane_b.is_empty():
		lane_a.append(lane_b.pop_front())
	if lane_b.is_empty() and lane_a.size() > 1:
		lane_b.append(lane_a.pop_back())
	# 起点同时连到两条分支的入口，保证两条路线都可以进入。
	var entries: Array[int] = []
	if not lane_a.is_empty():
		entries.append(lane_a[0])
	if not lane_b.is_empty():
		entries.append(lane_b[0])
	start.next = Array(entries, TYPE_INT, "", null)

	# 精英节点作为两条分支的汇合点。
	var elite := RoomGraphNode.new()
	elite.id = next_id
	elite.template_id = "room_07_elite_podium"
	elite.kind = GameConfig.RoomKind.ELITE
	elite.difficulty = 1.5
	elite.course_tags = PackedStringArray(["classroom"])
	elite.lane = 0
	nodes[next_id] = elite
	next_id += 1

	# Boss 节点。
	var boss := RoomGraphNode.new()
	boss.id = next_id
	for template in pools["boss"]:
		boss.template_id = template.id
		break
	boss.kind = GameConfig.RoomKind.BOSS
	boss.difficulty = 2.0
	boss.course_tags = PackedStringArray(["classroom", "boss"])
	boss.lane = 0
	nodes[next_id] = boss
	boss_id = next_id

	_wire_chain(lane_a, elite.id)
	_wire_chain(lane_b, elite.id)
	elite.next = Array([boss.id], TYPE_INT, "", null)
	boss.previous = Array([elite.id], TYPE_INT, "", null)

	# 填充敌人组合。
	for id in nodes.keys():
		var node: RoomGraphNode = nodes[id]
		var room := GameData.get_room(node.template_id)
		if room == null:
			errors.append("房间模板不存在：%s" % node.template_id)
			continue
		if node.kind == GameConfig.RoomKind.BOSS:
			continue
		node.encounter = RoomGenerator.build_encounter(room, rng, int(id), node.difficulty)

func _split_by_kind(templates: Array) -> Dictionary:
	var pools := {"combat": [], "elite": [], "boss": [], "shop": [], "rest": []}
	for template in templates:
		match template.kind:
			GameConfig.RoomKind.BOSS:
				pools["boss"].append(template)
			GameConfig.RoomKind.ELITE:
				pools["elite"].append(template)
			GameConfig.RoomKind.SHOP:
				pools["shop"].append(template)
			GameConfig.RoomKind.REST:
				pools["rest"].append(template)
			_:
				pools["combat"].append(template)
	return pools

func _wire_chain(chain: Array[int], final_id: int) -> void:
	if chain.is_empty():
		return
	for index in range(chain.size()):
		var node: RoomGraphNode = nodes[chain[index]]
		if index + 1 < chain.size():
			node.next = Array([chain[index + 1]], TYPE_INT, "", null)
			var child: RoomGraphNode = nodes[chain[index + 1]]
			child.previous.append(node.id)
		else:
			node.next = Array([final_id], TYPE_INT, "", null)
			var tail: RoomGraphNode = nodes[final_id]
			tail.previous.append(node.id)

func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for index in range(items.size() - 1, 0, -1):
		var swap_index := rng.randi() % (index + 1)
		var temp = items[index]
		items[index] = items[swap_index]
		items[swap_index] = temp

func get_node_by_id(id: int) -> RoomGraphNode:
	return nodes.get(id)

## 校验全部节点可达，且 Boss 可以从起点走到。
func validate() -> bool:
	if nodes.is_empty():
		errors.append("房间图为空")
		return false
	var reachable := _reachable_from(start_id)
	if not reachable.has(boss_id):
		errors.append("Boss 节点从起点不可达")
	for id in nodes.keys():
		if not reachable.has(id):
			errors.append("节点 %d 不可达" % int(id))
	return errors.is_empty()

func _reachable_from(from_id: int) -> Dictionary:
	var seen: Dictionary = {}
	var queue: Array[int] = [from_id]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		if seen.has(current):
			continue
		seen[current] = true
		var node: RoomGraphNode = nodes.get(current)
		if node == null:
			continue
		for child in node.next:
			if not seen.has(child):
				queue.append(child)
	return seen

## 本局的战斗房加精英房数量，用于结果摘要。
func combat_room_count() -> int:
	var total := 0
	for id in nodes.keys():
		var node: RoomGraphNode = nodes[id]
		if node.kind == GameConfig.RoomKind.COMBAT or node.kind == GameConfig.RoomKind.ELITE:
			total += 1
	return total

func describe() -> String:
	return "房间图 v%d 种子 %d 节点 %d 战斗房 %d 校验问题 %d" % [
		GENERATION_VERSION, seed_value, nodes.size(), combat_room_count(), errors.size()
	]
