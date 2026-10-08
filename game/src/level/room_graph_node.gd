class_name RoomGraphNode
extends RefCounted
## 房间图节点。一个节点对应一个房间模板与一条路线位置。

var id: int = 0
var template_id: String = ""
var kind: int = GameConfig.RoomKind.COMBAT
## 后继节点编号。使用有类型的数组，避免赋值时类型不匹配。
var next: Array[int] = Array([], TYPE_INT, "", null)
var previous: Array[int] = Array([], TYPE_INT, "", null)
## 课程标签，决定奖励池倾向。
var course_tags: PackedStringArray = PackedStringArray()
## 难度倍率，沿路线递增。
var difficulty: float = 1.0
## 已生成的敌人投放计划。
var encounter: Array = []
var cleared: bool = false
## 节点在分支时的可读位置，仅用于界面绘制。
var lane: int = 0

func display_kind() -> String:
	match kind:
		GameConfig.RoomKind.COMBAT:
			return "战斗"
		GameConfig.RoomKind.ELITE:
			return "精英"
		GameConfig.RoomKind.SHOP:
			return "商店"
		GameConfig.RoomKind.REST:
			return "休息"
		GameConfig.RoomKind.BOSS:
			return "Boss"
		GameConfig.RoomKind.START:
			return "起点"
	return "未知"
