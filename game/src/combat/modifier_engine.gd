class_name ModifierEngine
extends RefCounted
## 词条与触发链运行时。
##
## 区分静态词条（trigger 为 ALWAYS）与触发词条（其余 trigger）。
## 依据 docs/research/技术与动画方案.md 第 4 节与第 10 节：
## 触发链设置深度上限与次数上限，达到上限时记录原因，
## 防止弹射、复制与击杀爆炸形成无限调用。

## 按块计时器。RunState 在暂停时停止推进它。
var _clock: float = 0.0

## 已获得词条：def_id -> 层数。
var stacks: Dictionary = {}

## 触发词条的内部冷却剩余。
var _internal_cooldown: Dictionary = {}

## 临时加成：stat -> Array[Dictionary]，每项含 amount 与剩余时间。
var _temporary: Dictionary = {}

## 触发链计数与上限诊断。
var _chain_depth: Dictionary = {}
var _burst_window_start: float = 0.0
var _burst_count: Dictionary = {}
var _trigger_count: int = 0
var chain_limit_reports: PackedStringArray = PackedStringArray()

## 只读快照，供调试面板使用。
var last_resolved_stats: Dictionary = {}

func set_clock(now: float) -> void:
	_clock = now

func clear() -> void:
	stacks.clear()
	_internal_cooldown.clear()
	_temporary.clear()
	_chain_depth.clear()
	_burst_count.clear()
	chain_limit_reports.clear()
	last_resolved_stats.clear()

# --- 词条获取 ---

## 返回实际获得的层数，0 表示已达上限。
func grant(def_id: String) -> int:
	var def := _def(def_id)
	if def == null:
		return 0
	var current := int(stacks.get(def_id, 0))
	if current >= def.max_stacks:
		return 0
	stacks[def_id] = current + 1
	if def.trigger == ModifierDef.Trigger.ALWAYS:
		# 生命上限类词条需要立即补齐新增上限，避免出现未满血的新上限。
		if def.effect == ModifierDef.Effect.MAX_HEALTH:
			pass
	return 1

func has(def_id: String) -> bool:
	return stacks.has(def_id)

func stack_count(def_id: String) -> int:
	return int(stacks.get(def_id, 0))

func keyword_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id in stacks.keys():
		var def := _def(str(id))
		if def != null and def.is_keyword:
			out.append(str(id))
	return out

# --- 临时加成 ---

## 添加限时加成。同名来源会刷新而非叠加。
func add_temporary(stat: String, amount: float, duration: float, source_id: String) -> void:
	var list: Array = _temporary.get(stat, [])
	var replaced := false
	for entry in list:
		if entry["source"] == source_id:
			entry["amount"] = amount
			entry["time_left"] = duration
			replaced = true
			break
	if not replaced:
		list.append({"source": source_id, "amount": amount, "time_left": duration})
	_temporary[stat] = list

## 推进计时器。RunState 只在非暂停状态下调用。
func tick(delta: float) -> void:
	_clock += delta
	for stat in _temporary.keys():
		var list: Array = _temporary[stat]
		var kept: Array = []
		for entry in list:
			entry["time_left"] = float(entry["time_left"]) - delta
			if float(entry["time_left"]) > 0.0:
				kept.append(entry)
		if kept.is_empty():
			_temporary.erase(stat)
		else:
			_temporary[stat] = kept
	for id in _internal_cooldown.keys():
		var left := float(_internal_cooldown[id]) - delta
		if left <= 0.0:
			_internal_cooldown.erase(id)
		else:
			_internal_cooldown[id] = left

# --- 属性结算 ---

## 结算一个属性的最终值。
## additive 先相加，再乘各独立百分比组，得到 base 加 additive 后乘以各组系数。
func resolve(base: float, stat: String) -> float:
	var additive := 0.0
	var multiplier := 1.0
	for id in stacks.keys():
		var def := _def(str(id))
		if def == null or def.trigger != ModifierDef.Trigger.ALWAYS:
			continue
		var count := float(stacks[id])
		match def.effect:
			ModifierDef.Effect.STAT_ADD, ModifierDef.Effect.MAX_HEALTH:
				if def.stat == stat:
					additive += def.amount * count
			ModifierDef.Effect.STAT_MULTIPLY, ModifierDef.Effect.MOVE_SPEED:
				if def.stat == stat:
					multiplier *= pow(1.0 + def.amount, count)
			ModifierDef.Effect.CRIT_CHANCE:
				if stat == "crit_chance":
					additive += def.amount * count
			ModifierDef.Effect.DASH_COOLDOWN_SCALE:
				if stat == "dash_cooldown":
					multiplier *= pow(1.0 - def.amount, count)
			ModifierDef.Effect.DAMAGE_TAKEN:
				if stat == "damage_taken":
					additive += def.amount * count
			ModifierDef.Effect.RICOCHET_DAMAGE:
				if stat == "ricochet_damage":
					additive += def.amount * count
			ModifierDef.Effect.MARK_REWARD:
				if stat == "dash_cooldown_on_mark":
					additive += def.amount * count
			ModifierDef.Effect.DASH_ZONE:
				if stat == "dash_zone":
					additive += def.amount * count
			ModifierDef.Effect.REROLL_BONUS:
				if stat == "reroll_bonus":
					additive += def.amount * count
			ModifierDef.Effect.AUTO_AIM:
				if stat == "auto_aim_bonus":
					additive += def.amount * count
			ModifierDef.Effect.PICKUP_MAGNET:
				if stat == "pickup_magnet":
					additive += def.amount * count

	for entry in _temporary.get(stat, []):
		additive += float(entry["amount"])
		if stat == "damage_taken":
			pass

	var value := (base + additive) * multiplier
	last_resolved_stats[stat] = value
	return value

## 条件加成：目标带指定标签时额外生效的百分比。返回值用于独立乘算层。
func conditional_multiplier(target_tags: PackedStringArray) -> float:
	var multiplier := 1.0
	for id in stacks.keys():
		var def := _def(str(id))
		if def == null:
			continue
		if def.effect != ModifierDef.Effect.TAG_DAMAGE_BONUS:
			continue
		if def.required_tag.is_empty() or not target_tags.has(def.required_tag):
			continue
		multiplier *= pow(1.0 + def.amount, float(stacks[id]))
	return multiplier

## 关键字条目的具体数值查询，供武器与技能模块读取。
func value_of(def_id: String, fallback: float = 0.0) -> float:
	var def := _def(def_id)
	if def == null:
		return fallback
	var count := float(stacks.get(def_id, 0))
	if count <= 0.0:
		return fallback
	return def.amount * count

# --- 事件触发 ---

## 派发一次触发事件。source_id 用于触发链识别来源。
## allow_chain 为假的效果不会再次派发新事件。
## 返回实际触发的词条数量。
func fire_event(trigger: int, context: Dictionary, source_id: String, depth: int = 0) -> int:
	if depth > GameConfig.TRIGGER_CHAIN_MAX_DEPTH:
		_note_limit("触发链深度超过 %d，来源 %s" % [GameConfig.TRIGGER_CHAIN_MAX_DEPTH, source_id])
		return 0
	var fired := 0
	for id in stacks.keys():
		var def_id := str(id)
		var def := _def(def_id)
		if def == null or def.trigger != trigger:
			continue
		var count := int(stacks[id])
		if _internal_cooldown.has(def_id):
			continue
		if not _check_burst(source_id):
			continue
		var rng := _context_rng(context)
		if def.chance < 1.0 and rng.randf() > def.chance:
			continue
		if def.internal_cooldown > 0.0:
			_internal_cooldown[def_id] = def.internal_cooldown
		var applied := _apply_effect(def, count, context, def_id, source_id, depth)
		if applied:
			fired += 1
			_trigger_count += 1
	return fired

## 按标识触发单个词条，用于房间清除与冲刺结束这类明确时机。
func fire_specific(def_id: String, context: Dictionary, source_id: String) -> bool:
	var def := _def(def_id)
	if def == null or not stacks.has(def_id):
		return false
	if _internal_cooldown.has(def_id):
		return false
	if def.internal_cooldown > 0.0:
		_internal_cooldown[def_id] = def.internal_cooldown
	return _apply_effect(def, int(stacks[def_id]), context, def_id, source_id, 0)

## 应用一项触发效果。返回真表示本次触发被识别并生效。
## 依赖玩家实例的效果在缺少玩家时仍算识别成功，只是没有实际作用对象。
func _apply_effect(def: ModifierDef, count: int, context: Dictionary, def_id: String, source_id: String, depth: int) -> bool:
	var player: Node = context.get("player")
	var applied := false
	match def.effect:
		ModifierDef.Effect.HEAL:
			applied = true
			if player != null and player.has_method("heal"):
				player.heal(def.amount * float(count))
		ModifierDef.Effect.DASH_SHIELD:
			applied = true
			if player != null and player.has_method("grant_shield"):
				player.grant_shield(def.amount * float(count), def.duration)
		ModifierDef.Effect.DASH_ZONE:
			applied = true
			if player != null and player.has_method("spawn_dash_zone"):
				player.spawn_dash_zone(def.amount * float(count))
		ModifierDef.Effect.RICOCHET_DAMAGE:
			applied = true
			if player != null and player.has_method("note_ricochet"):
				player.note_ricochet()
		ModifierDef.Effect.MARK_REWARD:
			applied = true
			if player != null and player.has_method("spawn_motion_mark"):
				player.spawn_motion_mark()
		ModifierDef.Effect.DAMAGE_REDUCTION_BUFF:
			add_temporary("damage_taken", def.amount * float(count), maxf(0.4, def.duration), def_id)
			applied = true
		ModifierDef.Effect.CRIT_CHANCE, ModifierDef.Effect.STAT_ADD, ModifierDef.Effect.STAT_MULTIPLY:
			if not def.stat.is_empty():
				add_temporary(def.stat, def.amount * float(count), maxf(0.4, def.duration), def_id)
				applied = true
		_:
			# 静态词条在 resolve 中已经生效，事件本身不产生额外效果。
			applied = false
	if applied and def.allow_chain and player != null:
		# 允许连锁的词条才继续派发新事件，深度受上限保护。
		fire_event(ModifierDef.Trigger.ON_HIT, context, def_id, depth + 1)
	return applied

# --- 触发链配额 ---

func _check_burst(source_id: String) -> bool:
	var key := source_id
	if not _burst_count.has(key):
		_burst_count[key] = 1
		return true
	var total := int(_burst_count[key]) + 1
	_burst_count[key] = total
	if total > GameConfig.TRIGGER_BURST_LIMIT_PER_SECOND:
		_note_limit("来源 %s 的每秒触发次数超过 %d" % [source_id, GameConfig.TRIGGER_BURST_LIMIT_PER_SECOND])
		return false
	return true

## 每秒重置一次突发计数。
func reset_burst_window() -> void:
	_burst_count.clear()

## 本秒窗口内各来源的触发次数，供自检与调试读取。
func burst_counts() -> Dictionary:
	return _burst_count.duplicate()

## 已成功触发的词条次数，供自检读取。
func trigger_count() -> int:
	return _trigger_count

func _note_limit(message: String) -> void:
	if chain_limit_reports.size() < 16 and not chain_limit_reports.has(message):
		chain_limit_reports.append(message)
		push_warning("[ModifierEngine] " + message)

func _context_rng(context: Dictionary) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = context.get("rng")
	if rng == null:
		rng = RunState.rng if RunState != null else null
	return rng

func _def(def_id: String) -> ModifierDef:
	if GameData == null:
		return null
	return GameData.get_modifier(def_id)

## 供调试面板显示当前词条构成。
func describe() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for id in stacks.keys():
		var def := _def(str(id))
		var name_text := def.display_name if def != null else str(id)
		parts.append("%s x%d" % [name_text, int(stacks[id])])
	if parts.is_empty():
		return "无词条"
	return " ".join(parts)
