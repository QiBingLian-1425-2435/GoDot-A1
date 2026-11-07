extends SceneTree
func _initialize():call_deferred("run")
func run():
 DirAccess.make_dir_recursive_absolute("res://assets/worlds/survivor_base/source")
 var ignore:=FileAccess.open("res://assets/worlds/survivor_base/source/.gdignore",FileAccess.WRITE);ignore.close()
 var map=preload("res://worlds/survivor_base/survivor_base.gd").new();root.add_child(map)
 var doc:=GLTFDocument.new();var state:=GLTFState.new()
 var err:=doc.append_from_scene(map,state)
 if err==OK:
  var bytes:=doc.generate_buffer(state)
  var file:=FileAccess.open("res://assets/worlds/survivor_base/source/survivor_base_complete.glb",FileAccess.WRITE)
  if file!=null and not bytes.is_empty():file.store_buffer(bytes);file.close()
  else:err=ERR_CANT_CREATE
 print("SURVIVOR_EXPORT status=",err)
 map.queue_free();await process_frame;quit(0 if err==OK else 1)
