extends Node3D
## World physics adapter and presentation lifecycle; only the host seeds enemies.
const Body=preload("res://features/player/player.tscn")
const View=preload("res://features/enemies/enemy_view.gd")
var bodies:Dictionary={}
var views:Dictionary={}
var world_instance:=0
func clear():
	for node in bodies.values():node.free()
	for node in views.values():node.free()
	bodies.clear();views.clear();world_instance=0
func bind_world(ctx):
	ctx.session.model.enemy_sight=clear_sight
	ctx.session.model.enemy_move=move_enemy
func clear_sight(from:Vector3,to:Vector3)->bool:
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,1|16)).is_empty()
func body_for(id:int):
	if not bodies.has(id):
		var body=Body.instantiate();add_child(body);body.collision_layer=0;bodies[id]=body
	return bodies[id]
func move_enemy(id:int,from:Vector3,offset:Vector2)->Vector3:
	var body=body_for(id)
	var result:Vector3=body.move_spatial(from,offset)
	if Vector2(result.x-from.x,result.z-from.z).length()>=offset.length()*.65:return result
	# Limited local steering at corners; every candidate uses the physical capsule.
	var best:=result;var score:float=Vector2(result.x-from.x,result.z-from.z).dot(offset.normalized())
	for angle in [-PI/4,PI/4,-PI/2,PI/2]:
		var candidate:Vector3=body.move_spatial(from,offset.rotated(angle))
		var travel:=Vector2(candidate.x-from.x,candidate.z-from.z)
		var value:=travel.dot(offset.normalized())+travel.length()*.15
		if value>score:best=candidate;score=value
	return best
func spawn_wave(ctx):
	if ctx.session.mode=="client" or ctx.world_id!="surface" or ctx.session.model.state.get("enemies_seeded",false):return
	var model=ctx.session.model
	if model.state.players.is_empty():return
	var first:Dictionary=model.state.players.values()[0]
	var center:Vector2=first.pos
	var probe=body_for(-1)
	var enemies:Dictionary=model.state.enemies
	_spawn_group(ctx,probe,center,6,true)
	for landmark in ["StartPoints/StartPoint_1","StartPoints/StartPoint_2","StartPoints/StartPoint_4","StartPoints/StartPoint_5","QuestLocations/FishingPoint2"]:
		var location:Vector3=ctx.world.Library.source_location("surface",landmark)
		_spawn_group(ctx,probe,Vector2(location.x,location.z),2,false)
	model.state.enemies_seeded=true
	if ctx.session.mode=="host":ctx.session._broadcast_snapshot(true)
func _spawn_group(ctx,probe,center:Vector2,count:int,prefer_visible:bool):
	var enemies:Dictionary=ctx.session.model.state.enemies
	var goal:=enemies.size()+count
	var viewer:Dictionary=ctx.session.model.state.players.values()[0]
	for require_sight in ([true,false] if prefer_visible else [false]):
		for radius in [6.0,9.0,12.0,18.0]:
			for i in range(16):
				var point:Vector2=center+Vector2.from_angle(PI+TAU*i/16)*radius
				var floor_hit:Dictionary=probe._support(point,ctx.world.terrain_height(point)+.1)
				if floor_hit.is_empty() or floor_hit.normal.y<.65:continue
				var at:=Vector3(point.x,probe._feet_height(floor_hit),point.y)
				if not probe.is_clear(at):continue
				if require_sight and not clear_sight(at+Vector3.UP,ctx.session.model.Enemies.at(viewer)+Vector3.UP):continue
				var spaced:=true
				for p in ctx.session.model.state.players.values():
					if Vector2(p.pos).distance_to(point)<5:spaced=false
				for e in enemies.values():
					if Vector2(e.pos).distance_to(point)<4:spaced=false
				if not spaced:continue
				var exits:=0
				for direction in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]:
					if probe.move_spatial(at,direction*.6).distance_to(at)>.4:exits+=1
				if exits<2:continue
				var id:=enemies.size()+1
				enemies[id]=ctx.session.model.Enemies.create(id,at,center-point)
				if enemies.size()>=goal:return
func update(ctx,delta:float):
	bind_world(ctx)
	if not ctx.in_game or ctx.world_loading or ctx.world_id=="bunker":
		if not views.is_empty() or not bodies.is_empty():clear()
		return
	if world_instance!=ctx.world.get_instance_id():clear();world_instance=ctx.world.get_instance_id()
	spawn_wave(ctx)
	var enemies:Dictionary=ctx.session.model.state.get("enemies",{})
	for id in views.keys():
		if not enemies.has(id):views[id].free();views.erase(id)
	for id in enemies:
		if not views.has(id):var view=View.new();add_child(view);views[id]=view
		views[id].update_enemy(enemies[id],delta)
		views[id].visible=ctx.vision.can_see(views[id].position+Vector3(0,.85,0))
