extends RefCounted
## Authority-only subsystem. ctx is the match; no scene/UI dependencies.

var _nav := AStarGrid2D.new()

func _build_navigation(ctx) -> void:
	_nav.region = Rect2i(-22, -16, 45, 33)
	_nav.cell_size = Vector2(0.5, 0.5)
	_nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_nav.update()
	for x in range(-22, 23):
		for y in range(-16, 17):
			_nav.set_point_solid(Vector2i(x, y), not _position_clear(ctx, Vector2(x * 0.5, y * 0.5)))

func _path_direction(ctx, from: Vector2, to: Vector2) -> Vector2:
	if _line_clear(ctx, from, to):
		return from.direction_to(to)
	var start = Vector2i(roundi(from.x * 2), roundi(from.y * 2))
	var end = Vector2i(roundi(to.x * 2), roundi(to.y * 2))
	if not _nav.is_in_boundsv(start) or not _nav.is_in_boundsv(end):
		return Vector2.ZERO
	# Positions adjacent to furniture can round into a solid cell.
	start = _nearest_walkable(ctx, start)
	end = _nearest_walkable(ctx, end)
	var path = _nav.get_point_path(start, end, true)
	if path.size() > 1:
		return from.direction_to(path[1])
	return Vector2.ZERO

func _nearest_walkable(ctx, cell: Vector2i) -> Vector2i:
	if not _nav.is_point_solid(cell):
		return cell
	for radius in range(1, 4):
		for x in range(-radius, radius + 1):
			for y in range(-radius, radius + 1):
				var candidate = cell + Vector2i(x, y)
				if _nav.is_in_boundsv(candidate) and not _nav.is_point_solid(candidate):
					return candidate
	return cell

func _move_position(ctx, pos: Vector2, offset: Vector2) -> Vector2:
	var result = pos
	var next = Vector2(clampf(pos.x + offset.x, -10.5, 10.5), pos.y)
	if _position_clear(ctx, next):
		result.x = next.x
	next = Vector2(result.x, clampf(pos.y + offset.y, -7.5, 7.5))
	if _position_clear(ctx, next):
		result.y = next.y
	return result

func _position_clear(ctx, pos: Vector2) -> bool:
	if absf(pos.x) > 10.5 or absf(pos.y) > 7.5:
		return false
	for obstacle in ctx.obstacles:
		if obstacle.grow(0.25).has_point(pos):
			return false
	return true

func _line_clear(ctx, from: Vector2, to: Vector2) -> bool:
	var steps = maxi(1, ceili(from.distance_to(to) / 0.18))
	for step in range(1, steps + 1):
		if not _position_clear(ctx, from.lerp(to, float(step) / float(steps))):
			return false
	return true
