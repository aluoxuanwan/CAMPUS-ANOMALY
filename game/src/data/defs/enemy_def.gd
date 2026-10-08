class_name EnemyDef
extends DefBase
## 敌人定义。六个家族各一个原型变体，正式版每家族扩展至三个变体。
##
## 依据 docs/research/玩法机制与校园设计.md 第 4 节。

## 行为家族。
enum Family { CHASER, SHOOTER, SHIELD, ZONE, SUMMONER, DASHER }

const FAMILY_BY_ID := {
	"chaser": Family.CHASER,
	"shooter": Family.SHOOTER,
	"shield": Family.SHIELD,
	"zone": Family.ZONE,
	"summoner": Family.SUMMONER,
	"dasher": Family.DASHER,
}

## JSON 使用 family_id 字符串。
@export var family_id: String = "chaser"
@export var family: int = Family.CHASER
## 最大生命。
@export var max_health: float = 40.0
## 移动速度。
@export var move_speed: float = 120.0
## 接触伤害，0 表示不造成接触伤害。
@export var contact_damage: float = 0.0
## 攻击伤害。
@export var attack_damage: float = 8.0
## 首次攻击前的前摇时间。
@export var attack_windup: float = 0.45
## 攻击冷却。
@export var attack_cooldown: float = 1.6
## 攻击作用距离。
@export var attack_range: float = 300.0
## 近身距离，低于该值后停止接近。
@export var preferred_distance: float = 70.0
## 碰撞半径。
@export var body_radius: float = 15.0
## 是否固定不动。
@export var stationary: bool = false
## 固定减伤。
@export var flat_defense: float = 0.0
## 百分比减伤，盾卫使用。
@export var defense_reduction: float = 0.0
## 正面减伤比例，仅盾卫在正面判定时使用。
@export var front_shield_reduction: float = 0.0
## 视觉颜色。
@export var color: Color = Color(0.9, 0.4, 0.4)
## 房间威胁预算占用。
@export var threat: int = 1
## 提示文本，用于调试与图鉴。
@export var telegraph: String = ""

## 在加载后把 family_id 解析为枚举值。
func resolve_family() -> void:
	family = int(FAMILY_BY_ID.get(family_id, Family.CHASER))
