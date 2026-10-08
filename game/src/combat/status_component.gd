class_name StatusComponent
extends Node
## 状态层容器。挂在敌人身上，管理沾墨、解析与眩晕这类可叠层效果。
##
## 层数用于条件加成判定，眩晕用于打断前摇。

## 状态变化时发出，供表现层做提示。
signal status_changed(status_id: String, layers: int)

## status_id -> 层数
var layers: Dictionary = {}
## status_id -> 剩余时间，负数表示永久
var durations: Dictionary = {}

## 添加层数。duration 小于等于 0 表示本房间内永久。
func add(status_id: String, amount: int, duration: float = 0.0) -> int:
	var current := int(layers.get(status_id, 0)) + amount
	layers[status_id] = current
	var remaining := float(durations.get(status_id, -1.0))
	if duration > 0.0:
		remaining = maxf(remaining, duration)
	durations[status_id] = remaining
	status_changed.emit(status_id, current)
	return current

func consume(status_id: String, amount: int = 1) -> int:
	var current := int(layers.get(status_id, 0))
	if current <= 0:
		return 0
	var taken := mini(current, amount)
	var left := current - taken
	if left <= 0:
		layers.erase(status_id)
		durations.erase(status_id)
	else:
		layers[status_id] = left
	status_changed.emit(status_id, left)
	return taken

func count(status_id: String) -> int:
	return int(layers.get(status_id, 0))

func has(status_id: String) -> bool:
	return count(status_id) > 0

## 返回当前全部状态标签，供目标条件加成使用。
func tag_list() -> PackedStringArray:
	var out := PackedStringArray()
	for id in layers.keys():
		if int(layers[id]) > 0:
			out.append(str(id))
	return out

func is_stunned() -> bool:
	return count("stunned") > 0

func stun(seconds: float) -> void:
	# 眩晕不做叠层，取较长的一次。
	var existing := float(durations.get("stunned", 0.0))
	add("stunned", 1, 0.0)
	durations["stunned"] = maxf(existing, seconds)

func tick(delta: float) -> void:
	var expired: Array[String] = []
	for id in durations.keys():
		var remaining := float(durations[id])
		if remaining < 0.0:
			continue
		remaining -= delta
		durations[id] = remaining
		if remaining <= 0.0:
			expired.append(str(id))
	for id in expired:
		layers.erase(id)
		durations.erase(id)
		status_changed.emit(id, 0)

func clear_all() -> void:
	layers.clear()
	durations.clear()

func describe() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for id in layers.keys():
		parts.append("%s x%d" % [id, int(layers[id])])
	return " ".join(parts)
