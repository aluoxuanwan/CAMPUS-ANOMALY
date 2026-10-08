class_name ModifierDef
extends DefBase
## 被动词条定义，由触发事件与效果两部分组成。
##
## 依据 docs/research/技术与动画方案.md 第 4 节：
## 技能触发用事件类型与来源标识管理，触发产生的新攻击需要标记是否允许再次触发。
## 单次事件链设置深度与次数上限，达到上限时记录原因。

## 触发事件类型。
enum Trigger {
	ALWAYS,
	ON_HIT,
	ON_CRIT,
	ON_KILL,
	ON_DASH_END,
	ON_PICKUP,
	ON_DAMAGED,
	ON_ROOM_CLEAR,
	ON_ATTACK,
	ON_STATUS_CONSUMED,
}

## 效果类型。原型阶段只实现此处列出的类型。
enum Effect {
	STAT_ADD,
	STAT_MULTIPLY,
	TAG_DAMAGE_BONUS,
	CRIT_CHANCE,
	DASH_COOLDOWN_SCALE,
	DASH_ZONE,
	DASH_SHIELD,
	HEAL,
	MAX_HEALTH,
	DAMAGE_TAKEN,
	MOVE_SPEED,
	RICOCHET_DAMAGE,
	MARK_REWARD,
	DAMAGE_REDUCTION_BUFF,
	REROLL_BONUS,
	AUTO_AIM,
	PICKUP_MAGNET,
}

@export var trigger: int = Trigger.ALWAYS
@export var effect: int = Effect.STAT_ADD
## 受影响的属性标识。效果类型决定可用的标识集合。
@export var stat: String = ""
## 效果数值。
@export var amount: float = 0.0
## 叠加层数上限。
@export var max_stacks: int = 1
## 触发后是否允许继续触发新攻击。
@export var allow_chain: bool = false
## 触发概率，1.0 表示必定触发。
@export var chance: float = 1.0
## 触发内部冷却，单位为秒。
@export var internal_cooldown: float = 0.0
## 触发后效果的持续时间，0 表示瞬时或永久。
@export var duration: float = 0.0
## 条件加成所需的标签。目标带该标签时效果生效。
@export var required_tag: String = ""
## 奖励池分组，attack、mobility 或 defense。
@export var pool: String = "attack"
## 稀有度权重，数值越大越常见。
@export var weight: float = 1.0
## 是否为词条组合中的关键词条。
@export var is_keyword: bool = false
