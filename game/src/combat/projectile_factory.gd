class_name ProjectileFactory
extends RefCounted
## 投射物生成工具。玩家与敌人都通过这里发射，保证参数来源与命中规则一致。

## 生成一组投射物。spread_degrees 为整体散射角度，origin 为发射点。
static func volley(
	parent: Node,
	origin: Vector2,
	direction: Vector2,
	count: int,
	spread_degrees: float,
	config: Dictionary
) -> Array:
	var out: Array = []
	if parent == null or not is_instance_valid(parent):
		return out
	var base_dir := direction.normalized()
	if base_dir == Vector2.ZERO:
		base_dir = Vector2.RIGHT
	var spread := deg_to_rad(spread_degrees)
	for index in range(maxi(1, count)):
		var projectile := Projectile.new()
		var offset := 0.0
		if count > 1:
			offset = (-spread * 0.5) + (spread * float(index) / float(count - 1))
		var shot_dir := base_dir.rotated(offset)
		projectile.setup(config.merged({"direction": shot_dir}, true))
		projectile.global_position = origin
		parent.add_child(projectile)
		out.append(projectile)
	return out

## 生成一圈环形投射物，用于 Boss 的扇形组合。
static func fan(
	parent: Node,
	origin: Vector2,
	center_direction: Vector2,
	count: int,
	total_angle_degrees: float,
	config: Dictionary
) -> Array:
	var out: Array = []
	if parent == null or not is_instance_valid(parent):
		return out
	var center := center_direction.normalized()
	var total := deg_to_rad(total_angle_degrees)
	for index in range(maxi(1, count)):
		var offset := 0.0
		if count > 1:
			offset = (-total * 0.5) + (total * float(index) / float(count - 1))
		var projectile := Projectile.new()
		projectile.setup(config.merged({"direction": center.rotated(offset)}, true))
		projectile.global_position = origin
		parent.add_child(projectile)
		out.append(projectile)
	return out
