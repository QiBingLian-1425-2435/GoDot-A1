extends SceneTree
const Model = preload("res://features/base/base_model.gd")
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	print("PASS: " if ok else "FAIL: ", label)
	if not ok: failures += 1
func advance(m, seconds: float):
	for i in range(roundi(seconds*100)): m.tick(.01)
func run():
	var m = Model.new()
	m.add_player(1, "owner"); m.add_player(2, "guest")
	m.state.world = "surface"
	m.stations = [{"kind":"loot", "uid":"box", "world":"surface", "pos":Vector2.ZERO, "height":0.0, "locked":true}]
	m.loot_reachable = func(_uid, _from): return true
	var p: Dictionary = m.state.players[1]
	var q: Dictionary = m.state.players[2]
	p.pos = Vector2.ZERO; q.pos = Vector2.ZERO
	p.bag = m._empty_slots(24); q.bag = m._empty_slots(24)
	check(not m.command(1, "search", {"uid":"box"}) and m.state.containers.is_empty(), "locked container rejects without creating contents")
	p.bag[0] = m._item("lockpick", 2)
	check(m.command(1, "search", {"uid":"box"}), "host opens with one lockpick")
	var box: Dictionary = m.state.containers.box
	var rolled: Array = box.items.duplicate(true)
	check(box.items.size() >= 2 and box.items.size() <= 5 and m._count(p.bag,"lockpick") == 1, "2 to 5 slots generated once")
	check(box.revealed == 0 and m.state.drops.is_empty(), "starts unknown without floor loot")
	check(not m.command(1,"loot_take",{"uid":"box","index":0,"item_uid":box.items[0].uid}), "cannot take an undiscovered item even with its uid")
	var public: Dictionary = m.Loot.public_state(m.state)
	check(public.containers.box.items[0].is_empty() and not box.items[0].is_empty(), "public snapshot hides unknown contents without mutating authority")
	advance(m,.7)
	check(box.revealed == 0, "search does not finish instantly")
	check(m.command(1,"loot_close",{"uid":"box"}) and p.loot_uid.is_empty(), "close releases search")
	advance(m,3)
	check(box.revealed == 0 and is_equal_approx(float(box.progress), .7), "closed container pauses and preserves progress")
	check(m.command(2,"loot_view",{"uid":"box"}) and box.items == rolled and box.searcher == 2, "teammate resumes same contents without a lockpick")
	advance(m,.71)
	check(box.revealed == 1, "resumed timer reveals one slot")
	check(m.command(1,"loot_view",{"uid":"box"}) and box.searcher == 2 and m._count(p.bag,"lockpick") == 1, "second viewer cannot double search speed or spend another key")
	check(not m.command(1,"loot_close",{"uid":"other"}) and p.loot_uid == "box", "delayed close for other container does not cancel this one")
	var item: Dictionary = box.items[0].duplicate(true)
	check(not m.command(1,"loot_take",{"uid":"box","index":0,"item_uid":"forged"}), "stale item identity rejected")
	for i in range(24): p.bag[i] = m._item("rifle",1)
	check(not m.command(1,"loot_take",{"uid":"box","index":0,"item_uid":item.uid}) and box.items[0] == item, "full inventory leaves exact item in container")
	p.bag = m._empty_slots(24)
	check(m.command(1,"loot_take",{"uid":"box","index":0,"item_uid":item.uid}), "take transfers a revealed stack")
	check(box.items[0].is_empty() and m._count(p.bag,item.kind) == item.count, "one authoritative ownership transfer")
	check(not m.command(2,"loot_take",{"uid":"box","index":0,"item_uid":item.uid}) and m.Items.weight(q.bag) == 0, "second player cannot claim the same stack")
	m.command(1,"loot_close",{"uid":"box"}); m.command(2,"loot_close",{"uid":"box"})
	m.command(1,"loot_view",{"uid":"box"}); advance(m,10)
	check(box.revealed == box.items.size(), "remaining slots discovered in order")
	check(m.command(1,"loot_take",{"uid":"box","index":-1}), "take all available revealed items")
	var empty := true
	for stack in box.items:
		if not stack.is_empty(): empty = false
	check(empty and m.command(2,"loot_view",{"uid":"box"}) and box.items.size() == rolled.size(), "empty box reopens without reroll")
	q.pos = Vector2(10,0); m.tick(.1)
	check(q.loot_uid.is_empty(), "leaving range closes container")
	p.pos = Vector2.ZERO; m.command(1,"loot_view",{"uid":"box"})
	m.loot_reachable = func(_uid, _from): return false
	m.tick(.1)
	check(p.loot_uid.is_empty() and not m.command(1,"loot_view",{"uid":"box"}), "occlusion cancels and prevents reopening")
	m.loot_reachable = func(_uid, _from): return true
	m.command(1,"loot_view",{"uid":"box"}); m.reset_transients(1)
	check(p.loot_uid.is_empty() and box.searcher == 0, "relocation clears active search")
	m.command(2,"loot_view",{"uid":"box"}); m.remove_player(2)
	check(box.searcher == 0, "disconnect releases search ownership")
	print("CONTAINER_SEARCH checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
