extends Node
## 自检诊断出口。在无头模式下把结果写为标准输出并设置退出码。
##
## 用法：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path game -- --self-test
## 退出码 0 表示全部检查通过，1 表示存在失败项。

var enabled: bool = false
var _finished: bool = false
var _ok: bool = false
var _summary: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for argument in OS.get_cmdline_user_args():
		if argument == "--self-test":
			enabled = true
	GameEvents.diagnostic.connect(_on_diagnostic)
	GameEvents.self_test_finished.connect(_on_self_test_finished)

func _on_diagnostic(message: String) -> void:
	if enabled:
		print("[SELFTEST] " + message)

func _on_self_test_finished(ok: bool, summary: Dictionary) -> void:
	if not enabled or _finished:
		return
	_finished = true
	_ok = ok
	_summary = summary
	print("[SELFTEST] 结果：%s" % ("通过" if ok else "失败"))
	print("[SELFTEST] 检查项 %d 失败 %d 警告 %d" % [
		int(summary.get("checks", 0)), int(summary.get("failures", 0)), int(summary.get("warnings", 0))
	])
	for failure in summary.get("failure_list", []):
		print("[SELFTEST] 失败项：" + str(failure))
	for warning in summary.get("warning_list", []):
		print("[SELFTEST] 警告项：" + str(warning))
	# 延迟一帧退出，让队列中的打印先完成。
	call_deferred("_quit")

func _quit() -> void:
	if not enabled:
		return
	get_tree().quit(0 if _ok else 1)
