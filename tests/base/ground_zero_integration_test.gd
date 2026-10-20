extends SceneTree
const Main = preload("res://app/main.gd")
var failures := 0
var checks := 0
var game
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	print("PASS: " if value else "FAIL: ",message)
	if not value: failures += 1

func frames(count: int) -> void:
	for i in range(count): await physics_frame

func map_ready() -> void:
	while game.world_loading: await process_frame
	await frames(3)

func run() -> void:
	game = Main.new()
	game.smoke = true; game.elapsed = -10000; game.capture_mode = "base"
	root.add_child(game)
	game.set_physics_process(false)
	await frames(3)
	var model = game.session.model
	var player: Dictionary = model.state.players[1]
	check(not model.command(1,"travel",{"route":"bunker_to_surface"}),"remote entrance requests are rejected by distance")
	player.pos = Vector2(0,-8.2)
	game._update_interaction()
	check(game.nearest.get("uid")=="bunker_to_surface","the normal E interaction selects the exploration entrance")
	game._interact()
	game.session.set_physics_process(false)
	await map_ready()
	check(game.world_id=="surface" and model.state.world=="surface","the real main scene replaces the bunker with Ground Zero")
	check(game.world.data.renderers.size()>48000 and game.world._collider_count>14000,"complete source layout, vegetation and collisions are mounted")
	var spawn: Vector2 = player.pos
	for i in range(3): model.tick(1.0/60)
	print("GROUND_ZERO_SPAWN pos=",player.pos," height=",player.height," source_terrain=",game.world.terrain_height(spawn))
	var moved := 0.0
	for direction in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]:
		player.pos=spawn; player.height=-1.13
		model.command(1,"move",{"direction":direction,"aim":direction})
		for i in range(15):
			model.command(1,"move",{"direction":direction,"aim":direction})
			model.tick(1.0/60)
		moved = maxf(moved,spawn.distance_to(player.pos))
		print("GROUND_ZERO_WALK direction=",direction," distance=",spawn.distance_to(player.pos)," height=",player.height)
		check(spawn.distance_to(player.pos)<1.1,"walking does not cause a large collision recovery from hidden trigger volumes")
	check(moved>.5,"a spawned duck can walk away from the original bunker entrance")
	for path in ["StartPoints/StartPoint_1","QuestLocations/LetterEquipmentMercent"]:
		var location: Vector3=game.world.Library.source_location("surface",path)
		player.pos=Vector2(location.x,location.z);player.height=location.y
		model.reset_transients(1)
		for i in range(8):
			model.command(1,"move",{"direction":Vector2.RIGHT})
			model.tick(1.0/60)
		var walked: float=Vector2(player.pos).distance_to(Vector2(location.x,location.z))
		check(walked>.35 and walked<.65 and absf(float(player.height)-location.y)<.35,"the original elevated platform is walkable: "+path)
	check(not model.command(1,"transfer",{"from":"stash","to":"bag","index":0}),"the host rejects access to the bunker stash while exploring")
	var door: Dictionary={}
	for station in model.stations:
		if station.get("kind","")=="door":door=station;break
	check(not door.is_empty() and game.world._door_nodes.has(door.uid),"original door leaves and colliders are connected")
	if not door.is_empty() and game.world._door_nodes.has(door.uid):
		check(not model.command(1,"door",{"uid":door.uid}),"door requests from outside the doorway are rejected")
		player.pos=door.pos+Vector2(0,1.9);player.height=door.height
		game.session.send("door",{"uid":door.uid})
		check(model.state.doors[door.uid] and game.world._door_open[door.uid],"opening a door applies its original open pose to the live map")
		var blocker: Dictionary={}
		for part in game.world._door_nodes[door.uid]:
			if part.node is StaticBody3D:blocker=part;break
		if not blocker.is_empty():
			var collider: CollisionShape3D=blocker.node.get_child(0)
			var center: Vector3=blocker.closed*collider.position
			player.pos=Vector2(center.x,center.z);player.height=door.height
			model.command(1,"move",{"direction":Vector2.ZERO});model.tick(1.0/60)
			await frames(2)
			check(not model.command(1,"door",{"uid":door.uid}) and model.state.doors[door.uid],"a door cannot close through a player's actual collision capsule")
		player.pos=door.pos+Vector2(0,1.9);player.height=door.height
		model.tick(1.0/60);await frames(2)
		game.session.send("door",{"uid":door.uid})
		check(not model.state.doors[door.uid],"a clear doorway can close again")
	var shortcut: Dictionary={}
	for route in model.stations:
		if route.get("scope","")=="player":shortcut=route
	check(not shortcut.is_empty(),"the original same-map teleporters are connected")
	if not shortcut.is_empty():
		model.add_player(2,"shortcut fixture")
		var other: Vector2=model.state.players[2].pos
		var revision:=int(model.state.world_revision)
		player.pos=shortcut.pos;player.height=shortcut.height
		check(model.command(1,"travel",{"route":shortcut.uid}) and player.pos.distance_to(Vector2(shortcut.spawn.x,shortcut.spawn.z))<.01 and model.state.players[2].pos==other and int(model.state.world_revision)==revision,"same-map travel moves only its requesting player and preserves the party world")
		model.remove_player(2)
	player.pos=spawn; player.height=-1.13
	game._update_actors(1)
	game._update_camera(1)
	await capture("surface")
	var portal: Dictionary = {}
	for route in model.stations:
		if route.get("destination")=="cave": portal=route
	check(not portal.is_empty(),"the source cave teleporter is connected")
	if not portal.is_empty():
		player.pos=portal.pos; player.height=portal.height
		game.session.send("travel",{"route":portal.uid})
		await map_ready()
		check(game.world_id=="cave" and model.state.phase=="exploration","the party can enter the original cave")
		for i in range(3): model.tick(1.0/60)
		print("GROUND_ZERO_CAVE pos=",player.pos," height=",player.height)
		game._update_actors(1);game._update_camera(1)
		await capture("cave")
		var back: Dictionary = model.stations[0]
		player.pos=back.pos;player.height=back.height
		game.session.send("travel",{"route":back.uid})
		await map_ready()
		check(game.world_id=="surface","the cave exit returns the party to the source surface portal")
	player.pos=spawn;player.height=-1.13
	game.session.send("travel",{"route":"surface_to_bunker"})
	await frames(3)
	check(game.world_id=="bunker" and model.state.targets.size()==3,"returning restores the bunker and training targets")
	check(not game.player_physics.spatial_enabled and game.world.obstacles().size()==43,"map replacement removes exploration physics and restores base collision")
	player.pos=Vector2(0,-8.2);player.height=0
	game.session.send("travel",{"route":"bunker_to_surface"})
	check(game.world_loading and not model.world_ready,"loading keeps movement and shared map interactions gated")
	await process_frame
	game._return_menu()
	await frames(5)
	check(game.world_id=="bunker" and not game.in_game and model.world_ready and not game.world_loading,"leaving during loading safely restores the base and clears the loading gate")
	game.queue_free();await process_frame
	print("GROUND_ZERO_INTEGRATION ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)

func capture(zone: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await frames(10)
	await RenderingServer.frame_post_draw
	var path := "res://artifacts/ground_zero_"+zone+"_integrated.png"
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	get_root().get_texture().get_image().save_png(path)
	print("GROUND_ZERO_CAPTURE ",ProjectSettings.globalize_path(path))
