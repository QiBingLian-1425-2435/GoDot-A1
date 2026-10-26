extends RefCounted
const Texts = preload("res://features/localization/game_text.gd")

const InventoryRules = preload("res://features/inventory/base_inventory_rules.gd")
const Enemies = preload("res://features/enemies/enemy_rules.gd")
var enemy_sight: Callable
var enemy_move: Callable
const Inventory = preload("res://features/inventory/base_inventory_system.gd")
const Combat = preload("res://features/combat/combat_system.gd")
const Profile = preload("res://features/persistence/profile_store.gd")
const Facilities = preload("res://features/base/facility_system.gd")
const Movement = preload("res://features/player/movement_rules.gd")
const WorldTravel = preload("res://features/exploration/world_travel.gd")
## Host-authoritative base rules. No files are accessed until an explicit profile call.
const Loot=preload("res://features/exploration/container_loot.gd")
const FieldItems=preload("res://features/exploration/field_items.gd")
const Camp=preload("res://features/base/camp_upgrades.gd")
const Trade=preload("res://features/inventory/item_trade.gd")
const Souls = preload("res://features/rescue/soul_rules.gd")
var rescue_reachable: Callable
var soul_height: Callable
var field_placement:Callable
var loot_reachable:Callable
const Items = preload("res://features/inventory/item_catalog.gd")
const EQUIPMENT := ["weapon", "helmet", "armor", "backpack"]
const PLAYER_RADIUS := 0.32
const INPUT_TIMEOUT := 0.35
var bounds := Rect2(-15, -11, 30, 22)
var obstacles: Array[Rect2] = []
var stations: Array = []
var last_notice := ""
var state: Dictionary = {"camp":Camp.initial(),"field_effects":[],"containers":{},"players":{}, "drops":{}, "doors":{}, "infinite_reserve":false, "infinite_stamina":false, "infinite_credits":false, "phase":"base", "world":"bunker", "world_revision":0, "targets":[], "shots":[]}
var world_cache: Dictionary = {}
var travel_validator: Callable
var shot_query: Callable
var map_revision := ""
var world_ready := true
var door_clearance: Callable
var door_reachable: Callable
var _next_uid := 1
var _clock := 0.0
var _inputs: Dictionary = {}
var motion_solver: Callable # Main installs the real CharacterBody3D adapter; rule fixtures remain pure.
var recovery_solver: Callable
var _recovery_after: Dictionary = {}

func _init() -> void:
	state.corpses = {}
	state.enemies = {}; state.enemies_seeded = false
	for i in range(3):
		state.targets.append({"id":i, "pos":Vector2(8 + i * 2, 8.8), "hp":100, "max_hp":100, "hits":0})

func add_player(id: int, player_name: String) -> void:
	if id <= 0 or state.players.has(id) or state.players.size() >= 5:
		return
	var bag := _empty_slots(24)
	var stash := _empty_slots(48)
	var rifle := _item("rifle", 1)
	var p := {"id":id, "name":Texts.clip(player_name.strip_edges(),24), "pos":Vector2(-1 + state.players.size() * 0.9, 4), "aim":Vector2.UP, "hp":100.0, "stamina":100.0, "hunger":85.0, "thirst":85.0, "bag":bag, "stash":stash, "equipment":{"weapon":rifle,"helmet":{},"armor":{},"backpack":_item("backpack",1)}, "ammo":20, "reloading":false, "reload_progress":0.0, "shots":0, "credits":500, "sprint":false, "sprint_exhausted":false, "crouch":false, "ads":false, "weight":0.0, "max_weight":44.0, "magazines":{rifle.uid:20}, "reload_timer":0.0, "fire_timer":0.0}
	for spec in [["ammo",60],["bandage",3],["water",2],["canned_food",2],["scrap",8],["medkit",1],["pistol",1]]:
		_insert(p.bag, _item(spec[0], spec[1]))
	for spec in [["ammo",60],["scrap",12],["medkit",2],["helmet",1],["armor",1],["water",3]]:
		_insert(p.stash, _item(spec[0], spec[1]))
	state.players[id] = p
	p.height = 0.0
	p.life = "alive"; p.possessing = 0; p.rescue = {}; p.corpse_uid = ""
	p.san = 100.0
	if state.get("world","bunker")!="bunker" and not state.players.is_empty():
		var leader: Dictionary = state.players.values()[0]
		p.pos = Vector2(leader.pos)+Vector2(.9,0)
		p.height = float(leader.get("height",0))
	reset_transients(id)
	Camp.refresh_player(self,p)

func remove_player(id: int) -> void:
	if state.players.has(id): Loot.close(self,state.players[id])
	_recovery_after.erase(id)
	state.players.erase(id)
	_inputs.erase(id)

## Authority-only combat entry: enemies must select and damage only living players.
func enemy_targets() -> Array:
	return state.players.values().filter(func(p): return Souls.alive(p))

func enemy_damage(id: int, amount: float) -> bool:
	var p: Dictionary = state.players.get(id,{})
	if not world_ready or not Souls.alive(p) or not is_finite(amount) or amount<=0: return false
	p.hp = maxf(0,float(p.hp)-amount)
	Souls.reconcile(self,p)
	return true

func change_san(id: int, amount: float) -> bool:
	var p: Dictionary = state.players.get(id,{})
	if not world_ready or not Souls.alive(p) or not is_finite(amount): return false
	p.san = clampf(float(p.get("san",100))+amount,0,100)
	Souls.reconcile(self,p)
	return true

func reset_transients(id: int) -> void:
	if not state.players.has(id): return
	var p: Dictionary = state.players[id]
	Loot.close(self,p)
	var roll_seen:int=int(p.get("roll",{}).get("seen",0))
	p.roll=Movement.empty_roll();p.roll.seen=roll_seen
	p.input_roll=p.roll.duplicate(true)
	p.pending_use={}
	p.velocity = Vector2.ZERO
	p.sprint = false; p.sprint_exhausted = false; p.crouch = false; p.ads = false
	p.anim_seq = 0; p.anim_action = ""; p.anim_time = 0.0; p.anim_duration = 0.0
	p.reloading = false; p.reload_progress = 0.0; p.reload_timer = 0.0; p.fire_timer = 0.0
	p.input_seq = 0; p.input_origin = p.pos; p.input_stamina = p.stamina; p.input_sprint_exhausted = false
	p.input_weight = p.weight; p.input_max_weight = p.max_weight
	p.input_height = p.get("height",0.0)
	_inputs.erase(id)

func _animate(p: Dictionary, action: String, duration: float) -> void:
	p.anim_seq = int(p.get("anim_seq",0)) + 1
	p.anim_action = action; p.anim_time = 0.0; p.anim_duration = duration

func command(id: int, action: String, payload: Dictionary = {}) -> bool:
	last_notice = ""
	if not world_ready and action in ["move","fire","drop","pickup","travel","door","use","buy","sell","search","craft_item","loot_take"]: return false
	if not state.players.has(id):
		return false
	var p: Dictionary = state.players[id]
	Souls.reconcile(self,p)
	if action in ["soul_speed","suicide","soul_wait","possess","release_soul","rescue","rescue_cancel","return_camp"]:
		if not world_ready: return false
		return Souls.command(self,p,action,payload)
	if not Souls.alive(p) and not ((Souls.zombie(p) or p.get("life","")=="soul") and action=="move"): return _reject("⟦base_model.001⟧")
	if not p.get("rescue",{}).is_empty() and action != "move": p.rescue = {}
	if state.get("world","bunker")!="bunker" and ((action=="transfer" and (payload.get("from")=="stash" or payload.get("to")=="stash")) or (action in ["sort","split"] and payload.get("container")=="stash")):
		return _reject("⟦base_model.002⟧")
	if p.get("roll",{}).get("active",false) and action not in ["move","loot_close"]:return _reject("⟦base_model.003⟧")
	match action:
		"unstuck":
			if not world_ready:return _reject("⟦base_model.004⟧")
			if _clock<float(_recovery_after.get(id,0)):return _reject("⟦base_model.005⟧")
			if not recovery_solver.is_valid():return _reject("⟦base_model.006⟧")
			var safe: Dictionary=recovery_solver.call(id)
			if safe.is_empty():return _reject("⟦base_model.007⟧")
			var target: Vector3=safe.position
			p.pos=Vector2(target.x,target.z);p.height=target.y
			p.relocation_seq=int(p.get("relocation_seq",0))+1
			reset_transients(id)
			_recovery_after[id]=_clock+10.0
			last_notice="⟦base_model.008⟧"
			return true
		"camp_upgrade":return Camp.upgrade(self,p,payload)
		"buy","sell":return Trade.trade(self,p,action,payload)
		"craft_item":return Trade.craft(self,p,str(payload.get("kind","")))
		"search":
			var uid := str(payload.get("uid",""))
			if state.corpses.has(uid): return Loot.open(self,p,state.corpses[uid])
			return FieldItems.search(self,p,uid)
		"loot_take":return Loot.take(self,p,payload)
		"loot_close":return Loot.close(self,p,str(payload.get("uid","")))
		"door": return WorldTravel.toggle_door(self,id,payload)
		"travel": return WorldTravel.travel(self,id,payload)
		"move":
			var direction: Variant = payload.get("direction", Vector2.ZERO)
			var aim: Variant = payload.get("aim", p.aim)
			if not direction is Vector2 or not aim is Vector2 or not direction.is_finite() or not aim.is_finite():
				return false
			var roll_direction:Variant=payload.get("roll_direction",direction)
			if not roll_direction is Vector2 or not roll_direction.is_finite():return false
			_inputs[id] = {"roll_direction":roll_direction.limit_length(1.0),"direction":direction.limit_length(1.0), "stamp":_clock, "sprint":payload.get("sprint",false) == true, "crouch":payload.get("crouch",false) == true, "ads":payload.get("ads",false) == true,"roll_seq":clampi(int(payload.get("roll_seq",0)),0,2147483647) if payload.get("roll_seq",0) is int else 0}
			if aim.length_squared() > 0.001:
				p.aim = aim.normalized()
			return true
		"transfer": return _transfer(id, payload)
		"split": return _split(p, payload)
		"equip":
			var index: int = _index(payload.get("index"), 24)
			if index < 0 or p.bag[index].is_empty(): return false
			var slot: String = str(Items.definition(p.bag[index].kind).category)
			if not slot in EQUIPMENT: return _reject("⟦base_model.009⟧")
			return _transfer(id, {"from":"bag","index":index,"to":"equipment","target":slot})
		"unequip": return _transfer(id, {"from":"equipment","slot":payload.get("slot",""),"to":"bag"})
		"use": return _use(p, payload)
		"drop": return _drop(p, payload)
		"pickup":
			var drop:Dictionary=state.drops.get(str(payload.get("uid","")),{})
			if not drop.is_empty() and FieldItems.blocks_sight(state.field_effects,Vector3(p.pos.x,float(p.get("height",0))+1,p.pos.y),Vector3(drop.pos.x,float(drop.get("height",0))+.2,drop.pos.y)):return _reject("⟦base_model.010⟧")
			return _pickup(p,payload)
		"sort": return _sort(p, payload)
		"set_infinite_reserve":
			if id != 1: return _reject("⟦base_model.011⟧")
			if not payload.get("enabled") is bool: return false
			state.infinite_reserve = payload.enabled
			return true
		"set_infinite_stamina":
			if id != 1: return _reject("⟦base_model.012⟧")
			if not payload.get("enabled") is bool: return false
			state.infinite_stamina = payload.enabled
			return true
		"set_infinite_credits":
			if id != 1: return _reject("⟦settings.infinite_credits_host_only⟧")
			if not payload.get("enabled") is bool: return false
			state.infinite_credits = payload.enabled
			return true
		"reload": return _reload(p)
		"fire": return _fire(p)
		"select_weapon":
			for i in range(p.bag.size()):
				if not p.bag[i].is_empty() and Items.definition(p.bag[i].kind).category == "weapon":
					return command(id, "equip", {"index":i})
			return false
		"rest":
			if not _near(p, "medical"): return _reject("⟦base_model.013⟧")
			p.hp = p.get("max_hp",100.0); p.stamina = p.get("max_stamina",100.0); p.hunger = 100.0; p.thirst = 100.0
			_update_weight(p)
			last_notice = "⟦base_model.014⟧"
			_animate(p,"interact",0.8)
			return true
		"craft": return _craft(p)
		"buy_ammo": return _buy_ammo(p)
		"resupply_ammo": return Facilities.resupply_ammo(self,p)
		"train", "reset_targets":
			if not _near(p, "range"): return _reject("⟦base_model.015⟧")
			for target in state.targets: target.hp = int(target.get("max_hp",100)); target.hits = 0
			last_notice = "⟦base_model.016⟧"
			_animate(p,"interact",0.8)
			return true
	return false

func tick(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0: return
	delta = minf(delta, 0.1)
	_clock += delta
	Souls.tick(self,0.0)
	Loot.tick(self,delta)
	Enemies.tick(self,delta)
	for id in state.players:
		var p: Dictionary = state.players[id]
		if p.get("life","")=="soul":
			p.soul_bounds=bounds
			var soul_input: Dictionary = _inputs.get(id,{})
			if _clock-float(soul_input.get("stamp",-100))>INPUT_TIMEOUT:soul_input={}
			Movement.step(p,soul_input,delta,solve_motion.bind(int(id)))
			continue
		if not Souls.mobile(p): continue
		if Souls.zombie(p):
			var zombie_input: Dictionary = _inputs.get(id,{})
			if _clock-float(zombie_input.get("stamp",-100))>INPUT_TIMEOUT: zombie_input={}
			Movement.step(p,zombie_input,delta,solve_motion.bind(int(id)))
			continue
		var pending:Dictionary=p.get("pending_use",{})
		if not pending.is_empty():
			pending.remaining-=delta
			if pending.remaining<=0:p.hp=minf(float(p.get("max_hp",100)),float(p.hp)+float(pending.hp));p.pending_use={}
		if float(p.hp)<=0:
			Souls.die(self,p)
			continue
		var input: Dictionary = _inputs.get(id, {})
		if _clock - float(input.get("stamp", -100)) > INPUT_TIMEOUT: input = {}
		var in_camp: bool = state.get("world", "bunker") == "bunker"
		if in_camp:
			_restore_camp_status(p)
		else:
			p.hunger = maxf(0, p.hunger - delta * 0.012)
		_update_weight(p)
		p.infinite_stamina = bool(state.get("infinite_stamina",false))
		Movement.step(p,input,delta,solve_motion.bind(int(id)))
		p.anim_time = minf(float(p.get("anim_duration",0.0)),float(p.get("anim_time",0.0)) + delta)
		if in_camp:
			_restore_camp_status(p)
		else:
			p.thirst = maxf(0, p.thirst - delta * 0.018)
		p.fire_timer = maxf(0, float(p.fire_timer) - delta)
		if p.reloading:
			p.reload_timer = maxf(0, float(p.reload_timer) - delta)
			var reload_time := 1.6
			var reload_weapon: Dictionary = p.equipment.weapon
			if not reload_weapon.is_empty(): reload_time = float(Items.definition(reload_weapon.kind).get("reload_time",1.6))
			p.reload_progress = 1.0 - p.reload_timer / reload_time
			if p.reload_timer <= 0:
				var weapon: Dictionary = p.equipment.weapon
				if not weapon.is_empty():
					var needed: int = int(Items.definition(weapon.kind).get("magazine",30)) - int(p.ammo)
					p.ammo += needed if state.get("infinite_reserve",false) else _consume(p.bag,"ammo",needed)
					p.magazines[weapon.uid] = p.ammo
				p.reloading = false; p.reload_progress = 0.0
	Souls.tick(self,delta)
	for i in range(state.shots.size() - 1, -1, -1):
		state.shots[i].ttl -= delta
		if state.shots[i].ttl <= 0: state.shots.remove_at(i)

	for i in range(state.field_effects.size()-1,-1,-1):
		state.field_effects[i].ttl-=delta
		if state.field_effects[i].ttl<=0:state.field_effects.remove_at(i)

func _restore_camp_status(p: Dictionary) -> void:
	p.hp = float(p.get("max_hp", 100.0))
	p.stamina = float(p.get("max_stamina", 100.0))
	p.hunger = 100.0
	p.thirst = 100.0
	p.san = 100.0

func solve_motion(from: Vector2, travel: Vector2, id: int) -> Variant:
	var p: Dictionary = state.players.get(id,{})
	if p.get("life","")=="soul":
		var pos := from+travel
		var height: float = soul_height.call(pos,float(p.get("height",0))) if soul_height.is_valid() else float(p.get("height",0))
		return Vector3(pos.x,height,pos.y)
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
