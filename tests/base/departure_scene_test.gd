extends SceneTree
const Main=preload("res://app/main.gd")
const Texts=preload("res://features/localization/game_text.gd")
var failures:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 print("PASS: " if ok else "FAIL: ",label)
 if not ok:failures+=1
func run():
 var game=Main.new();game.smoke=true;game.elapsed=-10000;root.add_child(game);game._start_solo()
 game.set_process(false);game.set_physics_process(false);game.session.set_physics_process(false);game.sound.muted=true
 var m=game.session.model
 m.add_player(2,"Partner");game.session.mode="host"
 var p:Dictionary=m.state.players[1];p.pos=Vector2(0,-10.5);p.aim=Vector2.UP;game.camera_zoom=7
 game._update_actors(.1)
 for i in range(25):game._update_camera(.1)
 game.vision.update(game,.1);game._update_interaction();game.interaction_outline.update(game);game._refresh_ui()
 check(game.nearest.get("uid","")=="bunker_to_city" and game.nearest.get("destination","")=="city","main gate targets city")
 check(not game.interaction_outline.shells.is_empty(),"ready prompt highlights actual gate")
 game._interact();game._update_interaction();game._refresh_ui()
 check(m.state.departure_ready.get(1,false) and game.nearest.title=="⟦departure.cancel⟧","E readies local player and offers cancel")
 check(game.ui._world_note.text.contains("1 / 2"),"upper-left count shows one of two ready")
 var old_language=Texts.locale()
 for language in ["zh_CN","en"]:
  Texts.set_locale(language,false)
  game._refresh_ui();game._update_interaction();game.ui._toast_label.visible=false
  for i in range(5):await process_frame
  if DisplayServer.get_name()!="headless":
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png("res://artifacts/departure_"+language+".png")
 Texts.set_locale(old_language,false)
 game._interact();game._update_interaction()
 check(not m.state.departure_ready.get(1,false) and game.nearest.title=="⟦departure.confirm⟧","E cancels in real main interaction")
 game._interact();m.state.players[2].pos=Vector2(0,-10.5)
 check(m.command(2,"travel",{"route":"bunker_to_city"}),"last ready accepts departure")
 game._sync_world()
 while game.world_loading:await process_frame
 check(game.world_id=="city" and game.world.zone=="city","real city resource mounts after all ready")
 game.session.mode="offline";game.queue_free();await process_frame
 print("DEPARTURE_SCENE failures=",failures);quit(1 if failures else 0)
