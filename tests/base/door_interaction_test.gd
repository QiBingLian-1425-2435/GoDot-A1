extends SceneTree
const Main=preload("res://app/main.gd")
var game
var checks:=0
var failures:=0
func _initialize():call_deferred("run")
func check(ok: bool, message: String):
	checks+=1;print("PASS: " if ok else "FAIL: ",message)
	if not ok:failures+=1
func run():
	game=Main.new();game.smoke=true;game.elapsed=-10000;game.capture_mode="base";root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.session.set_physics_process(false)
	var model=game.session.model
	var p: Dictionary=model.state.players[1]
	p.pos=Vector2(0,-8.2);game.session.send("travel",{"route":"bunker_to_surface"})
	while game.world_loading:await process_frame
	await physics_frame;await physics_frame
	var count:=0
	for entity in game.world.data.entities:
		if entity.type!="Door":continue
		var uid:=str(int(entity.id))
		var station: Dictionary={}
		for candidate in model.stations:
			if candidate.get("uid")==uid:station=candidate;break
		var body: StaticBody3D
		for part in game.world._door_nodes[uid]:
			if part.node is StaticBody3D and part.node.get_meta("source_id")==int(entity.data.doorCollider.m_PathID):body=part.node;break
		if body==null:continue
		count+=1
		var shape: CollisionShape3D=body.get_child(0)
		var center: Vector3=body.transform*shape.position
		check(Vector2(center.x,center.z).distance_to(station.pos)<.8,"door interaction is at real doorway "+uid+" offset="+str(Vector2(center.x,center.z).distance_to(station.pos)))
		var normal: Vector3=body.basis.z.normalized() if shape.shape.size.z<shape.shape.size.x else body.basis.x.normalized()
		for side in [-1,1]:
			var foot:=Vector3(station.pos.x,float(station.height),station.pos.y)
			var start: Vector3=foot+normal*1.1*side
			var safe: Dictionary=game.player_physics.safe_standing_position(start)
			check(not safe.is_empty(),"door "+uid+" side "+str(side)+" has a walkable approach")
			if safe.is_empty():continue
			p.pos=Vector2(safe.position.x,safe.position.z);p.height=safe.position.y;p.aim=Vector2(normal.x,normal.z)*side
			model.state.doors[uid]=false;game.world.update_doors(model.state.doors)
			await physics_frame
			game._update_actors(1);game.vision.update(game,.06);game._update_interaction()
			check(game.nearest.get("uid")==uid and game.ui._interaction.text=="E   开门","nearby real E prompt selects closed door from side "+str(side)+" / "+uid)
			if side==1 and uid=="43925":await capture("closed")
			var blocked: Vector3=safe.position
			for i in range(40):blocked=game.player_physics.prediction_body.move_spatial(blocked,-Vector2(normal.x,normal.z)*side*.06)
			check((blocked-foot).dot(normal)*side>-.3,"closed leaf blocks walking through "+uid)
			game._interact();await physics_frame
			check(model.state.doors[uid] and game.world._door_open[uid],"E opens the host-confirmed leaf "+uid)
			game._update_interaction()
			check(game.ui._interaction.text=="E   关门","opened doorway remains reachable for closing "+uid)
			var traversed:=false
			# An open leaf occupies one edge; include a short sidestep around it.
			for lateral in [0,-.12,.12,-.24,.24,-.36,.36]:
				var crossed: Vector3=safe.position
				var tangent:=Vector2(-normal.z,normal.x)
				for i in range(4):crossed=game.player_physics.prediction_body.move_spatial(crossed,tangent*float(lateral)/4)
				for i in range(40):crossed=game.player_physics.prediction_body.move_spatial(crossed,-Vector2(normal.x,normal.z)*side*.06)
				if (crossed-foot).dot(normal)*side<-.4:traversed=true;break
			if not traversed:traversed=navigate_door(safe.position,foot,normal,side)
			check(traversed,"actual player capsule passes through opened doorway "+uid)
			if side==1 and uid=="43925":await capture("open")
			var occupant=game.player_physics.PlayerBody.instantiate()
			game.add_child(occupant);occupant.position=foot
			await physics_frame;await physics_frame
			check(not model.command(1,"door",{"uid":uid}) and model.state.doors[uid],"host refuses closing through a real player capsule "+uid)
			occupant.free()
			await physics_frame;await physics_frame
			game._interact();await physics_frame
			check(not model.state.doors[uid],"E closes the clear doorway "+uid)
		var from:=Vector3(station.pos.x,station.height,station.pos.y)+normal*1.1
		p.pos=Vector2(from.x,from.z);p.height=from.y
		var wall:=StaticBody3D.new();wall.collision_layer=17;wall.collision_mask=0
		var wall_shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(.3,2,.3);wall_shape.shape=box;wall.add_child(wall_shape)
		wall.position=from-normal*.55+Vector3(0,.8,0);game.add_child(wall);await physics_frame;await physics_frame
		game._update_interaction()
		check(game.nearest.get("uid")!=uid and not model.command(1,"door",{"uid":uid}),"intervening wall hides prompt and host rejects opening "+uid)
		wall.free();await physics_frame
		p.height=station.height+3;game._update_interaction()
		check(game.nearest.get("uid")!=uid and not model.command(1,"door",{"uid":uid}),"different floor cannot operate door "+uid)
		p.pos=station.pos+Vector2(20,0)
		check(not model.command(1,"door",{"uid":uid}),"host rejects distant opening "+uid)

	check(count==4,"all four source house doors have real physical interaction targets")
	game.queue_free();await process_frame
	print("DOOR_INTERACTION ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)



func navigate_door(origin: Vector3, foot: Vector3, normal: Vector3, side: int) -> bool:
	var queue: Array[Vector3]=[origin]
	var seen: Dictionary={}
	var index:=0
	while index<queue.size() and index<2500:
		var point:=queue[index];index+=1
		for i in range(8):
			var at: Vector3=game.player_physics.prediction_body.move_spatial(point,Vector2.from_angle(TAU*i/8)*.1)
			if (at-foot).dot(normal)*side<-.4:return true
			if Vector2(at.x-foot.x,at.z-foot.z).length()>1.5:continue
			var key:=Vector3i(roundi(at.x/.04),roundi(at.y/.06),roundi(at.z/.04))
			if seen.has(key) or at.distance_to(point)<.01:continue
			seen[key]=true;queue.append(at)
	print("DOOR_ROUTE_SEARCH states=",index)
	return false

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless":return
	game._update_camera(1);game._refresh_ui();await process_frame;await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	check(root.get_texture().get_image().save_png("res://artifacts/door_"+label+".png")==OK,"visible "+label+" door evidence saved")
