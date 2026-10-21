extends SceneTree
const Map=preload("res://worlds/ground_zero/ground_zero.gd")
const Body=preload("res://features/player/player.tscn")
func _initialize():call_deferred("run")
func run():
	var map=Map.new();map.zone="cave" if "--cave" in OS.get_cmdline_user_args() else "surface";root.add_child(map)
	while not map.loaded:await process_frame
	var body=Body.instantiate();map.add_child(body)
	await physics_frame;await physics_frame
	var space=map.get_world_3d().direct_space_state
	var query=PhysicsShapeQueryParameters3D.new();query.shape=body.get_child(0).shape;query.collision_mask=1;query.margin=.005
	var cases=0;var failures=[];var trees=0;var tested={}
	for node in map.get_children():
		if not node is StaticBody3D or not node.has_meta("source_name") or not (node.collision_layer&1):continue
		var label=str(node.get_meta("source_name"))
		if label.contains("Tree"):
			trees+=1
			if not "--full" in OS.get_cmdline_user_args() and trees%40!=0:continue
		elif not "--full" in OS.get_cmdline_user_args() and not (label.to_lower().contains("box") or label.contains("Container")):continue
		var col=node.get_child(0)
		var bounds=col.global_transform*col.shape.get_debug_mesh().get_aabb()
		var center=bounds.get_center()
		var radius=minf(4,maxf(bounds.size.x,bounds.size.z)*.5)+.7
		for direction in [Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT]:
			var point=Vector2(center.x,center.z)+direction*radius
			var hit=body._support(point,map.terrain_height(point)+.1)
			if hit.is_empty() or hit.normal.y<.65:continue
			var start=Vector3(point.x,body._feet_height(hit),point.y)
			query.transform=Transform3D(Basis.IDENTITY,start+Vector3(0,.75,0))
			if not space.intersect_shape(query,1).is_empty():continue
			var at=start
			for i in range(35):at=body.move_spatial(at,-direction*.06)
			var contact=at
			for i in range(60):
				var back=Vector2(start.x-at.x,start.z-at.z).limit_length(.06)
				at=body.move_spatial(at,back)
			cases+=1;tested[label]=int(tested.get(label,0))+1
			if Vector2(at.x-start.x,at.z-start.z).length()>.3:
				var escaped=false
				for j in range(8):
					var escape_at=at
					var escape_dir=Vector2(cos(TAU*j/8),sin(TAU*j/8))
					for k in range(30):escape_at=body.move_spatial(escape_at,escape_dir*.06)
					if Vector2(escape_at.x-at.x,escape_at.z-at.z).length()>.75:escaped=true;break
				if escaped or can_navigate_out(body,at):continue
				var entry={"name":label,"id":node.get_meta("source_id"),"start":str(start),"contact":str(contact),"end":str(at)}
				query.transform=Transform3D(Basis.IDENTITY,at+Vector3(0,.75,0))
				entry["overlap"] = []
				for h in space.intersect_shape(query,8):entry.overlap.append(str(h.collider.get_meta("source_name",h.collider.name)))
				entry["support"]=str(body._support(Vector2(at.x,at.z),at.y))
				failures.append(entry)
				if failures.size()<=12:print("STUCK ",entry)
		if cases%200==0:
			print("COLLISION_AUDIT_PROGRESS ",cases)
			await process_frame
	print("STUCK_SCAN cases=",cases," failed=",failures.size()," collider_types=",tested.size())
	var f=FileAccess.open("res://artifacts/collision_audit_"+map.zone+".json",FileAccess.WRITE);f.store_string(JSON.stringify({"cases":cases,"failures":failures,"types":tested},"  "));f.close()
	map.queue_free();await process_frame
	quit(1 if failures.size()>0 or cases==0 else 0)

# A narrow doorway can require a turn. Straight probes alone are not proof of a trap.
func can_navigate_out(body, origin: Vector3) -> bool:
	var queue: Array[Vector3]=[origin]
	var seen: Dictionary={}
	var index:=0
	while index<queue.size() and index<600:
		var point:=queue[index];index+=1
		for i in range(8):
			var at: Vector3=body.move_spatial(point,Vector2(cos(TAU*i/8),sin(TAU*i/8))*.12)
			if Vector2(at.x-origin.x,at.z-origin.z).length()>.75:return true
			var key:=Vector3i(roundi(at.x/.04),roundi(at.y/.06),roundi(at.z/.04))
			if seen.has(key) or at.distance_to(point)<.01:continue
			seen[key]=true;queue.append(at)
	return false
