extends SceneTree
const Main=preload("res://app/main.gd")
const Surface=preload("res://worlds/ground_zero/source_surface_double.gdshader")
var failures:=0
var checks:=0
var camera:Camera3D
var scene:Node3D
var materials:Array[ShaderMaterial]=[]
func _initialize():call_deferred("run")
func check(ok: bool, message: String):
	checks+=1;print("PASS: " if ok else "FAIL: ",message)
	if not ok:failures+=1
func material(color: Color, textured:=false) -> ShaderMaterial:
	var m:=ShaderMaterial.new();m.shader=Surface;m.set_shader_parameter("tint",color)
	m.set_shader_parameter("view_player",Vector3(0,.65,0));m.set_shader_parameter("view_camera",camera.position)
	m.set_shader_parameter("view_enabled",true);m.set_shader_parameter("vision_origin",Vector3.ZERO)
	m.set_shader_parameter("vision_aim",Vector2.UP)
	var rays:=Image.create(256,1,false,Image.FORMAT_RF);rays.fill(Color(1,0,0))
	m.set_shader_parameter("vision_rays",ImageTexture.create_from_image(rays))
	if textured:
		var texture:=Image.create(16,16,false,Image.FORMAT_RGB8)
		for y in range(16):
			for x in range(16):texture.set_pixel(x,y,Color(.9,.3,.12) if (x/4+y/4)%2==0 else Color(.18,.45,.14))
		m.set_shader_parameter("has_albedo",true);m.set_shader_parameter("albedo_map",ImageTexture.create_from_image(texture))
	materials.append(m);return m
func mesh(size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var node:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=size;node.mesh=box;node.position=at;node.material_override=mat;scene.add_child(node);return node
func render(name: String) -> Image:
	for i in range(4):await process_frame
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	var folder:=OS.get_environment("A1_TEST_ARTIFACTS")
	if folder.is_empty():folder=ProjectSettings.globalize_path("res://artifacts")
	DirAccess.make_dir_recursive_absolute(folder);check(image.save_png(folder+"/"+name+".png")==OK,"saved "+name)
	return image
func sample(image: Image, point: Vector3) -> Color:
	var xy:=camera.unproject_position(point)*Vector2(image.get_size())/root.get_visible_rect().size;var total:=Color(0,0,0,0)
	for y in range(int(xy.y)-2,int(xy.y)+3):
		for x in range(int(xy.x)-2,int(xy.x)+3):total+=image.get_pixel(x,y)
	return total/25.0
func run():
	if DisplayServer.get_name()!="headless":
		root.size=Vector2i(1200,800);scene=Node3D.new();root.add_child(scene)
		var environment:=WorldEnvironment.new();var env:=Environment.new()
		env.background_mode=Environment.BG_COLOR;env.background_color=Color(.015,.02,.03)
		env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color.WHITE;env.ambient_light_energy=1
		environment.environment=env;scene.add_child(environment)
		camera=Camera3D.new();scene.add_child(camera);camera.position=Vector3(10,16,14);camera.look_at(Vector3(0,0,-1));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=26
		var floor_mat:=material(Color.WHITE,true);mesh(Vector3(26,.2,26),Vector3(0,-.1,0),floor_mat)
		var roof_mat:=material(Color(.3,.4,.65));roof_mat.set_shader_parameter("roof_surface",true);var roof:=mesh(Vector3(20,.2,22),Vector3(0,4,0),roof_mat)
		var gable:=mesh(Vector3(20,3,.15),Vector3(0,3,-4),roof_mat)
		mesh(Vector3(2,.8,2),Vector3(0,.4,-7),material(Color(1,.65,.05)))
		# Offscreen colored wall outside the cone provides a stable material/color probe.
		var probe:=mesh(Vector3(2,.4,2),Vector3(-6,.2,4),material(Color(.9,.2,.08)))
		roof.visible=false;gable.visible=false
		for m in materials:m.set_shader_parameter("vision_enabled",false)
		var lit:=await render("vision_texture_lit")
		for m in materials:m.set_shader_parameter("vision_enabled",true)
		var dark:=await render("vision_texture_dark")
		var a:=sample(lit,probe.position+Vector3(0,.2,0));var b:=sample(dark,probe.position+Vector3(0,.2,0))
		print("FOG_PIXEL lit=",a," dark=",b)
		check(b.get_luminance()<a.get_luminance()*.5,"unseen textured material becomes dark")
		check(b.r>b.g*1.3 and b.r>b.b*1.3,"unseen material retains its original hue instead of gray/white")
		roof.visible=true;gable.visible=true
		var covered:=await render("vision_roof_covered")
		for m in materials:m.set_shader_parameter("vision_roof_cutaway",true)
		var revealed:=await render("vision_roof_revealed")
		a=sample(covered,Vector3(0,.8,-7));b=sample(revealed,Vector3(0,.8,-7))
		print("ROOF_PIXEL covered=",a," revealed=",b)
		check(b.r>a.r+.12 and b.r>b.b*1.5,"roof and attached vertical gable reveal furniture beyond the old small hole")
		var roof_shape:=StaticBody3D.new();var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(20,.2,22);shape.shape=box;roof_shape.add_child(shape);roof_shape.position=Vector3(0,4,0);roof_shape.collision_layer=16;scene.add_child(roof_shape)
		await physics_frame;await physics_frame
		var hit:=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,1.4,0),Vector3(0,12,0),16))
		check(not hit.is_empty(),"transparent roof retains physical occlusion/collision")
		scene.queue_free();await process_frame
	var game=Main.new();game.smoke=true;game.elapsed=-10000;root.add_child(game);game.sound.muted=true
	game.set_process(false);game.set_physics_process(false);game.session.set_physics_process(false);game._start_solo()
	var p:Dictionary=game.session.model.state.players[1];p.pos=Vector2(0,-8.2);game.session.send("travel",{"route":"bunker_to_surface"})
	while game.world_loading:await process_frame
	await physics_frame;await physics_frame
	check(game.world._roof_bounds.size()>=5,"original house roofs registered without new external assets")
	var normal_material:Material=game.world.library.material("sharedassets10_assets_381")
	var roof_material:Material=game.world.library.material("sharedassets10_assets_381",true)
	check(normal_material!=roof_material and not normal_material.get_shader_parameter("roof_surface") and roof_material.get_shader_parameter("roof_surface"),"roof material variant does not turn shared ordinary walls transparent")
	var bounds:AABB=game.world._roof_bounds[0]
	var best_score:float=-1
	var best_position:=Vector3(bounds.get_center().x,0,bounds.get_center().z)
	var best_aim:=Vector2.UP
	for x in range(-3,4,2):
		for z in range(-3,4,2):
			var candidate:=Vector3(bounds.get_center().x+x,0,bounds.get_center().z+z)
			candidate.y=game.world.terrain_height(Vector2(candidate.x,candidate.z))+.3
			var safe:Dictionary=game.player_physics.safe_standing_position(candidate)
			if safe.is_empty():continue
			candidate=safe.position
			for angle in range(16):
				var direction:=Vector2.from_angle(TAU*angle/16.0)
				var score:=0.0
				for offset in [-.6,0,.6]:
					var ray_dir:=direction.rotated(offset)
					var eye:=candidate+Vector3.UP
					var end:=eye+Vector3(ray_dir.x,0,ray_dir.y)*8
					var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye,end,16))
					score+=eye.distance_to(hit.position) if not hit.is_empty() else 8.0
				if score>best_score:best_score=score;best_position=candidate;best_aim=direction
	check(best_score>6,"real house test starts at a clear standing location with room to look")
	p.pos=Vector2(best_position.x,best_position.z);p.height=best_position.y;p.aim=best_aim
	print("REAL_HOUSE observer=",best_position," facing=",best_aim," sight=",best_score)
	game._update_actors(1);game._update_camera(1);game.vision.update(game,.06)
	check(game.vision.roof_cutaway,"entering the original house footprint activates local roof reveal")
	check(game.world.library._materials.values()[0].get_shader_parameter("vision_roof_cutaway"),"actual map material receives local roof state")
	var before:Dictionary=game.session.model.state.duplicate(true)
	p.pos=Vector2(-900,-900);game._update_actors(1);game.vision.update(game,.06)
	check(not game.vision.roof_cutaway,"leaving roof footprint restores solid roof")
	p.pos=before.players[1].pos
	game.vision.update(game,.06)
	check(game.session.model.state==before,"render evaluation preserves authoritative state")
	if DisplayServer.get_name()!="headless":
		game._update_actors(1);game._update_camera(1);game.vision.update(game,.06);game._refresh_ui()
		for i in range(4):await process_frame
		await RenderingServer.frame_post_draw
		var folder:=OS.get_environment("A1_TEST_ARTIFACTS")
		if folder.is_empty():folder=ProjectSettings.globalize_path("res://artifacts")
		root.get_texture().get_image().save_png(folder+"/vision_real_house.png")
	game.queue_free();await process_frame;await process_frame
	print("VISION_PRESENTATION checks=",checks," failures=",failures);quit(1 if failures else 0)
