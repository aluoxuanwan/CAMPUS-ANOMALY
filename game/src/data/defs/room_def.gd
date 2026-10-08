class_name RoomDef
extends DefBase
## 房间模板定义，由 8 个灰盒模板组成一个区域。
##
## 依据 docs/research/技术与动画方案.md 第 5 节：
## 先生成房间图并检查连通，再给节点填入人工布局模板。

## 房间类型。
@export var kind: int = 0 # GameConfig.RoomKind
## 房间尺寸，单位为格。
@export var grid_size: Vector2i = Vector2i(24, 14)
## 单格像素尺寸。
@export var tile_size: int = 48
## 墙体格坐标，格式为 "x,y"。
@export var walls: PackedStringArray = PackedStringArray()
## 掩体格坐标与初始状态，格式为 "x,y,active"。
@export var covers: PackedStringArray = PackedStringArray()
## 玩家出生格。
@export var spawn_player: Vector2i = Vector2i(2, 7)
## 敌人出生格与家族标识，格式为 "x,y,family"。
@export var spawn_enemies: PackedStringArray = PackedStringArray()
## 波次数量。
@export var waves: int = 1
## 威胁预算上限。
@export var threat_budget: int = 6
## 该模板是否允许高控制敌人。关掉可保证连续远程与封路时有移动解法。
@export var allow_high_control: bool = true
## 铃声阶段为课堂时的掩体状态覆盖，格式为 "x,y,active"。
@export var class_phase_covers: PackedStringArray = PackedStringArray()
## 铃声阶段为课间时的掩体状态覆盖，格式为 "x,y,active"。
@export var break_phase_covers: PackedStringArray = PackedStringArray()
## 该模板参与的课表课程标签。
@export var course_tags: PackedStringArray = PackedStringArray()

func pixel_size() -> Vector2:
	return Vector2(grid_size.x * tile_size, grid_size.y * tile_size)
