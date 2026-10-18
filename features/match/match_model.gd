extends RefCounted
## Authoritative, transport-independent rules. The presentation only reads state.

const ROUND_SECONDS := 360.0
const CAPACITY := 12.0
const EXTRACT_POSITION := Vector2(8.0, 5.5)
const EXTRACT_RADIUS := 1.5
const EXTRACT_SECONDS := 4.0
const REVIVE_SECONDS := 3.0
const BLEED_SECONDS := 22.0
const MOVE_SPEED := 3.5
const ITEM_TYPES = preload("res://features/inventory/item_catalog.gd").TYPES

var inventory = preload("res://features/inventory/inventory_system.gd").new()

var rescue = preload("res://features/rescue/rescue_system.gd").new()

var extraction = preload("res://features/extraction/extraction_system.gd").new()

var possession = preload("res://features/possession/possession_system.gd").new()

var enemies = preload("res://features/enemies/monster_system.gd").new()

var companions = preload("res://features/companions/companion_system.gd").new()

var navigation = preload("res://features/navigation/navigation_rules.gd").new()

var obstacles: Array[Rect2] = []
var state: Dictionary = {}
## Optional engine collision adapter, injected by the app on all local authorities.
var motion_solver: Callable
var _inputs: Dictionary = {}
var _next_item_id := 1
var _event_serial := 0

var _corpse_clocks: Dictionary:
	get:
		return rescue._corpse_clocks
	set(value):
		rescue._corpse_clocks = value

var _next_corpse_id: int:
	get:
		return rescue._next_corpse_id
	set(value):
		rescue._next_corpse_id = value

var _monster_hit_cooldown: float:
	get:
		return enemies._monster_hit_cooldown
	set(value):
		enemies._monster_hit_cooldown = value

var _monster_pause: float:
	get:
		return enemies._monster_pause
	set(value):
		enemies._monster_pause = value

var _patrol_index: int:
	get:
		return enemies._patrol_index
	set(value):
		enemies._patrol_index = value

var _bot_loot_clock: float:
	get:
		return companions._bot_loot_clock
	set(value):
		companions._bot_loot_clock = value

var _nav: AStarGrid2D:
	get:
		return navigation._nav
	set(value):
		navigation._nav = value

const InventoryRules = preload("res://features/inventory/inventory_rules.gd")

func _init() -> void:
	state = {"phase": "lobby", "round": 0, "time_left": ROUND_SECONDS,
		"players": {}, "loot": [], "corpses": [], "monster": {},
		"events": [], "total_banked": 0, "round_value": 0}
	reset_lobby()

func reset_lobby() -> void:
	state.phase = "lobby"
	state.time_left = ROUND_SECONDS
	state.loot = []
	state.corpses = []
	state.monster = {"pos": Vector2(3.0, -4.0), "mode": "patrol", "target": 0, "alert": 0.0}
	state.round_value = 0
	_inputs.clear()
	_corpse_clocks.clear()
	for id in state.players.keys():
		var old: Dictionary = state.players[id]
		if not old.get("connected", true):
			state.players.erase(id)
			continue
		var fresh := _make_player(int(id), str(old.name), bool(old.bot))
		fresh.banked = old.get("banked", 0)
		state.players[id] = fresh

func _make_player(id: int, display_name: String, bot: bool) -> Dictionary:
	return {"id": id, "name": display_name.left(20), "pos": Vector2(6.3, 4.2),
		"hp": 100.0, "status": "alive", "bag": [], "capacity": CAPACITY,
		"down_left": 0.0, "extract_progress": 0.0, "revive_progress": 0.0,
		"result_value": 0, "possessing": 0, "request_from": 0, "bot": bot,
		"connected": true, "banked": 0, "lost_value": 0, "invulnerable": 0.0,
		"look": Vector2(1, 0), "moving": false, "interacting": false}

func add_player(id: int, display_name: String, bot: bool = false) -> bool:
	if state.phase != "lobby" or state.players.size() >= 5 or state.players.has(id):
		return false
	state.players[id] = _make_player(id, display_name, bot)
	_event("%s 加入了队伍" % display_name)
	return true

func remove_player(id: int) -> void:
	if not state.players.has(id):
		return
	var p: Dictionary = state.players[id]
	_detach(id)
	_clear_requests(id)
	_inputs.erase(id)
	if state.phase == "lobby":
		state.players.erase(id)
	else:
		p.connected = false
		if p.status != "extracted" and p.status != "dead":
			_die(p, "断开连接，遗留物品可搜取")
	_event("%s 已断开连接" % p.name)
	_check_end()

func get_player(id: int) -> Dictionary:
	return state.players.get(id, {})

func bag_weight(player: Dictionary) -> float:
	return InventoryRules.weight(player.get("bag", []))

func bag_value(player: Dictionary) -> int:
	return InventoryRules.value(player.get("bag", []))

func start_round() -> bool:
	if state.phase != "lobby" or state.players.size() < 2:
		_event("需要至少两位队员；独自试玩可选择同行伙伴")
		return false
	reset_lobby()
	state.phase = "raid"
	state.round += 1
	_next_item_id = state.round * 1000 + 1
	_next_corpse_id = state.round * 100 + 1
	_monster_hit_cooldown = 0.0
	_monster_pause = 0.0
	_patrol_index = 0
	_bot_loot_clock = 0.0
	var slot := 0
	for id in state.players:
		state.players[id].pos = Vector2(6.3 - slot * 0.65, 4.2 + (slot % 2) * 0.55)
		slot += 1
	var locations := [Vector2(-8, 3.8), Vector2(-5, 4.3), Vector2(-6, 0),
		Vector2(-8, -4), Vector2(-4, -5), Vector2(0, -5.5), Vector2(2, -1),
		Vector2(5, -5), Vector2(7, -2), Vector2(6, 2), Vector2(0, 3.2), Vector2(4.5, 4.6)]
	var kinds := [0, 1, 3, 4, 2, 5, 0, 5, 4, 3, 1, 2]
	for index in locations.size():
		var item: Dictionary = ITEM_TYPES[kinds[index]].duplicate(true)
		item.id = _next_item_id
		_next_item_id += 1
		item.pos = locations[index]
		state.loot.append(item)
	_build_navigation()
	_event("夜探开始 · 搜集遗物，留意巡游者，带着收获撤离")
	return true

func command(id: int, action: String, payload: Dictionary = {}) -> void:
	if not state.players.has(id):
		return
	if action == "start":
		if id == 1:
			if state.phase == "results":
				reset_lobby()
			start_round()
		return
	if action == "lobby":
		if id == 1 and state.phase == "results":
			reset_lobby()
		return
	var p: Dictionary = state.players[id]
	if action == "detach":
		_detach(id)
		return
	if state.phase != "raid":
		return
	if action == "possession_request":
		_request_possession(p, int(payload.get("target", 0)))
		return
	if action == "possession_accept":
		_accept_possession(p)
		return
	if action == "possession_decline":
		p.request_from = 0
		return
	if p.status != "alive":
		return
	match action:
		"move":
			var direction: Variant = payload.get("direction", Vector2.ZERO)
			if not direction is Vector2 or not direction.is_finite():
				return
			_inputs[id] = {"direction": direction.limit_length(1.0), "interact": bool(payload.get("interact", false)), "age": 0.0}
		"pickup":
			_pickup(p)
		"drop":
			_drop(p, int(payload.get("item_id", -1)))
		"interact":
			_inputs[id] = {"direction": Vector2.ZERO, "interact": true, "age": 0.0}

func tick(delta: float) -> void:
	if state.phase != "raid" or delta <= 0.0 or not is_finite(delta):
		return
	delta = minf(delta, 0.1)
	state.time_left = maxf(0.0, state.time_left - delta)
	_bot_loot_clock -= delta
	for id in state.players:
		var p: Dictionary = state.players[id]
		p.invulnerable = maxf(0.0, p.invulnerable - delta)
		p.moving = false
		p.interacting = false
		if p.status == "downed":
			p.down_left = maxf(0.0, p.down_left - delta)
			if p.down_left <= 0.0:
				_die(p, "未能等到救援")
		if p.status != "alive":
			continue
		if p.bot:
			_bot_input(p)
		var input: Dictionary = _inputs.get(id, {"direction": Vector2.ZERO, "interact": false, "age": 9.0})
		input.age += delta
		if input.age > 0.35:
			input.direction = Vector2.ZERO
			input.interact = false
		var movement: Vector2 = input.direction
		p.interacting = input.interact
		if movement.length_squared() > 0.01:
			p.look = movement.normalized()
			var previous: Vector2 = p.pos
			p.pos = _advance_actor(int(p.id), p.pos, movement * MOVE_SPEED * delta)
			p.moving = previous.distance_squared_to(p.pos) > 0.0001
	_update_interactions(delta)
	_update_monster(delta)
	for p in state.players.values():
		if p.status == "alive":
			if p.pos.distance_to(EXTRACT_POSITION) <= EXTRACT_RADIUS:
				p.extract_progress = minf(EXTRACT_SECONDS, p.extract_progress + delta)
				if p.extract_progress >= EXTRACT_SECONDS:
					_extract(p)
			else:
				p.extract_progress = 0.0
		elif p.status != "extracted":
			p.extract_progress = 0.0
	if state.time_left <= 0.0:
		for p in state.players.values():
			if p.status == "alive" or p.status == "downed":
				_die(p, "钟声响起，未能及时撤离")
		_finish_round()
	else:
		_check_end()

func _pickup(p: Dictionary, quiet: bool = false) -> bool:
	return inventory._pickup(self, p, quiet)

func _drop(p: Dictionary, item_id: int) -> void:
	return inventory._drop(self, p, item_id)

func _loot_corpse(p: Dictionary, corpse: Dictionary, quiet: bool = false) -> bool:
	return inventory._loot_corpse(self, p, corpse, quiet)

func _update_interactions(delta: float) -> void:
	return rescue._update_interactions(self, delta)

func _hurt(p: Dictionary, damage: float) -> void:
	return rescue._hurt(self, p, damage)

func _die(p: Dictionary, reason: String) -> void:
	return rescue._die(self, p, reason)

func _extract(p: Dictionary) -> void:
	return extraction._extract(self, p)

func _check_end() -> void:
	return extraction._check_end(self)

func _finish_round() -> void:
	return extraction._finish_round(self)

func _request_possession(p: Dictionary, target_id: int) -> void:
	return possession._request_possession(self, p, target_id)

func _accept_possession(target: Dictionary) -> void:
	return possession._accept_possession(self, target)

func _detach(id: int) -> void:
	return possession._detach(self, id)

func _clear_requests(id: int) -> void:
	return possession._clear_requests(self, id)

func _update_monster(delta: float) -> void:
	return enemies._update_monster(self, delta)

func _bot_input(p: Dictionary) -> void:
	return companions._bot_input(self, p)

func _build_navigation() -> void:
	return navigation._build_navigation(self)

func _path_direction(from: Vector2, to: Vector2) -> Vector2:
	return navigation._path_direction(self, from, to)

func _nearest_walkable(cell: Vector2i) -> Vector2i:
	return navigation._nearest_walkable(self, cell)

func _move_position(pos: Vector2, offset: Vector2) -> Vector2:
	return navigation._move_position(self, pos, offset)

func _advance_actor(id: int, pos: Vector2, offset: Vector2) -> Vector2:
	var target := _move_position(pos, offset)
	if motion_solver.is_valid():
		return motion_solver.call(id, pos, target - pos)
	return target

func _position_clear(pos: Vector2) -> bool:
	return navigation._position_clear(self, pos)

func _line_clear(from: Vector2, to: Vector2) -> bool:
	return navigation._line_clear(self, from, to)

func _event(message: String, player_id: int = 0) -> void:
	_event_serial += 1
	state.events.append({"id": _event_serial, "serial": _event_serial, "text": message, "player_id": player_id})
	while state.events.size() > 10:
		state.events.pop_front()
