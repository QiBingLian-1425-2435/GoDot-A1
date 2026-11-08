extends SceneTree
const Main=preload("res://app/main.gd")
const Appearance=preload("res://features/player/appearance_rules.gd")
var failures:=0
var checks:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 checks+=1;print("PASS: " if ok else "FAIL: ",label)
 if not ok:failures+=1
func frames()->void:
 for i in 4:await process_frame
 await RenderingServer.frame_post_draw
func run()->void:
 var game=Main.new();game.smoke=true;game.elapsed=-10000;root.add_child(game);game._start_solo()
 game.set_process(false);game.set_physics_process(false);game.session.set_physics_process(false);game.sound.muted=true
 var p:Dictionary=game.session.model.state.players[1]
 var gate:Dictionary={}
 for station in game.session.model.stations:
  if station.get("id","")=="exit":gate=station;break
 check(not gate.is_empty(),"actual base has city gate interaction")
 if gate.is_empty():game.queue_free();await process_frame;quit(1);return
 p.pos=gate.pos+Vector2(0,-.25);p.height=gate.get("height",0);p.aim=Vector2.UP
 game.camera_zoom=7
 var outline=game.interaction_outline
 for gender in ["male","female"]:
  p.appearance=Appearance.defaults(gender)
  for pose in ["idle","walk","run","crouch"]:
   p.crouch=pose=="crouch";p.sprint=pose=="run";p.velocity=Vector2.RIGHT*(5.0 if p.sprint else 2.5) if pose in ["walk","run"] else Vector2.ZERO
   for i in 8:game._update_actors(.08);game._update_camera(.1)
   game.vision.update(game,.1);game._update_interaction();outline.clear();outline.update(game);game._refresh_ui();game.ui._toast_timer=0;game.ui._toast_label.hide()
   check(game.nearest.get("kind","")=="travel" and not outline.shells.is_empty(),gender+" "+pose+" outlines the gate")
   if outline.shells.is_empty():continue
   if DisplayServer.get_name()!="headless":await frames()
   var skins:=0;var blockers:=0;var valid_blockers:=true;var valid_skins:=true;var valid_renderer:=true
   var actor:Node3D=game.actors[1]
   for copy in outline.shells:
    var source=copy.get_meta("original")
    if actor.is_ancestor_of(source):
     blockers+=1
     valid_blockers=valid_blockers and copy.material_override.get_shader_parameter("mask_value")==0.0
    if source is MeshInstance3D and source.get_node_or_null(source.skeleton) is Skeleton3D:
     skins+=1
     valid_skins=valid_skins and copy.get_node_or_null(copy.skeleton)==source.get_node(source.skeleton) and copy.skin==source.skin
     if DisplayServer.get_name()!="headless":valid_renderer=valid_renderer and copy.get_skin_reference()!=null and copy.get_skin_reference().get_skeleton()==source.get_skin_reference().get_skeleton()
   check(valid_blockers,"player is only a blocker")
   check(valid_skins,"mask follows original live skeleton and skin")
   if DisplayServer.get_name()!="headless":check(valid_renderer,"renderer shares the live skeleton binding")
   check(skins>0 and blockers>0,"animated player is present in occlusion mask")
   if DisplayServer.get_name()=="headless":continue
   var mask:Image=outline.mask.get_texture().get_image()
   var shown:Image=root.get_texture().get_image()
   shown.resize(mask.get_width(),mask.get_height(),Image.INTERPOLATE_NEAREST)
   if gender=="male" and pose=="idle":shown.save_png("res://artifacts/gate_outline_fixed.png");mask.save_png("res://artifacts/gate_outline_mask.png")
   # Render the real compositing shader at mask resolution, so window content
   # scaling and moving fire/scene pixels cannot skew the alpha comparison.
   var output:=SubViewport.new();output.size=mask.get_size();output.transparent_bg=true;output.disable_3d=true;output.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(output)
   var rect:=TextureRect.new();rect.size=Vector2(output.size);rect.texture=outline.mask.get_texture();rect.material=outline.overlay.material;output.add_child(rect)
   await frames()
   var rendered:Image=output.get_texture().get_image()
   mask=outline.mask.get_texture().get_image()
   var center:Vector2=outline.mask_camera.unproject_position(actor.global_position+Vector3.UP*.9)
   var area:=Rect2i(Vector2i(center)-Vector2i(75,95),Vector2i(150,190)).intersection(Rect2i(Vector2i(3,3),mask.get_size()-Vector2i(6,6)))
   var green:=0;var edges:=0;var changed:=0;var white:=0
   for y in range(area.position.y,area.end.y):
    for x in range(area.position.x,area.end.x):
     var color:=mask.get_pixel(x,y)
     if color.r>.9:white+=1
     if color.g<.99 or color.r>.01:continue
     green+=1
     var near_target:=false
     for offset in [Vector2i(-2,0),Vector2i(2,0),Vector2i(0,-2),Vector2i(0,2)]:
      if mask.get_pixel(x+offset.x,y+offset.y).r>.9:near_target=true;break
     if not near_target:continue
     edges+=1
     if rendered.get_pixel(x,y).a>.05:changed+=1
   print("OCCLUSION pixels=",green," target=",white," boundary=",edges," painted=",changed)
   check(green>20 and white>20,"GPU distinguishes occluder from gate and background")
   check(edges>0 and changed<=maxi(1,edges/100),"no white contour painted onto player's occlusion boundary")
   output.queue_free();await process_frame
 game.nearest={};outline.update(game);check(outline.shells.is_empty(),"leaving prompt clears target and all blockers")
 game.queue_free();await process_frame
 print("OUTLINE_OCCLUSION checks=%d failures=%d"%[checks,failures]);quit(1 if failures else 0)
