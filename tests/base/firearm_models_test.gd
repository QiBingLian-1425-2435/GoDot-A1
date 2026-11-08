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
 var camera:=Camera3D.new();world.add_child(camera);camera.position=Vector3(3,2.3,-4);camera.look_at(Vector3(0,.85,-.1));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3.4
 var actors:Array=[]
 for gender in ["male","female"]:
  var actor=Actor.new();actor.human_enabled=true;world.add_child(actor);actor.setup(Color.WHITE,"");actor.nameplate.visible=false;actors.append(actor)
 for kind in ["rifle","pistol","sniper"]:
  var p:Dictionary=model.state.players[1];p.equipment.weapon=model._item(kind,1);p.magazines[p.equipment.weapon.uid]=0;p.ammo=0
  check(model.command(1,"reload"),kind+" reload starts")
  for tick in 30:model.tick(.1)
  check(p.ammo==int(model.Items.definition(kind).magazine),kind+" magazine loads")
  p.fire_timer=0
  check(model.command(1,"fire"),kind+" fires through existing combat")
  for action in ["idle","aim","walk","run","crouch","crouch_aim","reload"]:
   for i in 2:
    var data:Dictionary=p.duplicate(true);data.pos=Vector2(-.65 if i==0 else .65,0);data.aim=Vector2.UP;data.appearance=Appearance.defaults("male" if i==0 else "female");data.equipment.helmet={};data.equipment.armor={}
    data.velocity=Vector2(0,-6.1 if action=="run" else -1.85) if action in ["walk","run"] else Vector2.ZERO
    data.sprint=action=="run";data.ads=action in ["aim","crouch_aim"];data.crouch=action in ["crouch","crouch_aim"];data.reloading=action=="reload";data.reload_progress=.5
    for frame in 45:
     if action=="reload":actors[i]._reload_time=float(model.Items.definition(kind).reload_time)*.5-.016;actors[i]._was_reloading=true
     actors[i].update_actor(data,.016,true)
    var actor=actors[i];var finite:=true
    for mesh in actor.human_visual.meshes:finite=finite and mesh.global_transform.is_finite()
    check(finite,kind+" "+action+" "+str(i)+" skin transforms finite")
    check(actor.magazine!=null and actor.magazine.mesh!=null,"real detachable rifle magazine")
    var bounds:AABB=actor.magazine.get_aabb()
    check(bounds.size.z<.30 and bounds.size.y<.20,"detachable mesh contains only magazine")
    var gun:Node3D={"rifle":actor.rifle_mesh,"pistol":actor.pistol_mesh,"sniper":actor.sniper_mesh}[kind]
    check(gun.visible and gun.get_node("Muzzle").position.z<-.25,"correct active weapon and forward muzzle")
    check(absf(gun.get_node("Muzzle").position.x)<.03,"muzzle aligns with character facing")
    if action in ["idle","aim","walk","run","crouch","crouch_aim"]:
     var imported=actor.human_visual.imported_motion
     for side in ["L","R"]:
      var actual:Vector3=(imported.space*imported.skin.get_bone_global_pose(imported.skin.find_bone(side+"_Hand"))).origin
      check(actual.distance_to(actor.weapon_grip(side))<.13,kind+" "+action+" "+str(i)+" "+side+" hand reaches grip")
    if action=="crouch_aim":
     var gun_pose:Transform3D=actor.skeleton.get_bone_global_pose(actor.skeleton.find_bone("Gun"))
     var forward:Vector3=gun_pose.basis*Vector3.FORWARD
     print("CROUCH_AIM_PITCH ",kind," ",i," ",rad_to_deg(asin(forward.normalized().y)))
     check(forward.normalized().y>-.08,"crouch aim points forward instead of toward floor")
    if action=="reload" and kind=="rifle":check(not actor.magazine.visible and actor.held_props.reload.is_visible_in_tree(),"rifle magazine transfers to left hand")
   await process_frame;await process_frame
   if DisplayServer.get_name()!="headless":
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("res://artifacts/firearm_%s_%s.png"%[kind,action])
 world.queue_free();await process_frame
 print("FIREARM_MODELS failures=",failures);quit(0 if failures==0 else 1)
