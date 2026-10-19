extends SceneTree
const Model = preload("res://features/base/base_model.gd")
const Items = preload("res://features/inventory/item_catalog.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func total(model, kind: String) -> int:
	var result := 0
	for p in model.state.players.values():
		for container in [p.bag,p.stash,p.equipment.values()]:
			for item in container:
				if not item.is_empty() and item.kind == kind: result += int(item.count)
	for item in model.state.drops.values():
		if item.kind == kind: result += int(item.count)
	return result

func unique(model) -> bool:
	var seen := {}
	for p in model.state.players.values():
		for container in [p.bag,p.stash,p.equipment.values()]:
			for item in container:
				if item.is_empty(): continue
				if seen.has(item.uid) or int(item.count) <= 0 or int(item.count) > int(Items.definition(item.kind).stack): return false
				seen[item.uid] = true
	for item in model.state.drops.values():
		if seen.has(item.uid): return false
		seen[item.uid] = true
	return true

func slot_of(p: Dictionary, kind: String, container: String = "bag") -> int:
	for i in range(p[container].size()):
		if not p[container][i].is_empty() and p[container][i].kind == kind: return i
	return -1

func run() -> void:
	var model = Model.new()
	model.add_player(1,"测试鸭"); model.add_player(2,"队友鸭")
	check(model.state.players.size() == 2,"two players initialized")
	check(model.state.players[1].bag.size() == 24 and model.state.players[1].stash.size() == 48,"fixed inventory dimensions")
	check(unique(model),"initial UIDs unique")
	check(not model.command(1,"move",{"direction":Vector2(INF,0)}),"infinite movement rejected")
	check(not model.command(1,"move",{"aim":Vector2(NAN,0)}),"NaN aim rejected")
	check(not model.command(99,"drop",{"index":0}),"absent player rejected")
	check(not model.command(1,"transfer",{"from":"bag","index":-1,"to":"stash"}),"invalid inventory index rejected")
	var p: Dictionary = model.state.players[1]
	p.pos = Vector2.ZERO
	model.obstacles.assign([Rect2(1,-2,1,4)])
	for i in range(30):
		model.command(1,"move",{"direction":Vector2.RIGHT * 100,"aim":Vector2.RIGHT})
		model.tick(0.1)
	check(p.pos.x <= 0.681,"authoritative circle does not cross obstacle")
	model.obstacles.clear(); p.pos = Vector2.ZERO
	model.command(1,"move",{"direction":Vector2.RIGHT})
	for i in range(10): model.tick(0.1)
	var stopped: Vector2 = p.pos
	for i in range(10): model.tick(0.1)
	check(p.pos == stopped,"stale movement times out")
	p.pos = Vector2(14.6,0)
	for i in range(10):
		model.command(1,"move",{"direction":Vector2.RIGHT})
		model.tick(0.1)
	check(p.pos.x <= 14.68,"world bounds respected")
	var ammo_before := total(model,"ammo")
	check(model.command(1,"transfer",{"from":"bag","index":0,"to":"stash"}),"Ctrl transfer into storage succeeds")
	check(total(model,"ammo") == ammo_before and unique(model),"storage transfer conserves item counts")
	check(model.command(1,"transfer",{"from":"stash","index":0,"to":"bag","target":0}),"targeted drag transfer succeeds")
	var water_before := total(model,"water")
	check(model.command(1,"transfer",{"from":"bag","index":2,"to":"bag","target":3}),"drag swaps different stacks")
	check(total(model,"water") == water_before and unique(model),"drag swap conserves ownership")
	p = model.state.players[1]
	var helmet := slot_of(p,"helmet","stash")
	check(model.command(1,"transfer",{"from":"stash","index":helmet,"to":"equipment","target":"helmet"}),"equip armor from stash")
	check(not model.command(1,"transfer",{"from":"bag","index":0,"to":"equipment","target":"helmet"}),"wrong equipment category rejected")
	check(model.command(1,"unequip",{"slot":"helmet"}),"unequip into bag")
	p = model.state.players[1]
	p.hp = 50
	var bandage := slot_of(p,"bandage")
	check(model.command(1,"use",{"index":bandage}) and p.hp == 68,"medical use heals exactly once")
	p.hp = 100
	var bandage_count := total(model,"bandage")
	check(not model.command(1,"use",{"index":bandage}) and total(model,"bandage") == bandage_count,"full health never wastes bandage")
	p.pos = Vector2.ZERO; model.state.players[2].pos = Vector2.ZERO
	var drop_index := slot_of(p,"water")
	var uid: String = p.bag[drop_index].uid
	check(model.command(1,"drop",{"index":drop_index}),"drop from inventory")
	check(model.command(2,"pickup",{"uid":uid}),"teammate picks up dropped stack")
	check(not model.command(1,"pickup",{"uid":uid}),"competing duplicate pickup rejected")
	check(total(model,"water") == water_before and unique(model),"drop pickup never duplicates items")
	check(model.command(1,"sort",{"container":"bag"}) and unique(model),"sort preserves stacks and unique IDs")
	# Repeated storage and drag actions must preserve both counts and UID ownership.
	for i in range(40):
		p = model.state.players[1]
		var index := slot_of(p,"ammo")
		if index >= 0: model.command(1,"transfer",{"from":"bag","index":index,"to":"stash"})
		p = model.state.players[1]
		index = slot_of(p,"ammo","stash")
		if index >= 0: model.command(1,"transfer",{"from":"stash","index":index,"to":"bag"})
	check(total(model,"ammo") == ammo_before and unique(model),"repeated stack moves conserve ammunition")
	p = model.state.players[1]
	var ammo_loaded := int(p.ammo)
	model.state.targets = [{"id":0,"pos":Vector2(5,0),"hp":100,"max_hp":100,"hits":0}]
	p.pos = Vector2.ZERO
	model.command(1,"move",{"aim":Vector2.RIGHT})
	check(model.command(1,"fire") and model.state.targets[0].hp == 66,"aimed shot damages training target")
	check(not model.command(1,"fire") and p.ammo == ammo_loaded - 1,"fire cooldown blocks duplicate shot")
	model.tick(0.1); model.tick(0.1)
	model.obstacles.assign([Rect2(2,-1,1,2)])
	check(model.command(1,"fire") and model.state.targets[0].hp == 66,"obstacle blocks target shot")
	model.obstacles.clear()
	var ammo_total := total(model,"ammo") + int(p.ammo)
	check(model.command(1,"reload"),"reload begins with reserve ammunition")
	for i in range(20): model.tick(0.1)
	check(p.ammo == 30 and not p.reloading,"reload completes at magazine capacity")
	check(total(model,"ammo") + int(p.ammo) == ammo_total,"reload conserves ammunition")
	var rifle_uid: String = p.equipment.weapon.uid
	check(model.command(1,"select_weapon"),"weapon selection equips secondary")
	p = model.state.players[1]
	check(p.ammo == 0,"secondary does not inherit rifle ammunition")
	check(model.command(1,"select_weapon"),"return to primary")
	p = model.state.players[1]
	check(p.ammo == 30 and p.equipment.weapon.uid == rifle_uid,"primary retains its own magazine")
	model.stations = [{"kind":"medical","pos":Vector2(0,0)},{"kind":"workbench","pos":Vector2(0,0)},{"kind":"trader","pos":Vector2(0,0)},{"kind":"range","pos":Vector2(0,0)}]
	p.pos = Vector2(10,0)
	check(not model.command(1,"rest"),"remote medical interaction rejected")
	p.pos = Vector2.ZERO; p.hp = 10
	check(model.command(1,"rest") and p.hp == 100,"nearby rest restores status")
	var scrap_before := total(model,"scrap")
	check(model.command(1,"craft") and total(model,"scrap") == scrap_before - 4,"workbench consumes four scrap")
	check(model.command(1,"buy_ammo") and p.credits == 440,"trader charges exact purchase cost")
	check(model.command(1,"reset_targets") and model.state.targets[0].hp == 100,"nearby range reset works")
	var profile_path := "user://duckov_model_test_profile.json"
	check(model.save_profile(profile_path) == OK,"explicit profile save")
	var restored = Model.new(); restored.add_player(1,"返回的鸭"); restored.add_player(2,"队友")
	check(restored.load_profile(profile_path) == OK,"explicit profile load")
	check(restored.state.players[1].credits == 440 and restored.state.players[1].ammo == 30,"profile restores inventory and weapon magazine")
	check(unique(restored),"profile load reissues collision-free item UIDs")
	var file := FileAccess.open(profile_path,FileAccess.WRITE)
	file.store_string('{"version":1,"bag":[]}'); file.close()
	check(restored.load_profile(profile_path) == ERR_FILE_CORRUPT,"malformed profile rejected")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(profile_path))
	# A full destination must neither remove nor partly consume the source stack.
	var full = Model.new(); full.add_player(1,"满包鸭")
	var full_p: Dictionary = full.state.players[1]
	for i in range(24): full_p.bag[i] = full._item("helmet",1)
	var before_full: Dictionary = full_p.duplicate(true)
	check(not full.command(1,"transfer",{"from":"stash","index":0,"to":"bag"}),"full bag rejects storage transfer")
	check(full.state.players[1] == before_full,"failed full-bag transfer is atomic")
	check(not full.command(1,"unequip",{"slot":"weapon"}),"full bag cannot unequip weapon")
	check(full.state.players[1] == before_full,"failed unequip preserves loaded weapon")
	full.state.drops.test_drop = {"uid":"test_drop","kind":"ammo","count":30,"pos":full_p.pos}
	check(not full.command(1,"pickup",{"uid":"test_drop"}) and full.state.drops.has("test_drop"),"full bag leaves world drop intact")
	# A loaded weapon retains its ammunition when another player picks it up.
	var exchange = Model.new(); exchange.add_player(1,"甲"); exchange.add_player(2,"乙")
	exchange.state.players[2].pos = exchange.state.players[1].pos
	check(exchange.command(1,"unequip",{"slot":"weapon"}),"loaded rifle can be unequipped")
	var rifle_index := slot_of(exchange.state.players[1],"rifle")
	var exchange_uid: String = exchange.state.players[1].bag[rifle_index].uid
	check(exchange.command(1,"drop",{"index":rifle_index}),"loaded rifle dropped")
	check(not exchange.state.players[1].magazines.has(exchange_uid),"drop removes former owner magazine association")
	check(exchange.command(2,"pickup",{"uid":exchange_uid}),"loaded rifle picked up by teammate")
	check(exchange.state.players[2].magazines.get(exchange_uid,0) == 20,"pickup carries the original loaded rounds")
	check(unique(exchange),"loaded weapon exchange has unique ownership")
	# Invalid station intents never charge or create an item.
	var trade_before := total(model,"ammo")
	p.pos = Vector2(14,0)
	check(not model.command(1,"buy_ammo") and total(model,"ammo") == trade_before,"remote trader request cannot create ammo")
	p.pos = Vector2.ZERO; p.credits = 0
	check(not model.command(1,"buy_ammo") and total(model,"ammo") == trade_before,"insufficient currency cannot create ammo")
	# Splitting preserves quantity but intentionally creates a distinct stack UID.
	var split_model = Model.new(); split_model.add_player(1,"拆分鸭")
	var split_p: Dictionary = split_model.state.players[1]
	var split_uid: String = split_p.bag[0].uid
	var split_total := total(split_model,"ammo")
	check(split_model.command(1,"split",{"container":"bag","index":0}),"default split halves a stack")
	check(split_p.bag[0].count == 30 and split_p.bag[7].count == 30 and split_p.bag[7].uid != split_uid,"default split uses first empty slot and fresh UID")
	check(total(split_model,"ammo") == split_total and unique(split_model),"split preserves all counts and ownership")
	check(split_model.command(1,"split",{"container":"stash","index":0,"count":10}),"explicit-count split works in storage")
	check(split_p.stash[0].count == 50 and split_p.stash[6].count == 10,"storage split uses exact requested count")
	var split_before: Dictionary = split_p.duplicate(true)
	for invalid_count in [0,-1,30,99,1.5,"2"]:
		check(not split_model.command(1,"split",{"container":"bag","index":0,"count":invalid_count}),"invalid split amount rejected: " + str(invalid_count))
	check(split_p == split_before,"all rejected split amounts are atomic")
	check(not split_model.command(1,"split",{"container":"bag","index":20}),"empty slot cannot split")
	check(not split_model.command(1,"split",{"container":"bag","index":6}),"single weapon cannot split")
	check(not split_model.command(1,"split",{"container":"equipment","index":0}),"equipment container cannot split")
	check(not split_model.command(1,"split",{"container":"stash","index":48}),"out-of-range split index rejected")
	for i in range(split_p.bag.size()):
		if split_p.bag[i].is_empty(): split_p.bag[i] = split_model._item("helmet",1)
	split_before = split_p.duplicate(true)
	check(not split_model.command(1,"split",{"container":"bag","index":0,"count":1}),"full container cannot split")
	check(split_p == split_before and unique(split_model),"full-container split failure is atomic")
	model.remove_player(2)
	check(not model.state.players.has(2),"disconnect removes player")
	print("DUCKOV_MODEL_TEST ",checks," checks, ",failures," failures")
	quit(0 if failures == 0 else 1)
