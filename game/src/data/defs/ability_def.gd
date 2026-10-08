class_name AbilityDef
extends DefBase
## 主动技能定义。原型阶段实现六项，用于对照控制、召唤与范围能力是否容易理解。
##
## 依据 docs/research/玩法机制与校园设计.md 第 3 节。
## JSON 中使用 kind_id 字符串，避免枚举数字在数据文件里难以核对。

enum Kind { DASH_STRIKE, DEPLOY_TURRET, DECOY, FLASH, ORBITAL, ZONE }

const KIND_BY_ID := {
	"dash_strike": Kind.DASH_STRIKE,
	"deploy_turret": Kind.DEPLOY_TURRET,
	"decoy": Kind.DECOY,
	"flash": Kind.FLASH,
	"orbital": Kind.ORBITAL,
	"zone": Kind.ZONE,
}

@export var kind_id: String = "dash_strike"
@export var kind: int = Kind.DASH_STRIKE
## 冷却时间，单位为秒。
@export var cooldown: float = 10.0
## 效果持续时间，单位为秒。
@export var duration: float = 1.0
## 效果半径或作用距离。
@export var radius: float = 120.0
## 单次效果的伤害，0 表示不造成伤害。
@export var damage: float = 0.0
## 持续伤害区的触发间隔，单位为秒。
@export var tick_interval: float = 0.5
## 单次效果的击退强度。
@export var knockback: float = 120.0
## 眩晕时长，单位为秒。
@export var stun_seconds: float = 0.0
## 使用瞬间是否获得无敌帧。
@export var grants_invulnerability: bool = false
## 使用瞬间的移动加成，按基础移动速度的比例计算。
@export var move_speed_bonus: float = 0.0
## 冷却缩短下限，避免叠加后趋近于零。
@export var min_cooldown: float = 1.5
## 表现用颜色。
@export var color: Color = Color(0.6, 0.8, 1.0)

## 在加载后把 kind_id 解析为枚举值。
func resolve_kind() -> void:
	kind = int(KIND_BY_ID.get(kind_id, Kind.DASH_STRIKE))
