extends SceneTree
func _initialize():call_deferred("run")
func run():
 var map=preload("res://worlds/survivor_base/survivor_base.gd").new();root.add_child(map)
 assert(map.cache.size()==33)
 for key in map.cache:assert(map.cache[key]!=null)
 for node in map.get_children():
  if node is Node3D:assert(node.transform.origin.is_finite())
 print("SURVIVOR_BASE_TEST: all 33 user assets loaded; ",map.count," placements; finite transforms")
 map.queue_free();await process_frame;quit()
