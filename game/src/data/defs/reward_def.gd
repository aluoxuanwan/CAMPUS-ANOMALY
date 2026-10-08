class_name RewardDef
extends DefBase
## 奖励定义。战后从三个奖励中选择一项，分别偏攻击、机动或防御，并允许有限重抽。
##
## 依据 docs/research/玩法机制与校园设计.md 第 3 节。

enum Kind { MODIFIER, WEAPON, ABILITY, HEAL, CURRENCY }

@export var kind: int = Kind.MODIFIER
## 授予的被动词条标识，仅 MODIFIER 使用。
@export var modifier_id: String = ""
## 授予的武器标识，仅 WEAPON 使用。
@export var weapon_id: String = ""
## 授予的技能标识，仅 ABILITY 使用。
@export var ability_id: String = ""
## 恢复生命值，仅 HEAL 使用。
@export var heal_amount: float = 0.0
## 授予货币，仅 CURRENCY 使用。
@export var currency: int = 0
## 奖励池分组。
@export var pool: String = "attack"
## 抽取权重。
@export var weight: float = 1.0
## 一次性奖励在本次局内是否已使用。
@export var once_per_run: bool = false
