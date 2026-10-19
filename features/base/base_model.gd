extends RefCounted

const InventoryRules = preload("res://features/inventory/base_inventory_rules.gd")
const Inventory = preload("res://features/inventory/base_inventory_system.gd")
const Combat = preload("res://features/combat/combat_system.gd")
const Profile = preload("res://features/persistence/profile_store.gd")
const Facilities = preload("res://features/base/facility_system.gd")
const Movement = preload("res://features/player/movement_rules.gd")
## Host-authoritative base rules. No files are accessed until an explicit profile call.
const Items = preload("res://features/inventory/item_catalog.gd")
const EQUIPMENT := ["weapon", "helmet", "armor", "backpack"]
const PLAYER_RADIUS := 0.32
const INPUT_TIMEOUT := 0.35
var bounds := Rect2(-15, -11, 30, 22)
var obstacles: Array[Rect2] = []
var stations: Array = []
var last_notice := ""
var state: Dictionary = {"players":{}, "drops":{}, "phase":"base", "targets":[], "shots":[]}
var _next_uid := 1
var _clock := 0.0
var _inputs: Dictionary = {}
var motion_solver: Callable # Main installs the real CharacterBody3D adapter; rule fixtures remain pure.

func _init() -> void:
	for i in range(3):
		state.targets.append({"id":i, "pos":Vector2(8 + i * 2, 8.8), "hp":100, "max_hp":100, "hits":0})

func add_player(id: int, player_name: String) -> void:
	if id <= 0 or state.players.has(id) or state.players.size() >= 5:
		return
	var bag := _empty_slots(24)
	var stash := _empty_slots(48)
	var rifle := _item("rifle", 1)
	var p := {"id":id, "name":player_name.strip_edges().left(24), "pos":Vector2(-1 + state.players.size() * 0.9, 4), "aim":Vector2.UP, "hp":100.0, "stamina":100.0, "hunger":85.0, "thirst":85.0, "bag":bag, "stash":stash, "equipment":{"weapon":rifle,"helmet":{},"armor":{},"backpack":_item("backpack",1)}, "ammo":20, "reloading":false, "reload_progress":0.0, "shots":0, "credits":500, "sprint":false, "crouch":false, "ads":false, "weight":0.0, "max_weight":44.0, "magazines":{rifle.uid:20}, "reload_timer":0.0, "fire_timer":0.0}
	for spec in [["ammo",60],["bandage",3],["water",2],["canned_food",2],["scrap",8],["medkit",1],["pistol",1]]:
		_insert(p.bag, _item(spec[0], spec[1]))
	for spec in [["ammo",60],["scrap",12],["medkit",2],["helmet",1],["armor",1],["water",3]]:
		_insert(p.stash, _item(spec[0], spec[1]))
	state.players[id] = p
	reset_transients(id)
	_update_weight(p)

func remove_player(id: int) -> void:
	state.players.erase(id)
	_inputs.erase(id)

func reset_transients(id: int) -> void:
	if not state.players.has(id): return
	var p: Dictionary = state.players[id]
	p.velocity = Vector2.ZERO
	p.sprint = false; p.crouch = false; p.ads = false
	p.anim_seq = 0; p.anim_action = ""; p.anim_time = 0.0; p.anim_duration = 0.0
	p.reloading = false; p.reload_progress = 0.0; p.reload_timer = 0.0; p.fire_timer = 0.0
	p.input_seq = 0; p.input_origin = p.pos; p.input_stamina = p.stamina
	p.input_weight = p.weight; p.input_max_weight = p.max_weight
	_inputs.erase(id)

func _animate(p: Dictionary, action: String, duration: float) -> void:
	p.anim_seq = int(p.get("anim_seq",0)) + 1
	p.anim_action = action; p.anim_time = 0.0; p.anim_duration = duration

func command(id: int, action: String, payload: Dictionary = {}) -> bool:
	last_notice = ""
	if not state.players.has(id):
		return false
	var p: Dictionary = state.players[id]
	match action:
		"move":
			var direction: Variant = payload.get("direction", Vector2.ZERO)
			var aim: Variant = payload.get("aim", p.aim)
			if not direction is Vector2 or not aim is Vector2 or not direction.is_finite() or not aim.is_finite():
				return false
			_inputs[id] = {"direction":direction.limit_length(1.0), "stamp":_clock, "sprint":payload.get("sprint",false) == true, "crouch":payload.get("crouch",false) == true, "ads":payload.get("ads",false) == true}
			if aim.length_squared() > 0.001:
				p.aim = aim.normalized()
			return true
		"transfer": return _transfer(id, payload)
		"split": return _split(p, payload)
		"equip":
			var index: int = _index(payload.get("index"), 24)
			if index < 0 or p.bag[index].is_empty(): return false
			var slot: String = str(Items.definition(p.bag[index].kind).category)
			if not slot in EQUIPMENT: return _reject("这件物品无法装备")
			return _transfer(id, {"from":"bag","index":index,"to":"equipment","target":slot})
		"unequip": return _transfer(id, {"from":"equipment","slot":payload.get("slot",""),"to":"bag"})
		"use": return _use(p, payload)
		"drop": return _drop(p, payload)
		"pickup": return _pickup(p, payload)
		"sort": return _sort(p, payload)
		"reload": return _reload(p)
		"fire": return _fire(p)
		"select_weapon":
			for i in range(p.bag.size()):
				if not p.bag[i].is_empty() and Items.definition(p.bag[i].kind).category == "weapon":
					return command(id, "equip", {"index":i})
			return false
		"rest":
			if not _near(p, "medical"): return _reject("靠近医务床才能休息")
			p.hp = 100.0; p.stamina = 100.0; p.hunger = 100.0; p.thirst = 100.0
			last_notice = "休息完成，状态已恢复"
			_animate(p,"interact",0.8)
			return true
		"craft": return _craft(p)
		"buy_ammo": return _buy_ammo(p)
		"resupply_ammo": return Facilities.resupply_ammo(self,p)
		"train", "reset_targets":
			if not _near(p, "range"): return _reject("靠近靶场控制台重置训练靶")
			for target in state.targets: target.hp = int(target.get("max_hp",100)); target.hits = 0
			last_notice = "训练靶已重置"
			_animate(p,"interact",0.8)
			return true
	return false

func tick(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0: return
	delta = minf(delta, 0.1)
	_clock += delta
	for id in state.players:
		var p: Dictionary = state.players[id]
		var input: Dictionary = _inputs.get(id, {})
		if _clock - float(input.get("stamp", -100)) > INPUT_TIMEOUT: input = {}
		_update_weight(p)
		Movement.step(p,input,delta,solve_motion.bind(int(id)))
		p.anim_time = minf(float(p.get("anim_duration",0.0)),float(p.get("anim_time",0.0)) + delta)
		p.hunger = maxf(0, p.hunger - delta * 0.012)
		p.thirst = maxf(0, p.thirst - delta * 0.018)
		p.fire_timer = maxf(0, float(p.fire_timer) - delta)
		if p.reloading:
			p.reload_timer = maxf(0, float(p.reload_timer) - delta)
			p.reload_progress = 1.0 - p.reload_timer / 1.6
			if p.reload_timer <= 0:
				var weapon: Dictionary = p.equipment.weapon
				if not weapon.is_empty():
					var needed: int = int(Items.definition(weapon.kind).get("magazine",30)) - int(p.ammo)
					p.ammo += _consume(p.bag,"ammo",needed)
					p.magazines[weapon.uid] = p.ammo
				p.reloading = false; p.reload_progress = 0.0
	for i in range(state.shots.size() - 1, -1, -1):
		state.shots[i].ttl -= delta
		if state.shots[i].ttl <= 0: state.shots.remove_at(i)

func solve_motion(from: Vector2, travel: Vector2, id: int) -> Vector2:
	if motion_solver.is_valid(): return motion_solver.call(id,from,travel)
	var pos := from
	var steps := maxi(1,int(ceil(travel.length()/.12)))
	for step in range(steps):
		var part := travel/steps
		var next := pos+Vector2(part.x,0)
		if _free(next): pos = next
		next = pos+Vector2(0,part.y)
		if _free(next): pos = next
	return pos

func _empty_slots(size: int) -> Array:
	return InventoryRules._empty_slots(size)

func _item(kind: String, count: int) -> Dictionary:
	return Inventory._item(self, kind, count)

func _index(value: Variant, size: int) -> int:
	return InventoryRules._index(value, size)

func _reject(message: String) -> bool:
	last_notice = message
	return false

func _near(p: Dictionary, kind: String) -> bool:
	return Facilities._near(self, p, kind)

func _free(pos: Vector2) -> bool:
	if not bounds.grow(-PLAYER_RADIUS).has_point(pos): return false
	for rect in obstacles:
		var closest := Vector2(clampf(pos.x,rect.position.x,rect.end.x),clampf(pos.y,rect.position.y,rect.end.y))
		if pos.distance_squared_to(closest) < PLAYER_RADIUS * PLAYER_RADIUS: return false
	return true

func _insert(container: Array, item: Dictionary) -> bool:
	return InventoryRules._insert(container, item)

func _transfer(id: int, payload: Dictionary) -> bool:
	return Inventory._transfer(self, id, payload)

func _sync_weapon(p: Dictionary, old_uid: String) -> void:
	Inventory._sync_weapon(self, p, old_uid)

func _split(p: Dictionary, payload: Dictionary) -> bool:
	return Inventory._split(self, p, payload)

func _update_weight(p: Dictionary) -> void:
	InventoryRules._update_weight(p)

func _consume(container: Array, kind: String, count: int) -> int:
	return InventoryRules._consume(container, kind, count)

func _count(container: Array, kind: String) -> int:
	return InventoryRules._count(container, kind)

func _use(p: Dictionary, payload: Dictionary) -> bool:
	return Inventory._use(self, p, payload)

func _drop(p: Dictionary, payload: Dictionary) -> bool:
	return Inventory._drop(self, p, payload)

func _pickup(p: Dictionary, payload: Dictionary) -> bool:
	return Inventory._pickup(self, p, payload)

func _sort(p: Dictionary, payload: Dictionary) -> bool:
	return Inventory._sort(self, p, payload)

func _reload(p: Dictionary) -> bool:
	return Combat._reload(self, p)

func _fire(p: Dictionary) -> bool:
	return Combat._fire(self, p)

func _ray_rect(origin: Vector2, direction: Vector2, rect: Rect2) -> float:
	return Combat._ray_rect(self, origin, direction, rect)

func _craft(p: Dictionary) -> bool:
	return Facilities._craft(self, p)

func _buy_ammo(p: Dictionary) -> bool:
	return Facilities._buy_ammo(self, p)

func save_profile(path: String, id: int = 1) -> Error:
	return Profile.save_profile(self, path, id)

func load_profile(path: String, id: int = 1) -> Error:
	return Profile.load_profile(self, path, id)

func _valid_saved_item(item: Variant, seen: Dictionary) -> bool:
	return Profile._valid_saved_item(self, item, seen)
