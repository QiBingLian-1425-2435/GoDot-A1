extends RefCounted
## Main composition adapter for authoritative world changes.
const Map = preload("res://worlds/ground_zero/ground_zero.gd")
const Library = preload("res://worlds/ground_zero/map_library.gd")

static func available(zone: String) -> bool:
	return zone=="bunker" or (zone in ["surface","cave"] and FileAccess.file_exists(Library.ROOT+zone+".json") and FileAccess.file_exists(Library.ROOT+"library.json"))

static func configure(ctx) -> void:
	ctx.session.model.travel_validator = available
	var manifest := FileAccess.open(Library.ROOT+"asset_manifest.json",FileAccess.READ)
	if manifest!=null:
		var data: Dictionary = JSON.parse_string(manifest.get_as_text())
		ctx.session.model.map_revision = str(data.get("revision",""))
	_apply_rules(ctx)

static func sync(ctx) -> void:
	var desired: String = str(ctx.session.model.state.get("world","bunker"))
	if desired==ctx.world_id:
		if ctx.world.has_method("update_doors"):ctx.world.update_doors(ctx.session.model.state.get("doors",{}))
		return
	var different_assets: bool = desired!="bunker" and str(ctx.session.model.state.get("map_revision",""))!=ctx.session.model.map_revision
	if not available(desired) or different_assets:
		print("GROUND_ZERO_ASSET_MISMATCH world=",desired," local=",ctx.session.model.map_revision," host=",ctx.session.model.state.get("map_revision",""))
		ctx.session.set_physics_process(false)
		ctx._return_menu.call_deferred()
		ctx.ui.toast("⟦world_flow.001⟧")
		return
	if is_instance_valid(ctx.global_map):ctx.global_map.set_open(false)
	if is_instance_valid(ctx.field_item_view):ctx.field_item_view.clear()
	ctx.player_physics.reset_world()
	ctx.vision.enabled=false
	ctx.session.reset_world_motion()
	ctx.last_shots.clear()
	ctx.last_reloading.clear()
	for node in ctx.drops.values(): node.free()
	ctx.drops.clear()
	for label in ctx.target_labels: label.free()
	ctx.target_labels.clear()
	var feedback = ctx.get_node_or_null("ShotFeedback")
	if feedback!=null: feedback.free()
	if ctx.world.has_method("cancel_load") and not ctx.world.loaded:
		ctx.world.cancel_load()
		ctx.remove_child(ctx.world)
	else: ctx.world.free()
	ctx.world_id = desired
	ctx.world_loading = desired!="bunker"
	ctx.session.model.world_ready = not ctx.world_loading
	ctx.player_physics.world_ready = not ctx.world_loading
	ctx.ui.set_world_loading(ctx.world_loading,"⟦world_flow.002⟧" if desired=="surface" else "⟦world_flow.003⟧")
	if desired=="bunker": ctx.world = load("res://worlds/bunker/bunker.gd").new()
	else:
		ctx.world = Map.new()
		ctx.world.zone = desired
		ctx.world.map_loaded.connect(_finish_loading.bind(ctx,ctx.world))
	ctx.world.name = "Bunker" if desired=="bunker" else "GroundZero"
	ctx.add_child(ctx.world)
	ctx.world.visible = ctx.in_game and not ctx.world_loading
	_apply_rules(ctx)
	var player: Dictionary = ctx.session.model.state.players.get(ctx.session.local_id,{})
	var pos: Vector2 = player.get("pos",Vector2.ZERO)
	ctx.camera_focus = Vector3(pos.x,float(player.get("height",0)),pos.y)
	ctx.camera.far = 220
	ctx.ui.close_inventory()
	for child in ctx.get_children():
		if child is DirectionalLight3D:
			child.light_color = Color("c3d9e8") if desired=="bunker" else Color("fff0d9")
			child.light_energy = .05 if desired=="cave" else .42
		if child is WorldEnvironment:
			child.environment.ambient_light_energy = .14 if desired=="cave" else .3
			child.environment.ambient_light_color = Color("91afc7") if desired=="bunker" else Color("d6d9ce")
			child.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR

static func _finish_loading(ctx, map) -> void:
	if not is_instance_valid(ctx) or ctx.world!=map: return
	await ctx.get_tree().physics_frame
	if not is_instance_valid(ctx) or not is_instance_valid(map) or ctx.world!=map: return
	_apply_rules(ctx)
	ctx.world_loading = false
	ctx.player_physics.world_ready = true
	ctx.session.model.world_ready = true
	ctx.vision.update(ctx,0)
	ctx.world.visible=ctx.in_game
	ctx.ui.set_world_loading(false,"")
	if ctx.world_id=="surface":ctx.ui.toast("⟦world_flow.004⟧")
	if ctx.session.mode=="host": ctx.session._broadcast_snapshot(true)

static func _apply_rules(ctx) -> void:
	var model = ctx.session.model
	model.obstacles.assign(ctx.world.obstacles())
	model.stations = ctx.world.interactions().duplicate(true)
	model.field_placement=func(from:Vector3,to:Vector3)->Dictionary:
		if ctx.world_id=="bunker":return {"position":to} if ctx.session.model._free(Vector2(to.x,to.z)) else {}
		var query:=PhysicsRayQueryParameters3D.create(from+Vector3(0,.7,0),to+Vector3(0,.7,0),1)
		if not ctx.get_world_3d().direct_space_state.intersect_ray(query).is_empty():return {}
		return ctx.player_physics.safe_standing_position(to)
	model.loot_reachable=func(uid:String,from:Vector3)->bool:
		if not ctx.world.has_method("can_reach_loot") or not ctx.world.can_reach_loot(uid,from):return false
		for station in ctx.session.model.stations:
			if station.get("uid")==uid:return not ctx.session.model.FieldItems.blocks_sight(ctx.session.model.state.field_effects,from+Vector3.UP,Vector3(station.pos.x,station.height+.5,station.pos.y))
		return false
	model.door_reachable=ctx.world.can_reach_door if ctx.world.has_method("can_reach_door") else Callable()
	model.door_clearance=ctx.world.can_close_door if ctx.world.has_method("can_close_door") else Callable()
	for station in model.stations:
		if station.get("kind","")=="door" and not model.state.doors.has(station.uid):model.state.doors[station.uid]=station.initial_open
	if ctx.world.has_method("update_doors"):ctx.world.update_doors(model.state.doors)
	model.bounds = Rect2(-15,-11,30,22) if ctx.world_id=="bunker" else Rect2(0,-1024,1024,1024)
	model.shot_query = Callable() if ctx.world_id=="bunker" else ctx.player_physics.shot_hit
	ctx.player_physics.spatial_enabled = ctx.world_id!="bunker"
	if ctx.world_id=="bunker":
		for station in model.stations:
			if station.kind=="exit":
				station.kind = "travel"
				station.uid = "bunker_to_surface"
				station.world = "bunker"
				station.destination = "surface"
				station.spawn = Library.source_location("surface","Special/BunkerEntry") if available("surface") else Vector3.ZERO
	ctx.ui.set_stash_access(ctx.world_id=="bunker")
