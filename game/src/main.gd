extends Node2D
## 原型主场景入口。装配世界容器、界面与自检模式。
##
## 运行方式：
##   Godot_v4.7.2-stable_win64.exe --path game
## 自检方式（无需窗口）：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path game -- --self-test

const SELF_TEST_FLAG := "--self-test"
const CAPTURE_FLAG := "--capture"
const SEED_FLAG := "--seed="

var actors: Node2D = null
var effects: Node2D = null
var camera: CameraDirector = null
var ui: CombatUI = null
var flow: Node = null
var hitstop: HitstopService = null

var self_test_requested: bool = false
var capture_requested: bool = false
var seed_override: int = 0

func _ready() -> void:
	_parse_arguments()
	_build_world()
	_apply_settings()
	if self_test_requested:
		_run_self_test()
	else:
		flow.start_run(seed_override)
		if not capture_requested:
			ui.show_menu()
		if capture_requested:
			var probe: Node = load("res://src/core/window_probe.gd").new()
			probe.name = "CaptureProbe"
			add_child(probe)

## 读取用户参数。self 测试通过 "--" 之后的参数传入。
func _parse_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == SELF_TEST_FLAG:
			self_test_requested = true
		elif argument == CAPTURE_FLAG:
			capture_requested = true
		elif argument.begins_with(SEED_FLAG):
			seed_override = int(argument.substr(SEED_FLAG.length()))

func _build_world() -> void:
	actors = Node2D.new()
	actors.name = "Actors"
	actors.y_sort_enabled = true
	add_child(actors)

	effects = Node2D.new()
	effects.name = "Effects"
	add_child(effects)
	var feedback: Node2D = load("res://src/presentation/combat_effects.gd").new()
	add_child(feedback)
	var audio: Node = load("res://src/presentation/prototype_audio.gd").new()
	add_child(audio)

	camera = CameraDirector.new()
	camera.name = "Camera"
	add_child(camera)
	camera.make_current()

	hitstop = HitstopService.new()
	hitstop.name = "Hitstop"
	hitstop.add_to_group("hitstop")
	hitstop.scale_setting = float(SaveService.get_setting("hitstop_scale", 1.0))
	add_child(hitstop)

	ui = CombatUI.new()
	ui.name = "UI"
	add_child(ui)

	flow = GameFlow
	GameFlow.attach_world(actors, effects, ui, camera)
	ui.flow = flow
	# 自检模式关闭真实输入与设备相关表现，时间步由 SelfTest 驱动。
	GameFlow.self_test_mode = self_test_requested

func _apply_settings() -> void:
	camera.shake_setting = float(SaveService.get_setting("screen_shake", 1.0))
	var volume := float(SaveService.get_setting("master_volume", 0.8))
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(volume, 0.0001, 1.0)))

func _run_self_test() -> void:
	var tester := SelfTest.new()
	tester.name = "SelfTest"
	add_child(tester)
	tester.world = self
	# run 内部会在结束时发出 self_test_finished，由 Diagnostics 决定退出码。
	await tester.run(self)

func _process(delta: float) -> void:
	var _ignored := delta
	if self_test_requested:
		return
	# 未开始时支持快捷键直接开新局。
	if Input.is_action_just_pressed("debug_self_test"):
		flow.restart_run()
