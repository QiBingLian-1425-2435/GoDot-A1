extends SceneTree

const Model = preload("res://features/match/match_model.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: " + label)

func fixture():
	var m = Model.new()
	m.add_player(1, "Host")
	m.add_player(42, "Peer")
	m.start_round()
	m._monster_pause = 9999.0
	return m

func advance(m, seconds: float) -> void:
	for index in ceili(seconds / 0.1):
		m.tick(0.1)

func unique_items(m) -> bool:
	var all: Array = []
	for item in m.state.loot:
		all.append(item.id)
	for p in m.state.players.values():
		for item in p.bag:
			all.append(item.id)
	for corpse in m.state.corpses:
		for item in corpse.items:
			all.append(item.id)
	var ids: Dictionary = {}
	for id in all:
		if ids.has(id):
			return false
		ids[id] = true
	return all.size() == 12

func _run() -> void:
	var m = fixture()
	var a: Dictionary = m.get_player(1)
	var b: Dictionary = m.get_player(42)
	a.pos = m.state.loot[0].pos
	b.pos = a.pos
	var contested_id: int = m.state.loot[0].id
	m.command(1, "pickup")
	m.command(42, "pickup")
	check(a.bag.size() == 1 and b.bag.is_empty(), "two actors cannot duplicate one ground item")
	check(unique_items(m), "ground pickup preserves exactly 12 unique instances")
	m.command(1, "drop", {"item_id": contested_id})
	m.command(1, "drop", {"item_id": contested_id})
	m.command(42, "pickup")
	check(a.bag.is_empty() and b.bag.size() == 1 and unique_items(m), "repeated drop and pickup transfers only once")
	a.capacity = 0.1
	a.pos = m.state.loot[0].pos
	var count: int = m.state.loot.size()
	m.command(1, "pickup")
	check(a.bag.is_empty() and m.state.loot.size() == count, "overweight pickup neither consumes nor copies loot")
	m.command(42, "move", {"direction": Vector2(1000, 0)})
	var old_pos: Vector2 = b.pos
	m.tick(0.1)
	check(b.pos.distance_to(old_pos) <= 0.351, "movement intent magnitude is bounded")
	advance(m, 1.0)
	old_pos = b.pos
	advance(m, 0.5)
	check(b.pos == old_pos, "stale input expires rather than leaving stuck movement")
	var fresh = fixture()
	a = fresh.get_player(1)
	b = fresh.get_player(42)
	a.pos = Vector2(-7, 3)
	b.pos = Vector2(-6, 3)
	a.status = "downed"
	a.hp = 0.0
	a.down_left = 22.0
	for index in 31:
		fresh.command(42, "move", {"direction": Vector2.ZERO, "interact": true})
		fresh.tick(0.1)
	check(a.status == "alive" and a.hp == 65.0 and a.down_left == 0.0 and fresh.state.corpses.is_empty(), "held rescue revives once without a corpse or stale bleed timer")
	fresh = fixture()
	a = fresh.get_player(1)
	b = fresh.get_player(42)
	a.pos = fresh.state.loot[0].pos
	fresh.command(1, "pickup")
	fresh._die(a, "test")
	fresh._die(a, "duplicate")
	check(a.bag.is_empty() and fresh.state.corpses.size() == 1 and unique_items(fresh), "death transfers backpack to exactly one corpse")
	b.pos = a.pos
	fresh.command(42, "pickup")
	fresh.command(42, "pickup")
	check(b.bag.size() == 1 and fresh.state.corpses[0].items.is_empty() and unique_items(fresh), "repeated corpse loot cannot copy items")
	fresh = fixture()
	a = fresh.get_player(1)
	b = fresh.get_player(42)
	a.pos = fresh.state.loot[0].pos
	fresh.command(1, "pickup")
	var reward: int = fresh.bag_value(a)
	a.pos = Model.EXTRACT_POSITION
	advance(fresh, 2.0)
	check(a.extract_progress > 0.0 and a.status == "alive", "extraction waits rather than triggering immediately")
	a.pos = Vector2.ZERO
	fresh.tick(0.1)
	check(a.extract_progress == 0.0, "leaving extraction cancels hold")
	a.pos = Model.EXTRACT_POSITION
	advance(fresh, 4.2)
	check(a.status == "extracted" and a.result_value == reward and fresh.state.phase == "raid", "individual host extraction leaves the teammate and server in raid")
	fresh.command(1, "drop", {"item_id": a.bag[0].id})
	fresh.command(1, "move", {"direction": Vector2.LEFT})
	fresh._hurt(a, 100.0)
	advance(fresh, 4.2)
	check(a.bag.size() == 1 and a.pos == Model.EXTRACT_POSITION and fresh.state.total_banked == reward, "extracted bag is immutable and reward is counted once")
	fresh.state.time_left = 0.05
	fresh.tick(0.1)
	check(fresh.state.phase == "results" and b.status == "dead" and a.result_value == reward and fresh.state.total_banked == reward, "timeout keeps already extracted rewards")
	fresh.reset_lobby()
	fresh.start_round()
	check(fresh.state.round == 2 and fresh.state.corpses.is_empty() and fresh.get_player(1).bag.is_empty() and fresh.state.time_left == 360.0 and fresh.state.total_banked == reward, "new round clears transient state and preserves room banked total")
	fresh = fixture()
	b = fresh.get_player(42)
	b.pos = fresh.state.loot[0].pos
	fresh.command(42, "pickup")
	fresh.remove_player(42)
	check(fresh.get_player(42).status == "dead" and fresh.state.corpses.size() == 1 and fresh.state.total_banked == 0 and unique_items(fresh), "disconnect drops a corpse and never banks the backpack")
	fresh = fixture()
	a = fresh.get_player(1)
	b = fresh.get_player(42)
	fresh._die(a, "test")
	fresh.command(1, "possession_request", {"target": 42})
	check(a.possessing == 0 and b.request_from == 1, "possession request does not bypass consent")
	fresh.command(42, "possession_accept")
	check(a.possessing == 42 and b.request_from == 0, "living player can consent to view-only possession")
	fresh.command(42, "detach")
	check(a.possessing == 0, "living player can detach the viewer")
	fresh.command(1, "possession_request", {"target": 42})
	fresh.command(42, "possession_accept")
	b.pos = Model.EXTRACT_POSITION
	advance(fresh, 4.2)
	check(a.possessing == 0 and fresh.state.phase == "results", "extraction cleans possession and ends once nobody can act")
	fresh = fixture()
	check(not fresh.add_player(77, "Late"), "late joins are rejected during raid")
	fresh.reset_lobby()
	for id in [3, 4, 5]:
		fresh.add_player(id, "Extra")
	check(fresh.state.players.size() == 5 and not fresh.add_player(6, "Overflow"), "room limit includes host and is five total")
	fresh = fixture()
	a = fresh.get_player(1)
	a.status = "downed"
	a.down_left = 0.15
	advance(fresh, 0.3)
	check(a.status == "dead", "downed player bleeds out after timer")
	print("MODEL TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
