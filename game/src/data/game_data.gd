extends Node
## 数据装配：把 data/*.json 读成带类型的定义对象，并在启动时校验。
##
## 依据 docs/research/技术与动画方案.md 第 3 节：
## 数据与规则分离，同一资源引用不在运行时被修改，
## 生命、冷却与临时叠加状态保存在独立实例中。

const DATA_DIR := "res://data/"

var weapons: Dictionary = {}
var abilities: Dictionary = {}
var modifiers: Dictionary = {}
var enemies: Dictionary = {}
var rooms: Dictionary = {}
var rewards: Dictionary = {}

## 启动校验发现的问题。空数组表示数据自洽。
var validation_errors: PackedStringArray = PackedStringArray()

func _ready() -> void:
	load_all()

func load_all() -> void:
	validation_errors.clear()
	weapons = _load_defs("weapons.json", func() -> Resource: return WeaponDef.new())
	abilities = _load_defs("abilities.json", func() -> Resource: return AbilityDef.new())
	modifiers = _load_defs("modifiers.json", func() -> Resource: return ModifierDef.new())
	enemies = _load_defs("enemies.json", func() -> Resource: return EnemyDef.new())
	rooms = _load_defs("rooms.json", func() -> Resource: return RoomDef.new())
	_validate()
	if not validation_errors.is_empty():
		for problem in validation_errors:
			push_error("[GameData] " + problem)

func _load_defs(file_name: String, factory: Callable) -> Dictionary:
	var path := DATA_DIR + file_name
	if not FileAccess.file_exists(path):
		validation_errors.append("数据文件缺失：" + path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Array):
		validation_errors.append("数据文件格式错误，需要数组根节点：" + path)
		return {}
	var result: Dictionary = {}
	for entry in parsed:
		if not (entry is Dictionary):
			validation_errors.append("数据条目不是对象：" + path)
			continue
		var def: Resource = factory.call()
		_apply_dictionary(def, entry)
		_resolve_string_enums(def)
		if def.id.is_empty():
			validation_errors.append("数据条目缺少 id：" + path)
			continue
		if result.has(def.id):
			validation_errors.append("数据 id 重复：%s 位于 %s" % [def.id, path])
			continue
		result[def.id] = def
	return result

## 按字段名反射赋值，未知字段记录为错误，避免拼写问题被静默忽略。
func _apply_dictionary(def: Resource, entry: Dictionary) -> void:
	for key in entry.keys():
		var field := str(key)
		if not (field in def):
			validation_errors.append("%s 含未知字段：%s" % [def.get_class(), field])
			continue
		def.set(field, _coerce(def.get(field), entry[key]))

## JSON 只有浮点数与数组，这里转换回目标字段的类型。
func _coerce(current: Variant, value: Variant) -> Variant:
	match typeof(current):
		TYPE_INT:
			return int(value)
		TYPE_FLOAT:
			return float(value)
		TYPE_BOOL:
			return bool(value)
		TYPE_STRING:
			return str(value)
		TYPE_COLOR:
			if value is Array and value.size() >= 3:
				var a := 1.0
				if value.size() >= 4:
					a = float(value[3])
				return Color(float(value[0]), float(value[1]), float(value[2]), a)
			return current
		TYPE_VECTOR2I:
			if value is Array and value.size() >= 2:
				return Vector2i(int(value[0]), int(value[1]))
			return current
		TYPE_PACKED_STRING_ARRAY:
			var out := PackedStringArray()
			if value is Array:
				for item in value:
					out.append(str(item))
			return out
	return value

## 数据文件用字符串保存枚举，加载后在这里解析为整数。
func _resolve_string_enums(def: Resource) -> void:
	if def is AbilityDef:
		(def as AbilityDef).resolve_kind()
	elif def is WeaponDef:
		(def as WeaponDef).resolve_delivery()
	elif def is EnemyDef:
		(def as EnemyDef).resolve_family()

# --- 查询接口 ---

func get_weapon(id: String) -> WeaponDef:
	return weapons.get(id)

func get_ability(id: String) -> AbilityDef:
	return abilities.get(id)

func get_modifier(id: String) -> ModifierDef:
	return modifiers.get(id)

func get_enemy(id: String) -> EnemyDef:
	return enemies.get(id)

func get_room(id: String) -> RoomDef:
	return rooms.get(id)

func get_reward(id: String) -> RewardDef:
	return rewards.get(id)

## 按家族取敌人标识，供房间生成器填充组合。
func enemy_ids_by_family(family: int) -> PackedStringArray:
	var out := PackedStringArray()
	for id in enemies.keys():
		var def: EnemyDef = enemies[id]
		if def.family == family:
			out.append(id)
	return out

func boss_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id in enemies.keys():
		var def: EnemyDef = enemies[id]
		if def.has_tag("boss"):
			out.append(id)
	return out

func standard_enemy_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id in enemies.keys():
		var def: EnemyDef = enemies[id]
		if not def.has_tag("boss"):
			out.append(id)
	return out

## 按奖励池筛选词条标识。
func modifier_ids_in_pool(pool: String) -> PackedStringArray:
	var out := PackedStringArray()
	for id in modifiers.keys():
		var def: ModifierDef = modifiers[id]
		if def.pool == pool:
			out.append(id)
	return out

func _validate() -> void:
	for id in modifiers.keys():
		var def: ModifierDef = modifiers[id]
		if def.max_stacks < 1:
			validation_errors.append("词条 %s 的 max_stacks 小于 1" % id)
		if def.weight <= 0.0:
			validation_errors.append("词条 %s 的 weight 不大于 0" % id)
	for id in rooms.keys():
		var def: RoomDef = rooms[id]
		if def.grid_size.x <= 0 or def.grid_size.y <= 0:
			validation_errors.append("房间 %s 的 grid_size 非法" % id)
		if def.tile_size <= 0:
			validation_errors.append("房间 %s 的 tile_size 非法" % id)
		for key in ["spawn_player"]:
			var cell: Vector2i = def.get(key)
			if cell.x < 1 or cell.y < 1 or cell.x >= def.grid_size.x - 1 or cell.y >= def.grid_size.y - 1:
				validation_errors.append("房间 %s 的 %s 落在边界外" % [id, key])
	for id in weapons.keys():
		var def: WeaponDef = weapons[id]
		if def.cycle_time() <= 0.0:
			validation_errors.append("武器 %s 的攻击周期为 0" % id)
	for id in enemies.keys():
		var def: EnemyDef = enemies[id]
		if def.max_health <= 0.0:
			validation_errors.append("敌人 %s 的生命上限非法" % id)
		if def.threat < 1:
			validation_errors.append("敌人 %s 的威胁预算小于 1" % id)

## 供自检与调试输出使用的一行摘要。
func summary() -> String:
	return "武器 %d 技能 %d 词条 %d 敌人 %d 房间 %d 校验问题 %d" % [
		weapons.size(), abilities.size(), modifiers.size(), enemies.size(), rooms.size(), validation_errors.size()
	]
