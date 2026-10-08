extends Node
## 存档服务：永久进度、设置与叙事标签。
##
## 依据 docs/research/技术与动画方案.md 第 10 节：
## 采用临时文件写入后替换正式文件，保留一个最近可用备份，并为版本升级写迁移规则。
## 跨平台云存档与平台内购不在此层处理。

var SAVE_PATH := "user://save_v1.json"
var BACKUP_PATH := "user://save_v1.backup.json"
const CURRENT_VERSION := 1

var data: Dictionary = {}
## 上一次读写是否成功，供自检与设置界面显示。
var last_error: String = ""

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--self-test" or arg == "--capture":
			SAVE_PATH = "user://qa/save_v1.json"
			BACKUP_PATH = "user://qa/save_v1.backup.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_PATH.get_base_dir()))
	load_or_create()

func default_data() -> Dictionary:
	return {
		"version": CURRENT_VERSION,
		"club_points": 0,
		"settings": {
			"master_volume": 0.8,
			"screen_shake": 1.0,
			"show_damage_numbers": true,
			"hitstop_scale": 1.0,
			"reduced_flash": false,
		},
		"unlocks": {
			"weapons": ["chalk_rapid", "basketball_boomerang"],
			"abilities": ["club_sports_spin", "club_robotics_turret"],
			"modifiers": [],
		},
		"narrative_tags": [],
		"records": {
			"best_rooms_cleared": 0,
			"total_runs": 0,
			"total_kills": 0,
			"best_elapsed_seconds": 0.0,
		},
	}

func load_or_create() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var loaded := _read_json(SAVE_PATH)
		if not loaded.is_empty():
			data = _migrate(loaded)
			return
		# 正式文件损坏时尝试备份。
		if FileAccess.file_exists(BACKUP_PATH):
			var backup := _read_json(BACKUP_PATH)
			if not backup.is_empty():
				data = _migrate(backup)
				last_error = "正式存档读取失败，已从备份恢复"
				save()
				return
	data = default_data()
	save()

func _read_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {}
	var parsed: Variant = parser.data
	if not (parsed is Dictionary):
		return {}
	return parsed

## 版本迁移。当前只有版本 1，保留结构以便后续升级。
func _migrate(source: Dictionary) -> Dictionary:
	var version := int(source.get("version", 0))
	var merged := default_data()
	for key in source.keys():
		merged[key] = source[key]
	# 补齐后来新增的设置字段，避免旧存档缺键。
	var default_settings: Dictionary = default_data()["settings"]
	var settings: Dictionary = merged.get("settings", {})
	for key in default_settings.keys():
		if not settings.has(key):
			settings[key] = default_settings[key]
	merged["settings"] = settings
	merged["version"] = CURRENT_VERSION
	if version != CURRENT_VERSION:
		last_error = "存档已从版本 %d 迁移到 %d" % [version, CURRENT_VERSION]
	return merged

func save() -> bool:
	last_error = ""
	if FileAccess.file_exists(SAVE_PATH):
		var existing := FileAccess.get_file_as_string(SAVE_PATH)
		if not _read_json(SAVE_PATH).is_empty():
			_write_text(BACKUP_PATH, existing)
	var ok := _write_text(SAVE_PATH, JSON.stringify(data, "\t"))
	if not ok:
		last_error = "存档写入失败"
	return ok

func _write_text(path: String, text: String) -> bool:
	# 先写临时文件，再替换正式文件。
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return false
	if dir.file_exists(path.get_file()):
		dir.remove(path.get_file())
	return dir.rename(temp_path.get_file(), path.get_file()) == OK

# --- 设置访问 ---

func get_setting(key: String, fallback: Variant = null) -> Variant:
	var settings: Dictionary = data.get("settings", {})
	return settings.get(key, fallback)

func set_setting(key: String, value: Variant) -> void:
	var settings: Dictionary = data.get("settings", {})
	settings[key] = value
	data["settings"] = settings
	save()

# --- 永久进度 ---

func add_club_points(amount: int) -> int:
	var total := int(data.get("club_points", 0)) + amount
	data["club_points"] = total
	save()
	return total

func unlocked_weapons() -> PackedStringArray:
	return _unlocked("weapons")

func unlocked_abilities() -> PackedStringArray:
	return _unlocked("abilities")

func _unlocked(key: String) -> PackedStringArray:
	var unlocks: Dictionary = data.get("unlocks", {})
	var out := PackedStringArray()
	for item in unlocks.get(key, []):
		out.append(str(item))
	return out

func record_run(rooms_cleared: int, elapsed_seconds: float, kills: int) -> void:
	var records: Dictionary = data.get("records", {})
	records["total_runs"] = int(records.get("total_runs", 0)) + 1
	records["total_kills"] = int(records.get("total_kills", 0)) + kills
	records["best_rooms_cleared"] = maxi(int(records.get("best_rooms_cleared", 0)), rooms_cleared)
	var best := float(records.get("best_elapsed_seconds", 0.0))
	if rooms_cleared > 0 and (best <= 0.0 or elapsed_seconds < best):
		records["best_elapsed_seconds"] = elapsed_seconds
	data["records"] = records
	save()

func add_narrative_tag(tag: String) -> void:
	var tags: Array = data.get("narrative_tags", [])
	if not tags.has(tag):
		tags.append(tag)
		data["narrative_tags"] = tags
		save()

func has_narrative_tag(tag: String) -> bool:
	var tags: Array = data.get("narrative_tags", [])
	return tags.has(tag)

func summary() -> String:
	var records: Dictionary = data.get("records", {})
	return "存档版本 %d 社团点数 %d 总局数 %d 最佳房间 %d" % [
		int(data.get("version", 0)),
		int(data.get("club_points", 0)),
		int(records.get("total_runs", 0)),
		int(records.get("best_rooms_cleared", 0)),
	]
