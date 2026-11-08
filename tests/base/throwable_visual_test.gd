extends SceneTree
const Main=preload("res://app/main.gd")
const Rules=preload("res://features/combat/throwable_system.gd")
const Appearance=preload("res://features/player/appearance_rules.gd")
var failures:=0
var game
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 if not ok:failures+=1;push_error("THROW_VISUAL FAIL: "+label)
func frame(dt:float):
 game.session.model.tick(dt);game._process(dt)
 await process_frame
func capture(label:String):
 if DisplayServer.get_name()=="headless":return
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://artifacts/throwable_"+label+".png")
func run():
 game=Main.new();game.smoke=true;game.elapsed=-10000;root.add_child(game);game._start_solo();game.sound.muted=true;game.camera_zoom=14
 game.set_process(false);game.set_physics_process(false);game.session.set_physics_process(false)
 var m=game.session.model;var p:Dictionary=m.state.players[1]
 var preview=preload("res://features/player/throwable_preview.gd").new();preview.name="ThrowPreview";game.add_child(preview)
 var origin:Vector2=p.pos
 var right:Vector2=Vector2(game.camera.global_basis.x.x,game.camera.global_basis.x.z).normalized()
 var target:=Vector3(origin.x,0,origin.y)+Vector3(right.x,0,right.y)*4.5
 for gender in ["male","female"]:
  p.appearance=Appearance.defaults(gender)
  for kind in Rules.KINDS:
   m.state.field_effects=[];p.fire_timer=0;p.bag[20]=m._item(kind,2)
   preload("res://features/player/quick_slots.gd").kinds=["rifle","pistol",kind,"medkit","water","","",""]
   preload("res://features/player/base_input.gd")._activate_quick(game,2)
   check(Rules.held(p).get("kind","")==kind,"quick slot selects tool without consuming")
   check(m.Trade.available(kind),"tool available from merchant")
   for i in 12:
    m.command(1,"move",{"aim":right,"ads":false});await frame(.05)
   check(game.actors[1].melee_pose.holder.visible,"handheld tool visible")
   check(not game.actors[1].rifle_mesh.visible and not game.actors[1].flash.visible,"gun hidden")
   await capture(kind+"_"+gender+"_idle")
   for i in 12:
    m.command(1,"move",{"aim":right,"ads":true});await frame(.05)
   preview.visible=true;preview.update_target(p,target,m.projectile_query)
   check(game.actors[1].melee_pose.holder.position.y>1.1,"raised tool above chest")
   check(preview.line.mesh.get_surface_count()==1,"trajectory and radius mesh exists")
   await capture(kind+"_"+gender+"_aim")
   var texts=preload("res://features/localization/game_text.gd")
   texts.set_locale("en",false);game._refresh_ui()
   check("throw" in game.ui._reload_label.text and Rules.held(p).get("kind","")==kind,"English hint preserves selected tool")
   await capture(kind+"_"+gender+"_aim_en")
   texts.set_locale("zh_CN",false);game._refresh_ui()
   for mode in ["forward","backward","side","crouch"]:
    var moving:Dictionary=p.duplicate(true)
    moving.velocity=right*(1.5 if mode!="backward" else -1.5)
    if mode=="side":moving.velocity=right.orthogonal()*1.5
    moving.crouch=mode=="crouch";moving.ads=true
    var actor=game.actors[1]
    for tick in 40:actor.update_actor(moving,.025,true)
    var motion=actor.human_visual.imported_motion
    var hand:Vector3=(motion.space*motion.skin.get_bone_global_pose(motion.skin.find_bone("R_Hand"))).origin
    check(hand.y>(.75 if moving.crouch else 1.15),kind+" "+gender+" "+mode+" moving aim keeps right hand raised")
    check(actor.melee_pose.holder.visible and actor.melee_pose.holder.position.distance_to(hand)<.1,"moving tool remains in right palm")
    await capture(kind+"_"+gender+"_aim_"+mode)
   for i in 12:
    m.command(1,"move",{"aim":right,"ads":true});await frame(.05)
   preload("res://features/player/base_input.gd")._fire_pressed(game,kind,false)
   check(m.state.field_effects.is_empty(),"input click without aim does not throw")
   preload("res://features/player/base_input.gd")._fire_pressed(game,kind,true)
   check(m.state.field_effects.size()==1 and not game.trigger_held,"input aimed click throws exactly once")
   for i in 10:await frame(.05)
   preview.visible=false
   await capture(kind+"_"+gender+"_flight")
   for i in 11:await frame(.05)
   check(not m.state.field_effects.is_empty() and m.state.field_effects[0].phase=="active","effect landed")
   if not m.state.field_effects.is_empty():
    var uid:String=m.state.field_effects[0].uid
    check(game.field_item_view.nodes.has(uid),"effect node rendered")
   await capture(kind+"_"+gender+"_effect")
   for i in 160:m.tick(.1)
   game._process(.1);await process_frame
   check(game.field_item_view.nodes.is_empty(),"expired visuals freed")
 game.queue_free();await process_frame
 print("THROWABLE_VISUAL failures=",failures);quit(1 if failures else 0)
