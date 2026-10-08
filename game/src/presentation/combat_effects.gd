extends Node2D
## 原型命中特效与冲刺残影，不参与伤害结算。
var marks: Array[Dictionary] = []

func _ready() -> void:
	z_index = 20
	GameEvents.room_entered.connect(func(_a, _b, _c): marks.clear())
	GameEvents.attack_landed.connect(func(_id, _source, target, _damage, crit, _group):
		if is_instance_valid(target) and target is Node2D:
			marks.append({"position": target.global_position, "life": 0.22, "max_life": 0.22, "color": Color("#f7c779") if crit else Color("#fff9e3"), "radius": 25.0}))
	GameEvents.player_dashed.connect(func(_direction):
		if is_instance_valid(GameFlow.player):
			marks.append({"position": GameFlow.player.global_position, "life": 0.28, "max_life": 0.28, "color": Color("#82dfc9"), "radius": 44.0}))

func _process(delta: float) -> void:
	for mark in marks:
		mark["life"] -= delta
	marks = marks.filter(func(mark): return mark["life"] > 0.0)
	queue_redraw()

func _draw() -> void:
	for mark in marks:
		var ratio: float = mark["life"] / mark["max_life"]
		var point: Vector2 = mark["position"]
		var color: Color = mark["color"]
		color.a = ratio
		var radius: float = mark["radius"] * (1.15 - ratio)
		draw_arc(point, radius, 0, TAU, 16, color, 2.0)
		for index in range(5):
			var dir := Vector2.RIGHT.rotated(index * TAU / 5)
			draw_line(point + dir * radius, point + dir * (radius + 7), color, 2.0)

