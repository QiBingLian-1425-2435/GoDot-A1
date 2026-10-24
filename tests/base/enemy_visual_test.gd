extends SceneTree
const View=preload("res://features/enemies/enemy_view.gd")
const Rules=preload("res://features/enemies/enemy_rules.gd")
const G=preload("res://features/geometry/geometry.gd")
func _initialize():call_deferred("run")
func run():
	var stage:=Node3D.new();root.add_child(stage)
	G.box(stage,Vector3(0,-.15,0),Vector3(12,.2,7),Color("293b3c"))
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-30,0);light.light_energy=1.4;stage.add_child(light)
	var camera:=Camera3D.new();camera.position=Vector3(4,4,8);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=8;stage.add_child(camera);camera.look_at(Vector3(0,.8,0));camera.current=true
	var actors:Array=[];var states:Array=[]
	for i in range(3):
		var view=View.new();stage.add_child(view);actors.append(view)
		var data:=Rules.create(i,Vector3((i-1)*2.4,0,0),Vector2.DOWN)
		data.mode=["chase","windup","dead"][i];data.timer=.12
		data.velocity=Vector2.DOWN*4.6 if i==0 else Vector2.ZERO
		if i==2:data.hp=0
		states.append(data)
	for frame in range(45):
		for i in range(3):actors[i].update_enemy(states[i],1.0/60)
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var error:=root.get_texture().get_image().save_png("res://artifacts/enemy_visual_preview.png")
	print("ENEMY_VISUAL capture=",error);stage.queue_free();await process_frame;quit(0 if error==OK else 1)
