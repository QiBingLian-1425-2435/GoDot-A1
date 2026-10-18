extends RefCounted
## Authority-only subsystem. ctx is the match; no scene/UI dependencies.

var _monster_hit_cooldown := 0.0
var _monster_pause := 0.0
var _patrol_index := 0

func _update_monster(ctx, delta: float) -> void:
	var monster: Dictionary = ctx.state.monster
	_monster_hit_cooldown = maxf(0.0, _monster_hit_cooldown - delta)
	_monster_pause = maxf(0.0, _monster_pause - delta)
	if _monster_pause > 0.0:
		monster.mode = "recover"
		return
	var target: Dictionary = {}
	var nearest = 5.0
	for p in ctx.state.players.values():
		if p.status != "alive" or p.pos.distance_to(ctx.EXTRACT_POSITION) < 2.2:
			continue
		var distance: float = monster.pos.distance_to(p.pos)
		if distance < nearest and ctx._line_clear(monster.pos, p.pos):
			target = p
			nearest = distance
	var destination: Vector2
	var speed = 1.35
	if not target.is_empty():
		monster.mode = "chase"
		monster.target = target.id
		monster.alert = 2.5
		monster.last_seen = target.pos
		destination = target.pos
		speed = 2.55
		if nearest < 0.9 and _monster_hit_cooldown <= 0.0:
			ctx._hurt(target, 34.0)
			_monster_hit_cooldown = 1.2
	elif float(monster.get("alert", 0.0)) > 0.0:
		monster.mode = "search"
		monster.alert = maxf(0.0, monster.alert - delta)
		destination = monster.get("last_seen", monster.pos)
		speed = 1.8
	else:
		monster.mode = "patrol"
		monster.target = 0
		var points = [Vector2(0, -4), Vector2(6, -4), Vector2(7, 0), Vector2(0.4, 0)]
		destination = points[_patrol_index]
		if monster.pos.distance_to(destination) < 0.55:
			_patrol_index = (_patrol_index + 1) % points.size()
	var direction = ctx._path_direction(monster.pos, destination)
	monster.pos = ctx._advance_actor(0, monster.pos, direction * speed * delta)
