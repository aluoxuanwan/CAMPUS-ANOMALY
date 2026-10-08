extends Node
## 带窗口的验证工具。仅在 --capture 时启用，独立 qa 存档。
var frame := 0
var mode := "battle"
var output := "user://qa/battle.png"
var target_frames := 180
var frame_samples: Array[float] = []
var last_frame_usec := 0
var _saved := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-mode="):
			mode = arg.trim_prefix("--capture-mode=")
		if arg.begins_with("--capture-path="):
			output = arg.trim_prefix("--capture-path=")
		if arg.begins_with("--frames="):
			target_frames = int(arg.trim_prefix("--frames="))
	if mode == "menu":
		GameFlow.ui_layer.show_menu()
	elif mode == "boss":
		GameFlow._enter_room(GameFlow.graph.boss_id)
	if is_instance_valid(GameFlow.player):
		GameFlow.player.accepts_device_input = false
		GameFlow.player.use_auto_aim = true

func _process(delta: float) -> void:
	frame += 1
	var now := Time.get_ticks_usec()
	if frame > 30 and last_frame_usec > 0:
		frame_samples.append(float(now - last_frame_usec) / 1000.0)
	last_frame_usec = now
	if mode in ["battle", "boss"] and is_instance_valid(GameFlow.player):
		var player: Player = GameFlow.player
		player.input_attack_held = true
		player.input_move = Vector2(0.3, sin(frame * 0.025)) if frame < 130 else Vector2.ZERO
		player.invuln_left = 2.0
		if frame == 95:
			player.use_ability(1)
		if frame == 120:
			player.equip_weapon(1)
	if frame == 80 and mode in ["reward", "routes", "pause", "death"]:
		match mode:
			"reward", "routes":
				GameFlow.current_room._close()
				GameFlow._process_room_clear(1.0)
				if mode == "routes":
					GameFlow.ui_layer._choose_reward(GameFlow.offered_rewards[0])
			"pause":
				GameFlow.toggle_pause()
			"death":
				GameFlow.player.invuln_left = 0.0
				RunState.health = 1.0
				GameFlow.player.receive_damage(999, null, 9988, false, Vector2.ZERO, 0.0, "qa")
	if frame >= target_frames and not _saved:
		_saved = true
		await RenderingServer.frame_post_draw
		var picture := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
		var result := picture.save_png(output)
		var sum := 0.0
		for sample in frame_samples:
			sum += sample
		frame_samples.sort()
		var average_ms := sum / maxf(1, frame_samples.size())
		var p95_ms: float = frame_samples[mini(frame_samples.size() - 1, int(frame_samples.size() * 0.95))]
		print("[capture] %s result=%d %dx%d fps=%.1f frame_avg=%.2fms frame_p95=%.2fms static_memory=%.1fMiB" % [output, result, picture.get_width(), picture.get_height(), 1000.0 / average_ms, average_ms, p95_ms, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
		get_tree().quit(result)
