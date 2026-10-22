extends RefCounted
## Local perception only. Hidden objects retain their authority, simulation and collision.
const Rules=preload("res://features/visibility/vision_rules.gd")
const RAY_COUNT := 256
const OCCLUDER_MASK := 16
var roof_cutaway:=false
var enabled:=false
var observer:=Vector3.ZERO
var aim:=Vector2.UP
var space: PhysicsDirectSpaceState3D
var ray_texture: ImageTexture
var _ray_image: Image
var _clock:=1.0
var _world_id:=0

func update(ctx, delta: float) -> void:
	var active: bool=ctx.in_game and not ctx.world_loading and ctx.world_id!="bunker"
	var current_world: int=ctx.world.get_instance_id()
	if current_world!=_world_id:
		_world_id=current_world;_clock=1.0
	enabled=active
	if is_instance_valid(ctx.tracer_node):ctx.tracer_node.material_override.set_shader_parameter("vision_enabled",enabled)
	if not enabled:
		roof_cutaway=false
		if ctx.world.has_method("set_vision"):ctx.world.set_vision(false,{})
		if ctx.world_loading:
			for actor in ctx.actors.values():actor.visible=false
			for drop in ctx.drops.values():drop.visible=false
			for label in ctx.target_labels:label.visible=false
		return
	var player: Dictionary=ctx.session.model.state.players.get(ctx.session.local_id,{})
	if player.is_empty():enabled=false;return
	var local: Dictionary=ctx.session.local_movement.sample_player(player) if ctx.session.mode=="client" else player
	observer=Vector3(local.pos.x,float(local.get("height",0)),local.pos.y)
	if ctx.actors.has(ctx.session.local_id):observer=ctx.actors[ctx.session.local_id].position
	var facing: Vector2=local.get("aim",Vector2.UP)
	if not facing.is_zero_approx():aim=facing.normalized()
	space=ctx.get_world_3d().direct_space_state
	_clock+=delta
	# Rays only shade the remembered environment; exact target tests run below.
	if _clock>=.05 or ray_texture==null:
		_clock=0
		_update_rays()
		roof_cutaway=ctx.world.has_method("has_overhead_cover") and ctx.world.has_overhead_cover(observer)
		if not roof_cutaway:
			var query:=PhysicsRayQueryParameters3D.create(observer+Vector3(0,1.4,0),observer+Vector3(0,12,0),OCCLUDER_MASK)
			var overhead:=space.intersect_ray(query)
			roof_cutaway=not overhead.is_empty() and absf(Vector3(overhead.normal).y)>.4
	var parameters: Dictionary={"vision_roof_cutaway":roof_cutaway,"vision_origin":observer,"vision_aim":aim,"vision_rays":ray_texture,"vision_range":Rules.VIEW_DISTANCE,"vision_sense":Rules.SENSE_RADIUS,"vision_cos_inner":cos(deg_to_rad(Rules.VIEW_ANGLE*.5)),"vision_cos_outer":cos(deg_to_rad(Rules.VIEW_ANGLE*.5+2))}
	if ctx.world.has_method("set_vision"):ctx.world.set_vision(true,parameters)
	if is_instance_valid(ctx.tracer_node):
		for key in parameters:ctx.tracer_node.material_override.set_shader_parameter(key,parameters[key])
	for id in ctx.actors:
		var actor: Node3D=ctx.actors[id]
		actor.visible=id==ctx.session.local_id or can_see(actor.position+Vector3(0,.45,0)) or can_see(actor.position+Vector3(0,1.3,0))
	for uid in ctx.drops:
		ctx.drops[uid].visible=can_see(ctx.drops[uid].position+Vector3(0,.2,0))
	if ctx.world.has_method("vision_targets"):
		for target in ctx.world.vision_targets():
			var visible:=false
			for point in target.points:
				if can_see(point,target.exclude):visible=true;break
			for node in target.nodes:node.visible=visible
	for i in ctx.target_labels.size():
		ctx.target_labels[i].visible=can_see(ctx.target_labels[i].position-Vector3(0,1.4,0))

func can_see(point: Vector3, exclude: Array[RID]=[]) -> bool:
	if not enabled:return true
	if not Rules.contains(observer,aim,point):return false
	if space==null:return false
	var eye:=observer+Vector3(0,Rules.EYE_HEIGHT,0)
	if eye.distance_squared_to(point)<.0001:return true
	var query:=PhysicsRayQueryParameters3D.create(eye,point,OCCLUDER_MASK,exclude)
	var hit:=space.intersect_ray(query)
	return hit.is_empty() or Vector3(hit.position).distance_to(point)<.08

func _update_rays() -> void:
	if _ray_image==null:_ray_image=Image.create(RAY_COUNT,1,false,Image.FORMAT_RF)
	var eye:=observer+Vector3(0,Rules.EYE_HEIGHT,0)
	for i in range(RAY_COUNT):
		var angle:=TAU*float(i)/RAY_COUNT
		var end:=eye+Vector3(cos(angle),0,sin(angle))*Rules.VIEW_DISTANCE
		var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(eye,end,OCCLUDER_MASK))
		var distance:=Rules.VIEW_DISTANCE if hit.is_empty() else eye.distance_to(hit.position)
		_ray_image.set_pixel(i,0,Color(distance/Rules.VIEW_DISTANCE,0,0,1))
	if ray_texture==null:ray_texture=ImageTexture.create_from_image(_ray_image)
	else:ray_texture.update(_ray_image)
