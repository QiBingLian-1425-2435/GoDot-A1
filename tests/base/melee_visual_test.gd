extends SceneTree
const Actor=preload("res://features/player/base_actor.gd")
const Model=preload("res://features/base/base_model.gd")
const Appearance=preload("res://features/player/appearance_rules.gd")
var failures:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
	print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
func run():
	var model=Model.new();model.add_player(1,"preview")
	var world:=Node3D.new();root.add_child(world)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("73675a");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.8;world.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-50,0);sun.light_energy=1.5;world.add_child(sun)
	var camera:=Camera3D.new();world.add_child(camera);camera.position=Vector3(3,2.3,-4);camera.look_at(Vector3(0,1,-.1));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3.4
	var actors:Array=[]
	for gender in ["male","female"]:
		var actor=Actor.new();actor.human_enabled=true;world.add_child(actor);actor.setup(Color.WHITE,"");actor.nameplate.visible=false;actors.append(actor)
	var sequence:=0
	for kind in ["fire_axe","crowbar","baseball_bat","baton","machete","katana"]:
		var p:Dictionary=model.state.players[1];p.equipment.weapon=model._item(kind,1);p.ammo=0
		var swing_positions:Array[Vector3]=[]
		for action in ["idle","aim","forward","back","run","crouch_aim"]:
			sequence+=1
			for i in 2:
				var data:Dictionary=p.duplicate(true);data.pos=Vector2(-.65 if i==0 else .65,0);data.aim=Vector2.UP;data.appearance=Appearance.defaults("male" if i==0 else "female");data.equipment.helmet={};data.equipment.armor={}
				data.velocity=Vector2(0,-6.1) if action=="run" else Vector2.ZERO
				data.sprint=action=="run";data.ads=action in ["aim","forward","back","crouch_aim"];data.crouch=action=="crouch_aim"
				data.anim_seq=sequence;data.anim_action="melee_"+action if action in ["forward","back"] else ("melee_forward" if action=="one_hand_forward" else "")
				data.anim_duration=float(model.Items.definition(kind).fire_interval) if action in ["forward","back","one_hand_forward"] else 0.0
				data.anim_time=data.anim_duration*.36
				for frame in 50:
					actors[i]._event_time=maxf(0,float(data.anim_time)-.016)
					actors[i].update_actor(data,.016,true)
				var actor=actors[i];var motion=actor.human_visual.imported_motion
				actor.local_ring.visible=false
				var right:Vector3=(motion.space*motion.skin.get_bone_global_pose(motion.skin.find_bone("R_Hand"))).origin
				var left:Vector3=(motion.space*motion.skin.get_bone_global_pose(motion.skin.find_bone("L_Hand"))).origin
				check(actor.melee_pose.holder.visible and actor.melee_pose.holder.position.distance_to(right)<.09,kind+" "+action+" "+str(i)+" carried at right palm")
				check(not actor.flash.visible and not actor.rifle_mesh.visible and not actor.pistol_mesh.visible and not actor.sniper_mesh.visible,"melee hides guns and muzzle flash")
				if data.ads:check(left.distance_to(actor.melee_pose.holder.transform*actor.melee_pose.LEFT_WRIST)<.14,kind+" "+action+" "+str(i)+" second hand grips handle")
				var finite:=true
				for mesh in actor.human_visual.meshes:finite=finite and mesh.global_transform.is_finite()
				check(finite,"skin transforms finite")
				if action=="idle":
					var tip:Vector3=actor.melee_pose.holder.basis*Vector3.UP
					check(tip.dot(Vector3.FORWARD)>.98 and absf(tip.y)<.06,kind+" idle holds working end level toward front")
					var rest_hand:Vector3=motion.rest[motion.skin.find_bone("R_Hand")].origin
					check(right.distance_to(rest_hand)<.035 and actor.melee_pose.right_weight<.01,kind+" idle keeps original hanging hand")
				if action in ["forward","back"] and i==0:swing_positions.append(actor.melee_pose.holder.position)
			await process_frame;await process_frame
			if DisplayServer.get_name()!="headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://artifacts/melee_%s_%s.png"%[kind,action])
		check(swing_positions[0].distance_to(swing_positions[1])>.08,kind+" repeated attacks alternate direction")
	world.queue_free();await process_frame
	print("MELEE_VISUAL failures=",failures);quit(0 if failures==0 else 1)
