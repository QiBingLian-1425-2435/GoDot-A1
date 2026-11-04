extends SceneTree
const Quick=preload("res://features/player/quick_slots.gd")
const Main=preload("res://app/main.gd")
var failures:=0
func check(ok:bool,label:String):
 print("PASS: " if ok else "FAIL: ",label)
 if not ok:failures+=1
func _initialize():call_deferred("run")
func run():
 var existed:=FileAccess.file_exists(Quick.PATH)
 var backup:=FileAccess.get_file_as_string(Quick.PATH) if existed else ""
 Quick.kinds=Quick.DEFAULTS.duplicate()
 var game=Main.new();game.smoke=true;game.elapsed=-10000;root.add_child(game);game._start_solo();game.set_process(false);game.set_physics_process(false);game.session.set_physics_process(false);game.sound.muted=true
 var m=game.session.model;var p:Dictionary=m.state.players[1]
 game._refresh_ui();game.ui.toggle_inventory(true)
 check(game.ui._quick_slots.size()==16,"HUD and inventory each have eight slots")
 var water_index:=-1
 for i in p.bag.size():
  if p.bag[i].get("kind","")=="water":water_index=i
 var item:Dictionary=p.bag[water_index]
 var payload={"duckov_item":true,"from":"bag","index":water_index,"uid":item.uid,"kind":item.kind}
 var slot=game.ui._quick_slots[15]
 check(slot._can_drop_data(Vector2.ZERO,payload),"inventory hotbar accepts a carried usable item")
 var count:int=item.count
 slot._drop_data(Vector2.ZERO,payload)
 check(Quick.kinds[7]=="water" and p.bag[water_index].count==count,"drag assigns slot eight without moving or consuming water")
 Quick.kinds=[];Quick.ensure_loaded();check(Quick.kinds[7]=="water","binding survives preference reload")
 var temp:Dictionary=p.bag[20];p.bag[20]=p.bag[water_index];p.bag[water_index]=temp
 check(Quick.resolve(p,7).index==20,"binding follows item kind after bag reordering")
 var stale:=payload.duplicate();stale.uid="wrong";game.ui._bind_quick(6,stale)
 check(Quick.kinds[6]=="","stale drag is rejected")
 check(not slot._can_drop_data(Vector2.ZERO,{"duckov_item":true,"from":"stash","kind":"water"}),"warehouse drag cannot bind inaccessible items")
 if DisplayServer.get_name()!="headless":
  game._refresh_ui();game.ui._toast_label.visible=false
  for i in range(4):await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://artifacts/quick_inventory.png")
 game.ui.close_inventory();m.state.world="surface";p.thirst=0
 var event:=InputEventKey.new();event.physical_keycode=KEY_8;event.pressed=true
 game._unhandled_input(event);m.tick(3)
 check(m._count(p.bag,"water")==count-1 and p.thirst>0,"key eight uses assigned water through authority")
 game.ui._bind_quick(7,{})
 check(Quick.kinds[7]=="","right-click clear path removes binding")
 if existed:
  var file=FileAccess.open(Quick.PATH,FileAccess.WRITE);file.store_string(backup);file.close()
 else:DirAccess.remove_absolute(Quick.PATH)
 Quick.kinds=[]
 game.queue_free();await process_frame
 print("QUICK_SLOTS failures=",failures);quit(1 if failures else 0)
