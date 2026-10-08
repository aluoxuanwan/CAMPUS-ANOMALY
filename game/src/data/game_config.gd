extends Node
## 全局常量：碰撞层、阵营、阶段枚举与原型调参起点。
##
## 调参数值来自 docs/research/技术与动画方案.md 第 4 节与第 8 节，
## 属于测试起点，不属于已校准的手感结论。

# --- 物理层序号。layer_names 在 project.godot 中同名保存。 ---

const LAYER_WORLD := 1
const LAYER_PLAYER_BODY := 2
const LAYER_ENEMY_BODY := 3
const LAYER_PLAYER_HURTBOX := 4
const LAYER_ENEMY_HURTBOX := 5
const LAYER_PLAYER_ATTACK := 6
const LAYER_ENEMY_ATTACK := 7
const LAYER_PLAYER_PROJECTILE := 8
const LAYER_ENEMY_PROJECTILE := 9
const LAYER_PICKUP := 10
const LAYER_COVER := 11
const LAYER_COVER_HURTBOX := 12

## 把层序号转换为位掩码。
static func bit(layer_number: int) -> int:
	return 1 << (layer_number - 1)

static func mask(layer_numbers: Array) -> int:
	var total := 0
	for n in layer_numbers:
		total |= bit(n)
	return total

# --- 阵营 ---

enum Faction { PLAYER, ENEMY, NEUTRAL }

# --- 攻击阶段。表现层与规则层共用，顺序固定。 ---

enum AttackPhase { IDLE, WINDUP, ACTIVE, RECOVERY }

# --- 铃声阶段。普通房间在课堂与课间之间切换。 ---

enum BellPhase { CLASS, BREAK }

# --- 房间类型 ---

enum RoomKind { COMBAT, ELITE, SHOP, REST, BOSS, START }

# --- 伤害来源标签。用于触发链来源标识与表现选择。 ---

enum DamageSource { WEAPON, PROJECTILE, MELEE, ABILITY, STATUS, ENVIRONMENT }

# --- 原型调参起点 ---

const DASH_INVULN_SECONDS := 0.14
const DASH_COOLDOWN_SECONDS := 0.70
const DASH_DISTANCE := 190.0
const DASH_DURATION := 0.16
const INPUT_BUFFER_SECONDS := 0.10
const HITSTOP_LIGHT_MS := 28.0
const HITSTOP_HEAVY_MS := 55.0
const HITSTOP_MIN_INTERVAL_MS := 90.0
const CAMERA_SHAKE_LIGHT := 3.0
const CAMERA_SHAKE_HEAVY := 7.0

## 单次事件链允许的最大触发深度。
const TRIGGER_CHAIN_MAX_DEPTH := 3

## 单个房间内同一来源触发的每秒上限，防止弹射与复制形成无限调用。
const TRIGGER_BURST_LIMIT_PER_SECOND := 24

## 房间结束后进入奖励界面的延迟。
const ROOM_CLEAR_DELAY := 0.65

## 精英敌人与 Boss 的额外表现延迟。
const BOSS_PHASE_TRANSITION_SECONDS := 1.1

const REWARD_REROLL_BASE := 1
const INSIGHT_CURRENCY_NAME := "社团点数"

# --- 自动瞄准。原型阶段供手柄与后续移动端复用。 ---

const AUTOAIM_MAX_RANGE := 520.0
const AUTOAIM_STICKY_SECONDS := 0.45
const AUTOAIM_SWITCH_SCORE_MARGIN := 1.18
