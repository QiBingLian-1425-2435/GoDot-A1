extends SceneTree
const Main=preload("res://app/main.gd")
const Highlight=preload("res://features/exploration/interaction_outline.gd")
var failures:=0
func check(ok:bool,message:String):
 print("PASS: " if ok else "FAIL: ",message)
 if not ok:failures+=1
func _initialize():call_deferred("run")
func run():
 var game=Main.new();game.smoke=true;game.elapsed=-10000;root.add_child(game);game.set_process(false);game.set_physics_process(false);game.session.set_physics_process(false);game.sound.muted=true
 game._start_solo()
 var p:Dictionary=game.session.model.state.players[1]
 p.pos=Vector2(0,-8.3);p.aim=Vector2.UP;game._update_actors(.016);game._update_camera(1);game.vision.update(game,.1);game._update_interaction();game.interaction_outline.update(game)
 check(game.nearest.get("kind","")=="travel" and not game.interaction_outline.shells.is_empty(),"local E exit prompt outlines actual hatch")
 check(not game.interaction_outline.shells.is_empty() and game.interaction_outline.shells[0].material_override is ShaderMaterial,"outline has a private material")
 var other=Highlight.new();root.add_child(other)
 var other_world=Node3D.new();root.add_child(other_world)
 var observer={"nearest":{},"in_game":true,"world_loading":false,"world":other_world}
 other.update(observer);check(other.shells.is_empty() and not game.interaction_outline.shells.is_empty(),"observer without prompt has no outline")
 if DisplayServer.get_name()!="headless":
  game._refresh_ui();game.ui._toast_label.visible=false
  for i in range(4):await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://artifacts/interaction_hatch.png")
 p.pos=Vector2(0,4);game._update_interaction();game.interaction_outline.update(game)
 check(game.interaction_outline.shells.is_empty(),"moving out of range removes highlight")
 game.world_loading=true;game.interaction_outline.update(game);check(game.interaction_outline.shells.is_empty(),"loading clears highlight");game.world_loading=false
 p.pos=Vector2(0,-8.3);game.session.model.command(1,"travel",{"route":"bunker_to_surface"});game._sync_world()
 while game.world_loading:await process_frame
 for i in range(3):await physics_frame
 var found:=false
 for station in game.session.model.stations:
  if station.get("kind","")!="loot" or station.get("loot_pool","")=="food":continue
  if game.world.has_overhead_cover(Vector3(station.pos.x,station.height,station.pos.y)):continue
  p.pos=station.pos+Vector2(0,1);p.height=station.height;p.aim=Vector2.UP
  game._update_actors(.016);game._update_camera(1);game.vision.update(game,.1);game._update_interaction();game.interaction_outline.update(game)
  if game.nearest.get("kind","") in ["loot","loot_view"] and not game.interaction_outline.shells.is_empty():found=true;break
 check(found,"actual visible Ground Zero box prompt selects box geometry")
 if found and DisplayServer.get_name()!="headless":
  game._refresh_ui();game.ui._toast_label.visible=false
  for i in range(4):await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://artifacts/interaction_box.png")
 if found:
  game.nearest.kind="loot_view";game.interaction_outline.update(game)
  check(not game.interaction_outline.shells.is_empty(),"search-to-view transition keeps outline")
 game.nearest={};game.interaction_outline.update(game);check(game.interaction_outline.shells.is_empty(),"no prompt clears box outline")
 other.free();other_world.free();game.queue_free();await process_frame
 print("INTERACTION_OUTLINE failures=",failures);quit(1 if failures else 0)
