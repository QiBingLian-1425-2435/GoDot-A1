extends RefCounted
## Migrated reference behavior; called only through the owning composition/model.

static func _setup_environment(ctx)->void:
	var node =WorldEnvironment.new()
	var env =Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color("07182a")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("91afc7")
	env.ambient_light_energy=0.34
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	node.environment=env
	ctx.add_child(node)
	var sun =DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-58,-25,0)
	sun.light_color=Color("c3d9e8")
	sun.light_energy=0.42
	sun.shadow_enabled=true
	sun.directional_shadow_max_distance=70
	ctx.add_child(sun)
	ctx.camera=Camera3D.new()
	ctx.camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	ctx.camera.size=ctx.camera_zoom
	ctx.camera.near=0.1
	ctx.camera.far=120
	ctx.add_child(ctx.camera)
	ctx._update_camera(1.0)

static func _update_camera(ctx, delta:float)->void:
	var target =Vector3(0,0,3)
	if ctx.session!=null:
		var p:Dictionary=ctx.session.model.state.players.get(ctx.session.local_id,{})
		var pos:Vector2=p.get("pos",Vector2(0,3))
		if ctx.actors.has(ctx.session.local_id):
			var visible_pos:Vector3=ctx.actors[ctx.session.local_id].position
			pos=Vector2(visible_pos.x,visible_pos.z)
		target=Vector3(pos.x*0.76,0,pos.y*0.76)
	ctx.camera_focus=ctx.camera_focus.lerp(target,minf(1,delta*6))
	ctx.camera.position=ctx.camera_focus+Vector3(15,23,21)
	ctx.camera.look_at(ctx.camera_focus)
	ctx.camera.size=lerpf(ctx.camera.size,ctx.camera_zoom,minf(1,delta*8))

static func _update_actors(ctx, delta:float)->void:
	var players:Dictionary=ctx.session.model.state.players
	if ctx.session.mode=="client":ctx.session.motion_buffer.advance(delta)
	for id in ctx.actors.keys():
		if not players.has(id):
			ctx.actors[id].queue_free()
			ctx.actors.erase(id)
	for id in players:
		if not ctx.actors.has(id):
			var actor =ctx.Actor.new()
			ctx.add_child(actor)
			actor.setup(Color("87c9db") if id!=ctx.session.local_id else Color("d7c583"),str(players[id].name))
			ctx.actors[id]=actor
		ctx.actors[id].visible=true
		var display:Dictionary=players[id]
		if ctx.session.mode=="client":display=ctx.session.motion_buffer.sample_player(id,players[id])
		ctx.actors[id].update_actor(display,delta,id==ctx.session.local_id)
		var shots:int=players[id].get("shots",0)
		if shots>int(ctx.last_shots.get(id,shots)):ctx.sound.play("fire")
		ctx.last_shots[id]=shots
	var targets:Array=ctx.session.model.state.get("targets",[])
	if ctx.world.has_method("update_targets"):ctx.world.update_targets(targets)
	while ctx.target_labels.size()<targets.size():
		var label =Label3D.new()
		label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size=21
		label.pixel_size=0.011
		label.outline_size=5
		ctx.add_child(label)
		ctx.target_labels.append(label)
	for i in targets.size():
		var t:Dictionary=targets[i]
		var pos:Vector2=t.pos
		ctx.target_labels[i].position=Vector3(pos.x,2.6,pos.y)
		ctx.target_labels[i].text="%d / %d · 命中 %d"%[int(t.hp),int(t.get("max_hp",100)),int(t.get("hits",0))]
		ctx.target_labels[i].modulate=Color("aee4c8") if t.hp>0 else Color("edb075")
		ctx.target_labels[i].visible=true

static func _update_drops(ctx)->void:
	var data:Dictionary=ctx.session.model.state.drops
	for uid in ctx.drops.keys():
		if not data.has(uid):
			ctx.drops[uid].queue_free()
			ctx.drops.erase(uid)
	for uid in data:
		if not ctx.drops.has(uid):
			var node =Node3D.new()
			var mesh =MeshInstance3D.new()
			var box =BoxMesh.new()
			box.size=Vector3(0.48,0.3,0.38)
			mesh.mesh=box
			var mat =StandardMaterial3D.new()
			mat.albedo_color=Color("b5ac78")
			mesh.material_override=mat
			mesh.position.y=0.2
			node.add_child(mesh)
			var label =Label3D.new()
			label.text="E  拾取"
			label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
			label.position.y=0.8
			label.font_size=20
			label.pixel_size=0.012
			node.add_child(label)
			ctx.add_child(node)
			ctx.drops[uid]=node
		var pos:Vector2=data[uid].pos
		ctx.drops[uid].position=Vector3(pos.x,0,pos.y)
		ctx.drops[uid].visible=true

static func _update_tracers(ctx)->void:
	ctx.tracer_mesh.clear_surfaces()
	var shots:Array=ctx.session.model.state.get("shots",[])
	if shots.is_empty():return
	var started:=false
	for shot in shots:
		# Draw a moving streak, never a full ray frozen at the old firing position.
		# The hit point stays authoritative; actor motion cannot drag it through walls.
		var age:float=maxf(0.0,0.16-float(shot.ttl)+ctx.session.snapshot_age())
		var origin:Vector2=shot.from
		var end:Vector2=shot.to
		var distance:float=origin.distance_to(end)
		if distance<=0.01:continue
		var direction:Vector2=(end-origin)/distance
		var muzzle:float=minf(0.7,distance)
		var travel:float=(distance-muzzle)/220.0
		var lifetime:float=minf(0.16,travel+0.025)
		if age>=lifetime:continue
		var head:float=minf(distance,muzzle+age*220.0+1.8)
		var tail:float=maxf(muzzle,head-1.8)
		if head-tail<=0.01:continue
		if not started:
			ctx.tracer_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
			started=true
		var alpha:float=clampf((lifetime-age)/0.025,0.0,1.0)
		var start:Vector2=origin+direction*tail
		var finish:Vector2=origin+direction*head
		ctx.tracer_mesh.surface_set_color(Color(1,1,1,alpha*0.3))
		ctx.tracer_mesh.surface_add_vertex(Vector3(start.x,0.9,start.y))
		ctx.tracer_mesh.surface_set_color(Color(1,1,1,alpha))
		ctx.tracer_mesh.surface_add_vertex(Vector3(finish.x,0.9,finish.y))
	if started:ctx.tracer_mesh.surface_end()

static func _capture(ctx)->void:
	await RenderingServer.frame_post_draw
	ctx.get_viewport().get_texture().get_image().save_png(ctx.capture_path)
	print("CAPTURE ",ctx.capture_path)
	ctx.get_tree().quit()
