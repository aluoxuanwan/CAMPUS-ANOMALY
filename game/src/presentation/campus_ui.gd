class_name CombatUI
extends CanvasLayer
## 只展示信息并提交选择，奖励与选路由流程层校验。
const INK := Color("#101e25")
const PANEL := Color("#1b3037")
const MUTED := Color("#93b1b3")
const PAPER := Color("#eff1de")
const MINT := Color("#84d9bc")
const GOLD := Color("#f0c774")
var flow: Node
var root: Control
var health_bar: ProgressBar
var health_text: Label
var weapon_text: Label
var room_text: Label
var bell_text: Label
var stats_text: Label
var ability_buttons: Array[Button] = []
var boss_panel: VBoxContainer
var boss_bar: ProgressBar
var boss_text: Label
var overlay: Control
var modal: VBoxContainer
var debug_text: Label
var flash_rect: ColorRect
var floats: Control
var font: SystemFont
var pending_routes: Array = []

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC", "Arial"])
	_build()
	GameEvents.floating_text_requested.connect(_on_floating_text)
	GameEvents.bell_phase_changed.connect(func(_phase, _seconds): toast("铃声响起，课桌布局改变"))
	GameEvents.player_weapon_swapped.connect(func(id): toast(GameData.get_weapon(id).display_name))

func _style(color: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(1 if border.a > 0 else 0)
	box.set_corner_radius_all(10)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	return box

func label(text: String, size_value: int = 16, color: Color = PAPER) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_override("font", font)
	node.add_theme_font_size_override("font_size", size_value)
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

func button(text: String, callback: Callable, min_size: Vector2 = Vector2(180, 48)) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size = min_size
	node.add_theme_font_override("font", font)
	node.add_theme_font_size_override("font_size", 16)
	node.add_theme_color_override("font_color", PAPER)
	node.add_theme_color_override("font_hover_color", MINT)
	node.add_theme_color_override("font_disabled_color", MUTED.darkened(0.35))
	node.add_theme_stylebox_override("normal", _style(PANEL.lightened(0.035), Color("#36545a")))
	node.add_theme_stylebox_override("hover", _style(PANEL.lightened(0.12), MINT))
	node.add_theme_stylebox_override("pressed", _style(INK, MINT))
	node.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, GOLD))
	node.add_theme_stylebox_override("disabled", _style(INK.lightened(0.05)))
	node.pressed.connect(callback)
	return node

func bar(color: Color, height: int = 10) -> ProgressBar:
	var node := ProgressBar.new()
	node.custom_minimum_size = Vector2(240, height)
	node.show_percentage = false
	node.max_value = 1.0
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := _style(INK)
	background.content_margin_top = 0
	background.content_margin_bottom = 0
	var fill := _style(color)
	fill.content_margin_top = 0
	fill.content_margin_bottom = 0
	node.add_theme_stylebox_override("background", background)
	node.add_theme_stylebox_override("fill", fill)
	return node

func _build() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 24
	top.offset_right = -24
	top.offset_top = 14
	top.add_theme_stylebox_override("panel", _style(PANEL, Color("#345158")))
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 32)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(header)
	var health_box := VBoxContainer.new()
	health_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(health_box)
	health_text = label("生命 100 / 100", 15, MINT)
	health_box.add_child(health_text)
	health_bar = bar(MINT)
	health_box.add_child(health_bar)
	weapon_text = label("", 13, MUTED)
	health_box.add_child(weapon_text)
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(center)
	room_text = label("", 19)
	center.add_child(room_text)
	bell_text = label("", 13, GOLD)
	center.add_child(bell_text)
	stats_text = label("", 14, MUTED)
	header.add_child(stats_text)
	header.add_child(button("Esc  暂停", func(): flow.toggle_pause(), Vector2(118, 44)))
	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 24
	bottom.offset_right = -24
	bottom.offset_top = -91
	bottom.add_theme_constant_override("separation", 7)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	var skills := HBoxContainer.new()
	skills.alignment = BoxContainer.ALIGNMENT_CENTER
	skills.add_theme_constant_override("separation", 10)
	skills.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(skills)
	for index in range(4):
		var slot := index
		var callback := func():
			if flow.state == GameFlow.FlowState.PLAYING and is_instance_valid(flow.player):
				flow.player.use_ability(slot)
		var skill := button("", callback, Vector2(200, 43))
		skills.add_child(skill)
		ability_buttons.append(skill)
	var controls := label("WASD 移动    鼠标瞄准 / 左键攻击    空格冲刺    Q 换武器    R 装填    1 至 4 社团技能", 13, MUTED)
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(controls)
	boss_panel = VBoxContainer.new()
	boss_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	boss_panel.offset_left = -220
	boss_panel.offset_right = 220
	boss_panel.offset_top = -149
	boss_panel.offset_bottom = -114
	boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(boss_panel)
	boss_text = label("", 14, INK)
	boss_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_panel.add_child(boss_text)
	boss_bar = bar(Color("#e77d71"), 7)
	boss_panel.add_child(boss_bar)
	boss_panel.hide()
	debug_text = label("", 12, MINT)
	debug_text.position = Vector2(28, 126)
	debug_text.hide()
	root.add_child(debug_text)
	floats = Control.new()
	floats.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	floats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(floats)
	flash_rect = ColorRect.new()
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash_rect)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.025, 0.07, 0.085, 0.91)
	overlay.add_child(dim)
	var center_modal := CenterContainer.new()
	center_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center_modal)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 0)
	panel.add_theme_stylebox_override("panel", _style(PANEL, Color("#45605e")))
	center_modal.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	modal = VBoxContainer.new()
	modal.add_theme_constant_override("separation", 20)
	margin.add_child(modal)
	overlay.hide()

func _process(_delta: float) -> void:
	if flow == null:
		return
	health_text.text = "生命 %d / %d" % [ceili(RunState.health), roundi(RunState.max_health())]
	health_bar.value = RunState.health / RunState.max_health()
	var player = flow.player
	if is_instance_valid(player) and player.weapon != null:
		var ammo_text := "无需装填"
		if player.weapon.magazine > 0:
			ammo_text = "装填 %.1fs" % player.reload_timer if player.reload_timer > 0 else "%d / %d" % [player.ammo, player.weapon.magazine]
		weapon_text.text = "%s  ·  %s" % [player.weapon.display_name, ammo_text]
		for slot in range(4):
			var def := GameData.get_ability(RunState.ability_ids[slot])
			var cooldown := float(player.ability_cooldowns.get(def.id, 0.0))
			var names := ["体育回旋", "临时炮台", "戏剧诱饵", "摄影闪光"]
			ability_buttons[slot].text = "%d  %s%s" % [slot + 1, names[slot], "  %.1fs" % cooldown if cooldown > 0 else ""]
			ability_buttons[slot].tooltip_text = def.display_name + "\n" + def.description
			ability_buttons[slot].disabled = cooldown > 0 or flow.state != GameFlow.FlowState.PLAYING
	stats_text.text = "%s\n击败 %d   ·   学分 %d   ·   %02d:%02d" % [flow.progress_text(), RunState.kills, RunState.insight, int(RunState.elapsed_seconds / 60), int(RunState.elapsed_seconds) % 60]
	var room = flow.current_room
	boss_panel.visible = is_instance_valid(room) and is_instance_valid(room.boss)
	if is_instance_valid(room):
		if room.template.kind == GameConfig.RoomKind.BOSS:
			bell_text.text = "期末考场  ·  直线 / 扇形 / 铃声攻击"
		elif room.is_closed:
			bell_text.text = "本节已完成  ·  领取奖励后继续"
		else:
			bell_text.text = "%s  ·  铃声 %.1fs  ·  波次 %d/%d  ·  异常 %d" % ["课堂" if room.bell_phase == 0 else "课间", room.bell_phase_timer, maxi(1, room.current_wave + 1), room.total_waves, room.enemies.size()]
		if boss_panel.visible:
			boss_bar.value = room.boss.health_ratio()
			boss_text.text = "%s  /  %s" % [room.boss.def.display_name, room.boss.current_phase_name()]
	if debug_text.visible:
		debug_text.text = "FPS %d\n种子 %d\n%s\n%s" % [Engine.get_frames_per_second(), RunState.seed_value, flow.state_name(), RunState.modifiers.describe()]

func on_room_entered(room: Room, _data: RoomGraphNode) -> void:
	room_text.text = room.template.display_name

func _open(title: String, subtitle: String) -> void:
	for child in modal.get_children():
		modal.remove_child(child)
		child.queue_free()
	modal.add_child(label("CAMPUS ANOMALY  /  课外行动", 13, MINT))
	modal.add_child(label(title, 34))
	var sub := label(subtitle, 16, MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal.add_child(sub)
	overlay.show()

func close_modal() -> void:
	overlay.hide()

func show_menu() -> void:
	flow.state = GameFlow.FlowState.MENU
	get_tree().paused = true
	_open("校园异常", "期末周，课桌开始移动，教科书长出了脾气。\n带上粉笔、篮球和直尺，穿过六节异常课程，挑战试卷巨像。")
	modal.add_child(label("三把校园武器   /   四项社团技能   /   铃声改变掩体", 17, GOLD))
	modal.add_child(label("每清理一间教室，选择一个成长奖励，再选择下一节课。\n红色外圈表示敌人正在准备攻击，及时侧移或冲刺。", 15))
	modal.add_child(button("开始课外行动  ·  Enter", _start))
	modal.add_child(label("战斗原型 v0.1   ·   画面与声音为程序制作的临时素材", 12, MUTED))

func _start() -> void:
	close_modal()
	flow.start_run()

func show_reward_screen(options: Array) -> void:
	pending_routes = options
	_open("本节完成，选一个奖励", "成长只作用于本局。选择后安排下一节课。")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	modal.add_child(row)
	for id in flow.offered_rewards:
		var def := GameData.get_modifier(id)
		var title := def.display_name if def != null else "校医补给"
		var description := def.description if def != null else "立即恢复 25 点生命。"
		var card := button("%s\n\n%s" % [title, description], _choose_reward.bind(id), Vector2(255, 170))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(card)
	var reroll := button("重抽  ·  本局剩余 %d 次" % RunState.rerolls_left, func():
		if flow.reroll_rewards():
			show_reward_screen(pending_routes))
	reroll.disabled = RunState.rerolls_left <= 0
	modal.add_child(reroll)

func _choose_reward(id: String) -> void:
	if flow.select_reward(id):
		show_routes()

func show_routes() -> void:
	_open("安排下一节课", "本局成长：" + RunState.modifiers.describe())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	modal.add_child(row)
	for id in pending_routes:
		var data: RoomGraphNode = flow.graph.get_node_by_id(int(id))
		var room := GameData.get_room(data.template_id)
		var callback := func():
			close_modal()
			flow.choose_next_room(int(id))
		var course_names := {"classroom": "普通课程", "gym": "体育课", "lab": "实验课", "library": "自习课", "boss": "期末考试", "elite": "挑战课"}
		var tags: PackedStringArray = PackedStringArray()
		for tag in data.course_tags:
			tags.append(course_names.get(tag, "校园课程"))
		var card := button("%s\n\n%s   %s" % [room.display_name, data.display_kind(), " / ".join(tags)], callback, Vector2(310, 120))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)

func show_death_screen(points: int) -> void:
	_results("下课了，明天再来", "异常课程暂时赢了一回。积累的社团点数已经保存。", points)

func show_victory() -> void:
	_results("期末考试，通过！", "试卷巨像倒下，校园恢复了秩序。", RunState.settle_rewards(true))

func _results(title: String, subtitle: String, points: int) -> void:
	flow.release_hitstop()
	get_tree().paused = true
	_open(title, subtitle)
	modal.add_child(label("清理 %d 节课程    ·    击败 %d 个异常    ·    用时 %.1f 秒" % [RunState.rooms_cleared, RunState.kills, RunState.elapsed_seconds], 18, GOLD))
	modal.add_child(label("本次社团点数 +%d    ·    累计 %d\n本局成长：%s" % [points, int(SaveService.data.get("club_points", 0)), RunState.modifiers.describe()], 15))
	modal.add_child(button("再次挑战  ·  Enter", _start))
	modal.add_child(button("返回开始页", show_menu))

func show_pause(visible_now: bool) -> void:
	if not visible_now:
		close_modal()
		return
	_open("课间休息", "战斗、冷却和铃声计时已经暂停。")
	modal.add_child(label("本局成长：" + RunState.modifiers.describe(), 15))
	modal.add_child(button("继续行动  ·  Esc", func(): flow.toggle_pause()))
	var volume := HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 1.0
	volume.step = 0.05
	volume.value = float(SaveService.get_setting("master_volume", 0.8))
	modal.add_child(label("音量", 14, MUTED))
	modal.add_child(volume)
	volume.value_changed.connect(func(value):
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, value)))
		SaveService.set_setting("master_volume", value))
	modal.add_child(button("切换震屏  ·  当前 " + ("开启" if flow.camera.shake_setting > 0 else "关闭"), func():
		flow.camera.shake_setting = 0.0 if flow.camera.shake_setting > 0 else 1.0
		SaveService.set_setting("screen_shake", flow.camera.shake_setting)
		show_pause(true)))
	modal.add_child(button("返回开始页", show_menu))

func flash(color: Color, duration: float) -> void:
	if SaveService.get_setting("reduced_flash", false):
		return
	flash_rect.color = Color(color.r, color.g, color.b, minf(0.16, color.a))
	create_tween().tween_property(flash_rect, "color:a", 0.0, duration)

func _on_floating_text(world_position: Vector2, text: String, color: Color) -> void:
	if flow == null or GameFlow.self_test_mode or not bool(SaveService.get_setting("show_damage_numbers", true)):
		return
	var node := label(text, 15, color)
	node.add_theme_constant_override("outline_size", 3)
	node.add_theme_color_override("font_outline_color", INK)
	node.position = flow.actors.get_global_transform_with_canvas() * world_position + Vector2(-8, -24)
	floats.add_child(node)
	var tween := create_tween().set_parallel()
	tween.tween_property(node, "position:y", node.position.y - 30, 0.7)
	tween.tween_property(node, "modulate:a", 0.0, 0.7)
	tween.chain().tween_callback(node.queue_free)

func toast(text: String) -> void:
	if floats == null or GameFlow.self_test_mode:
		return
	if flow != null and is_instance_valid(flow.current_room) and flow.current_room.template.kind == GameConfig.RoomKind.BOSS:
		return
	var node := label(text, 17, GOLD)
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	node.offset_top = get_viewport().get_visible_rect().size.y - 124
	floats.add_child(node)
	var tween := create_tween()
	tween.tween_interval(0.65)
	tween.tween_property(node, "modulate:a", 0.0, 0.25)
	tween.tween_callback(node.queue_free)

func _unhandled_input(event: InputEvent) -> void:
	if flow == null or GameFlow.self_test_mode:
		return
	if event.is_action_pressed("debug_toggle"):
		debug_text.visible = not debug_text.visible
	if event.is_action_pressed("ui_cancel"):
		flow.toggle_pause()
	if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		if flow.state in [GameFlow.FlowState.MENU, GameFlow.FlowState.DEAD, GameFlow.FlowState.VICTORY]:
			_start()
