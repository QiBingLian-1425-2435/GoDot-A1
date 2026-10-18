extends RefCounted
## Authority-only subsystem. ctx is the match; no scene/UI dependencies.

var _corpse_clocks: Dictionary = {}
var _next_corpse_id := 1

func _update_interactions(ctx, delta: float) -> void:
	var helped: Dictionary = {}
	for p in ctx.state.players.values():
		if p.status != "alive" or not p.interacting:
			_corpse_clocks.erase(p.id)
			continue
		var target: Dictionary = {}
		var nearest = 1.6
		for other in ctx.state.players.values():
			if other.status != "downed":
				continue
			var distance: float = p.pos.distance_to(other.pos)
			if distance < nearest and ctx._line_clear(p.pos, other.pos):
				nearest = distance
				target = other
		if not target.is_empty():
			helped[target.id] = true
		else:
			_corpse_clocks[p.id] = float(_corpse_clocks.get(p.id, 0.0)) + delta
			if _corpse_clocks[p.id] >= 0.75:
				_corpse_clocks[p.id] = 0.0
				for corpse in ctx.state.corpses:
					if p.pos.distance_to(corpse.pos) < 1.6 and ctx._line_clear(p.pos, corpse.pos):
						ctx._loot_corpse(p, corpse, true)
						break
	for p in ctx.state.players.values():
		if p.status != "downed":
			continue
		if helped.has(p.id):
			p.revive_progress += delta
			if p.revive_progress >= ctx.REVIVE_SECONDS:
				p.status = "alive"
				p.hp = 65.0
				p.down_left = 0.0
				p.revive_progress = 0.0
				p.invulnerable = 5.0
				ctx._event("%s 被救起，短暂受到庇护" % p.name)
		else:
			p.revive_progress = 0.0

func _hurt(ctx, p: Dictionary, damage: float) -> void:
	if p.status != "alive" or p.invulnerable > 0.0:
		return
	p.hp = maxf(0.0, p.hp - damage)
	p.invulnerable = 0.85
	if p.hp <= 0.0:
		p.status = "downed"
		p.down_left = ctx.BLEED_SECONDS
		p.extract_progress = 0.0
		p.revive_progress = 0.0
		ctx._inputs.erase(p.id)
		ctx._monster_pause = 3.8
		ctx._event("%s 倒地！靠近并按住 E 救援" % p.name)

func _die(ctx, p: Dictionary, reason: String) -> void:
	if p.status == "dead" or p.status == "extracted":
		return
	p.status = "dead"
	p.hp = 0.0
	p.down_left = 0.0
	p.revive_progress = 0.0
	p.extract_progress = 0.0
	p.lost_value = ctx.bag_value(p)
	if not p.bag.is_empty():
		ctx.state.corpses.append({"id": _next_corpse_id, "owner": p.id, "name": p.name, "pos": p.pos, "items": p.bag})
		_next_corpse_id += 1
	p.bag = []
	ctx._inputs.erase(p.id)
	ctx._detach(p.id)
	ctx._clear_requests(p.id)
	ctx._event("%s · %s" % [p.name, reason])
