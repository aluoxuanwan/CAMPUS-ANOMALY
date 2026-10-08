class_name DamageCalc
extends RefCounted
## 伤害分层结算。
##
## 结算顺序：基础值加固定增加值，乘同组加成，乘独立层倍率，
## 随后处理防御、暴击、最低伤害规则。
## 依据 docs/research/技术与动画方案.md 第 4 节，首轮保留两至三个乘算层。

## 加成分组。同组相加，跨组相乘。
const GROUP_WEAPON := "weapon"
const GROUP_CLUB := "club"
const GROUP_SITUATIONAL := "situational"

var base: float = 0.0
## 按组保存的固定增加值。
var flat_bonus: Dictionary = {}
## 按组保存的百分比加成，0.15 表示该组增加 15%。
var group_bonus: Dictionary = {}
## 独立层倍率，键为来源标识，值为倍率。
var independent_multipliers: Dictionary = {}
## 暴击倍率，1.0 表示无暴击加成。
var crit_multiplier: float = 1.0
var is_crit: bool = false
## 目标的固定减伤。
var flat_defense: float = 0.0
## 目标的百分比减伤，0.2 表示减少 20%。
var defense_reduction: float = 0.0
## 全局倍率，用于难度或阶段修正。
var global_multiplier: float = 1.0

const MINIMUM_DAMAGE := 1

func add_flat(group: String, value: float) -> DamageCalc:
	flat_bonus[group] = float(flat_bonus.get(group, 0.0)) + value
	return self

func add_group_bonus(group: String, value: float) -> DamageCalc:
	group_bonus[group] = float(group_bonus.get(group, 0.0)) + value
	return self

func add_independent(source_id: String, value: float) -> DamageCalc:
	independent_multipliers[source_id] = float(independent_multipliers.get(source_id, 1.0)) * value
	return self

func set_crit(chance: float, multiplier: float, roll: float) -> DamageCalc:
	is_crit = roll < chance
	crit_multiplier = multiplier if is_crit else 1.0
	return self

## 结算为整数伤害，并给出可读的分解，供 UI 预览与调试使用。
func resolve() -> Dictionary:
	var flat_total := base
	for key in flat_bonus.keys():
		flat_total += float(flat_bonus[key])

	var after_group := flat_total
	for key in group_bonus.keys():
		after_group *= 1.0 + float(group_bonus[key])

	var product := after_group
	var independent_product := 1.0
	for key in independent_multipliers.keys():
		independent_product *= float(independent_multipliers[key])
	product *= independent_product

	product *= crit_multiplier
	product *= global_multiplier

	var defended := (product - flat_defense) * (1.0 - clampf(defense_reduction, 0.0, 0.95))
	var final_amount := int(maxf(float(MINIMUM_DAMAGE), floorf(defended + 0.0001)))

	return {
		"amount": final_amount,
		"base": base,
		"flat_total": flat_total,
		"after_group": after_group,
		"independent_product": independent_product,
		"before_defense": product,
		"after_defense": defended,
		"is_crit": is_crit,
	}

## 用同一套规则生成 UI 预览文本，避免界面与结算使用不同公式。
static func preview_text(ctx: DamageCalc) -> String:
	var r := ctx.resolve()
	var parts: Array[String] = ["基础 %d" % int(round(ctx.base))]
	if not ctx.flat_bonus.is_empty():
		parts.append("固定 +%d" % int(round(r["flat_total"] - ctx.base)))
	for key in ctx.group_bonus.keys():
		parts.append("%s +%d%%" % [key, int(round(float(ctx.group_bonus[key]) * 100.0))])
	if absf(r["independent_product"] - 1.0) > 0.0001:
		parts.append("独立 x%.2f" % r["independent_product"])
	if ctx.is_crit:
		parts.append("暴击 x%.2f" % ctx.crit_multiplier)
	if ctx.flat_defense > 0.0 or ctx.defense_reduction > 0.0:
		parts.append("减免后 %d" % r["amount"])
	parts.append("合计 %d" % r["amount"])
	return " ".join(parts)
