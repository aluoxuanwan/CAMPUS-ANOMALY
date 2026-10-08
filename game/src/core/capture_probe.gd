extends Node
## 截图工具。启动后推进若干帧，保存一张帧缓冲图并退出。
## 仅在带窗口的验证流程中使用，不参与游戏流程。

const OUTPUT_PATH := "user://frame.png"

var frames_waited: int = 0
var target_frames: int = 150
var _flow: Node = null
var _saved: bool = false
## 截取前的额外等待，让敌人靠近以检验战斗画面。
var approach_frames: int = 90

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--frames="):
			target_frames = int(argument.substr("--frames=".length()))
	_flow = GameFlow

func _process(_delta: float) -> void:
	frames_waited += 1
	# 前若干帧让玩家移动并开火，检验移动、投射物与 HUD。
	if frames_waited == 20 and _flow != null and _flow.player != null:
		_flow.player.input_move = Vector2.RIGHT
	if frames_waited == 60 and _flow != null and _flow.player != null:
		_flow.player.input_attack_held = true
		_flow.player.use_auto_aim = true
		_flow.player.input_move = Vector2.ZERO
	if frames_waited >= target_frames and not _saved:
		_saved = true
		_capture()
	if frames_waited > target_frames + 30:
		get_tree().quit(0)

func _capture() -> void:
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(OUTPUT_PATH)
	var absolute := ProjectSettings.globalize_path(OUTPUT_PATH)
	print("[capture] 保存 %s 结果 %d 尺寸 %dx%d" % [absolute, error, image.get_width(), image.get_height()])
