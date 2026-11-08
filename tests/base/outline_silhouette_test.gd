extends SceneTree
func _initialize():call_deferred("run")
func run():
 var game=load("res://app/main.gd").new();game.smoke=true;game.elapsed=-10000;root.add_child(game);game._start_solo()
 game.set_process(false);game.set_physics_process(false);game.session.set_physics_process(false);game.sound.muted=true
 var p:Dictionary=game.session.model.state.players[1]
 for station in game.session.model.stations:
  if station.get("id","")=="medical":p.pos=station.pos+Vector2(0,1);p.height=station.get("height",0);break
 p.aim=Vector2.LEFT
 game.camera_zoom=8;game._update_actors(.1)
 for i in range(30):game._update_camera(.1)
 game.vision.update(game,.1);game._update_interaction();game.interaction_outline.update(game);game._refresh_ui()
 if game.interaction_outline.mask==null:
  push_error("Medical station did not create an interaction outline")
  game.queue_free();await process_frame;quit(1);return
 for i in range(10):await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://artifacts/outline_npc.png")
 var mask:Image=game.interaction_outline.mask.get_texture().get_image()
 await process_frame;await RenderingServer.frame_post_draw
 var shown:Image=root.get_texture().get_image()
 shown.resize(mask.get_width(),mask.get_height(),Image.INTERPOLATE_NEAREST)
 game.interaction_outline.overlay.hide();game.interaction_outline.set_process(false)
 await process_frame;await RenderingServer.frame_post_draw
 var hidden:Image=root.get_texture().get_image();var interiors:=0;var changed:=0
 hidden.resize(mask.get_width(),mask.get_height(),Image.INTERPOLATE_NEAREST)
 for y in range(3,mask.get_height()-3):
  for x in range(3,mask.get_width()-3):
   if mask.get_pixel(x,y).r>.99 and mask.get_pixel(x-3,y).r>.99 and mask.get_pixel(x+3,y).r>.99 and mask.get_pixel(x,y-3).r>.99 and mask.get_pixel(x,y+3).r>.99:
    interiors+=1
    var a:=shown.get_pixel(x,y);var b:=hidden.get_pixel(x,y)
    if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>.05:changed+=1
 print("OUTLINE_INTERIOR pixels=",interiors," changed=",changed)
 game.queue_free();await process_frame;quit(0 if interiors>100 and changed<interiors*.01 else 1)
