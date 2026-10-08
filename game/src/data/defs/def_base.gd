class_name DefBase
extends Resource
## 全部数据定义的基类。
##
## 依据 docs/research/技术与动画方案.md 第 3 节：
## 每项定义有稳定 ID、可显示名字、参数、标签与表现引用。
## 表现文件路径变化不得改变 ID，ID 用于存档与版本迁移。

## 稳定标识，仅使用 ASCII 小写与下划线。
@export var id: String = ""
## 界面显示名。
@export var display_name: String = ""
## 图鉴与提示用的一句话说明。
@export var description: String = ""
## 分类标签，用于奖励池筛选与协同判定。
@export var tags: PackedStringArray = PackedStringArray()

func is_valid() -> bool:
	return not id.is_empty()

func has_tag(tag: String) -> bool:
	return tags.has(tag)

func to_debug_string() -> String:
	return "%s(%s)" % [display_name, id]
