extends Node
## 局内状态：当前一局的参数、成长与统计。
##
## 依据 docs/research/技术与动画方案.md 第 3 节与第 10 节：
## 局内状态与永久进度分开保存；词条定义共享，运行时数值保存在独立实例中。
## 所有战斗计时使用本节点推进的局内时钟，暂停时不增长。

## 原型阶段的基准属性。
const BASE_MAX_HEALTH := 100.0
const BASE_MOVE_SPEED := 250.0
const BASE_DASH_COOLDOWN := GameConfig.DASH_COOLDOWN_SECONDS
const BASE_INSIGHT := 0

var rng := RandomNumberGenerator.new()
var seed_value: int = 0

var health: float = BASE_MAX_HEALTH
var shield: float = 0.0
var shield_time_left: float = 0.0
var insight: int = BASE_INSIGHT

var modifiers := ModifierEngine.new()

var elapsed_seconds: float = 0.0
var kills: int = 0
var rooms_cleared: int = 0
var damage_dealt: int = 0
var damage_taken: int = 0
var rerolls_left: int = GameConfig.REWARD_REROLL_BASE

var weapon_ids: PackedStringArray = PackedStringArray()
var ability_ids: PackedStringArray = PackedStringArray()
var active_ability_index: int = 0

## 本局内的叙事标签，用于失败后的 NPC 回应。
var run_tags: PackedStringArray = PackedStringArray()

## 局内是否仍在进行。
var is_active: bool = false
var _settled: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

## 开始新的一局。
func begin_run(seed_override: int = 0) -> void:
	if seed_override != 0:
		seed_value = seed_override
	else:
		seed_value = int(Time.get_unix_time_from_system()) ^ (randi() & 0xFFFF)
	rng.seed = seed_value
	modifiers.clear()
	health = BASE_MAX_HEALTH
	shield = 0.0
	shield_time_left = 0.0
	insight = BASE_INSIGHT
	elapsed_seconds = 0.0
	kills = 0
	rooms_cleared = 0
	damage_dealt = 0
	damage_taken = 0
	rerolls_left = GameConfig.REWARD_REROLL_BASE
	run_tags.clear()
	is_active = true
	_settled = false
	weapon_ids = PackedStringArray(["chalk_rapid", "basketball_boomerang", "ruler_sweep"])
	ability_ids = _default_abilities()
	active_ability_index = 0
	GameEvents.run_started.emit(seed_value)

func _default_abilities() -> PackedStringArray:
	var unlocked := SaveService.unlocked_abilities()
	if unlocked.size() >= 4:
		return unlocked
	# 原型始终提供四项用于对照，存档解锁在 Demo 阶段接管。
	return PackedStringArray([
		"club_sports_spin",
		"club_robotics_turret",
		"club_drama_decoy",
		"club_photo_flash",
	])

## 受暂停影响的时间推进。词条计时与护盾倒计时都走这里。
func tick_timers(delta: float) -> void:
	if not is_active:
		return
	elapsed_seconds += delta
	modifiers.set_clock(elapsed_seconds)
	modifiers.tick(delta)
	if shield_time_left > 0.0:
		shield_time_left -= delta
		if shield_time_left <= 0.0:
			shield_time_left = 0.0
			shield = 0.0

# --- 属性查询 ---

func max_health() -> float:
	return maxf(1.0, modifiers.resolve(BASE_MAX_HEALTH, "max_health"))

func move_speed() -> float:
	return maxf(20.0, modifiers.resolve(BASE_MOVE_SPEED, "move_speed"))

func dash_cooldown() -> float:
	return maxf(0.15, modifiers.resolve(BASE_DASH_COOLDOWN, "dash_cooldown"))

func crit_chance() -> float:
	return clampf(modifiers.resolve(0.0, "crit_chance"), 0.0, 0.95)

func damage_taken_multiplier() -> float:
	return clampf(1.0 - modifiers.resolve(0.0, "damage_taken"), 0.15, 1.0)

func reroll_bonus() -> int:
	return int(round(modifiers.resolve(0.0, "reroll_bonus")))

# --- 生命与资源 ---

func heal(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var before := health
	health = minf(max_health(), health + amount)
	var gained := health - before
	return gained

## 结算一次对玩家的伤害。返回实际扣除值。
func apply_player_damage(raw_amount: float) -> int:
	if not is_active:
		return 0
	if shield > 0.0:
		var absorbed := minf(shield, raw_amount)
		shield -= absorbed
		raw_amount -= absorbed
		if shield <= 0.0:
			shield = 0.0
			shield_time_left = 0.0
		if raw_amount <= 0.0:
			return int(round(absorbed))
	var final_amount := maxf(1.0, raw_amount * damage_taken_multiplier())
	var dealt := int(round(final_amount))
	health = maxf(0.0, health - final_amount)
	damage_taken += dealt
	GameEvents.player_damaged.emit(dealt, int(ceil(health)))
	modifiers.fire_event(ModifierDef.Trigger.ON_DAMAGED, {"player": GameFlow.player}, "player_damaged")
	if health <= 0.0:
		fail_run()
	return dealt

func add_shield(amount: float, duration: float) -> void:
	shield = maxf(shield, amount)
	shield_time_left = maxf(shield_time_left, duration)

func add_insight(amount: int) -> void:
	insight = maxi(0, insight + amount)
	GameEvents.insight_changed.emit(insight)

func spend_insight(amount: int) -> bool:
	if insight < amount:
		return false
	add_insight(-amount)
	return true

# --- 词条 ---

## 授予词条。返回实际获得的层数。
func grant_modifier(def_id: String) -> int:
	var gained := modifiers.grant(def_id)
	if gained > 0:
		var def := GameData.get_modifier(def_id)
		if def != null and def.effect == ModifierDef.Effect.MAX_HEALTH:
			health = minf(max_health(), health + def.amount)
	return gained

func add_run_tag(tag: String) -> void:
	if not run_tags.has(tag):
		run_tags.append(tag)
		SaveService.add_narrative_tag(tag)

# --- 结算 ---

func note_kill() -> void:
	kills += 1
	modifiers.fire_event(ModifierDef.Trigger.ON_KILL, {"player": GameFlow.player}, "on_kill")

func note_room_cleared() -> void:
	rooms_cleared += 1
	modifiers.fire_event(ModifierDef.Trigger.ON_ROOM_CLEAR, {"player": GameFlow.player}, "on_room_clear")
	add_insight(1 + int(rooms_cleared / 3.0))

func fail_run() -> void:
	if not is_active:
		return
	is_active = false
	GameEvents.run_failed.emit(rooms_cleared, elapsed_seconds)

func complete_run() -> void:
	if not is_active:
		return
	is_active = false
	GameEvents.run_victory.emit(rooms_cleared, elapsed_seconds)

## 结算本局的社团点数。失败仍获得用于解锁新选项的社团点数。
func settle_rewards(victory: bool) -> int:
	if _settled:
		return 0
	_settled = true
	var base_points := rooms_cleared * 2 + int(kills / 4.0)
	if victory:
		base_points += 15
	var total := SaveService.add_club_points(base_points)
	SaveService.record_run(rooms_cleared, elapsed_seconds, kills)
	GameEvents.run_reward_granted.emit(base_points, total)
	return base_points
