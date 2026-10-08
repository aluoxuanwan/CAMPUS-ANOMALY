class_name WeaponDef
extends DefBase
## 武器定义。原型阶段实现两个变体：粉笔连射与回旋篮球。
##
## 攻击结算至少包含前摇、有效窗口与后摇三个时间段，
## 见 docs/research/技术与动画方案.md 第 4 节。

enum Delivery { MELEE, PROJECTILE }

const DELIVERY_BY_ID := {
	"melee": Delivery.MELEE,
	"projectile": Delivery.PROJECTILE,
}

## 攻击方式。JSON 使用 delivery_id 字符串。
@export var delivery_id: String = "projectile"
@export var delivery: int = Delivery.PROJECTILE
## 前摇，动作发生前的提示时间。
@export var windup: float = 0.08
## 有效窗口，实际造成命中的时间。
@export var active_window: float = 0.06
## 后摇，决定连续攻击与取消的边界。
@export var recovery: float = 0.16
## 单次攻击的基础伤害。
@export var base_damage: float = 8.0
## 近战有效半径，仅近战使用。
@export var melee_radius: float = 86.0
## 近战有效张角，单位为度，仅近战使用。
@export var melee_arc_degrees: float = 105.0
## 投射物速度。
@export var projectile_speed: float = 620.0
## 投射物寿命，单位为秒。
@export var projectile_lifetime: float = 0.55
## 投射物最大飞行距离，超出后回收。
@export var projectile_max_distance: float = 320.0
## 投射物碰撞半径。
@export var projectile_radius: float = 7.0
## 单次发射的投射物数量。
@export var projectiles_per_shot: int = 1
## 散射角度，单位为度。
@export var spread_degrees: float = 0.0
## 是否回旋：到达最大距离后返回发射者。
@export var boomerang: bool = false
## 回旋回头后的减速系数。
@export var return_speed_scale: float = 0.85
## 是否在撞墙后反弹。
@export var ricochet: bool = false
## 撞墙反弹次数上限。
@export var ricochet_max_bounces: int = 2
## 命中是否附加异常层。
@export var applies_status: String = ""
## 附加层数。
@export var status_layers: int = 1
## 击退强度。
@export var knockback: float = 120.0
## 暴击率。
@export var crit_chance: float = 0.08
## 暴击倍率。
@export var crit_multiplier: float = 1.8
## 弹药容量，0 表示不消耗弹药。
@export var magazine: int = 0
## 装填时间，单位为秒。
@export var reload_time: float = 0.0
## 单发消耗弹药数量。
@export var ammo_cost: int = 1
## 命中停顿档位，true 使用重档。
@export var heavy_impact: bool = false
## 是否允许在冲刺后立即取消后摇。
@export var dash_cancel_recovery: bool = true

## 一次完整攻击周期的时长。
func cycle_time() -> float:
	return windup + active_window + recovery

## 在加载后把 delivery_id 解析为枚举值。
func resolve_delivery() -> void:
	delivery = int(DELIVERY_BY_ID.get(delivery_id, Delivery.PROJECTILE))

## 每秒理论攻击次数，供平衡与调试显示。
func attacks_per_second() -> float:
	var cycle := cycle_time()
	if cycle <= 0.0:
		return 0.0
	return 1.0 / cycle
