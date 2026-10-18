extends RefCounted
## Authority-only subsystem. ctx is the match; no scene/UI dependencies.

var _bot_loot_clock := 0.0

func _bot_input(ctx, p: Dictionary) -> void:
	var leader: Dictionary = {}
	var rescue: Dictionary = {}
	for other in ctx.state.players.values():
		if other.id == p.id:
			continue
		if other.status == "downed":
			rescue = other
		if not other.bot and (other.status == "alive" or other.status == "extracted"):
			leader = other
	var destination: Vector2 = p.pos
	var interact = false
	if not rescue.is_empty():
		destination = rescue.pos
		if p.pos.distance_to(destination) < 1.2:
			interact = true
			destination = p.pos
	elif leader.is_empty() or leader.status == "extracted" or leader.extract_progress > 0.0:
		destination = ctx.EXTRACT_POSITION
	elif p.pos.distance_to(leader.pos) > 2.0:
		destination = leader.pos
	else:
		var closest = 3.3
		for item in ctx.state.loot:
			var distance: float = p.pos.distance_to(item.pos)
			if distance < closest and item.pos.distance_to(leader.pos) < 3.6 and ctx.bag_weight(p) + float(item.weight) <= p.capacity:
				destination = item.pos
				closest = distance
		if closest < 1.4 and _bot_loot_clock <= 0.0:
			ctx._pickup(p, true)
			_bot_loot_clock = 1.0
	var direction = Vector2.ZERO
	if p.pos.distance_to(destination) > 0.45:
		direction = ctx._path_direction(p.pos, destination)
	ctx._inputs[p.id] = {"direction": direction, "interact": interact, "age": 0.0}
