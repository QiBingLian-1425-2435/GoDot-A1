extends Node3D
signal map_loaded()
## Original scene layout, static world physics, and source landmarks.
const WalkabilityRepairs = preload("res://worlds/ground_zero/walkability_repairs.gd")
const Library = preload("res://worlds/ground_zero/map_library.gd")
const TERRAIN_SHADER = preload("res://worlds/ground_zero/terrain.gdshader")
const WATER_DECAL_SHADER = preload("res://worlds/ground_zero/water_decal.gdshader")
@export_enum("surface","cave") var zone := "surface"
@export var build_collisions := true
@export var overview_mode := false
var library
var data: Dictionary = {}
var landmarks: Array = []
var _heights := PackedFloat32Array()
var _terrain_origin := Vector3.ZERO
var _terrain_scale := Vector3.ONE
var _resolution := 0
var _shapes: Dictionary = {}
var _render_groups := 0
var _collider_count := 0
var target_nodes: Dictionary = {}
var _interactions: Array = []
var loaded := false
var _cancelled := false
var _door_nodes: Dictionary = {}
var _door_open: Dictionary = {}
var _vision_groups: Dictionary = {}
var _terrain_material: ShaderMaterial
var _vision_materials: Array[ShaderMaterial]=[]

func _ready() -> void:
	if library == null: library = Library.new()
	data = library.read_json(zone+".json")
	if data.is_empty(): return
	await _build_terrain()
	if _cancelled: queue_free();return
	await _build_geometry()
	if _cancelled: queue_free();return
	_build_lights()
	if build_collisions:
		await _build_collisions()
		WalkabilityRepairs.build(self,zone)
	if _cancelled: queue_free();return
	_build_landmarks()
	_project_decals.call_deferred()
	loaded = true
	map_loaded.emit()
	print("GROUND_ZERO_MAP zone=",zone," render_groups=",_render_groups," colliders=",_collider_count," source_renderers=",data.renderers.size()," terrain_resolution=",_resolution)

func cancel_load() -> void:
	_cancelled = true

func _build_geometry() -> void:
	var groups: Dictionary = {}
	for item in data.renderers:
		# Custom deferred-light hulls are represented by real lights below.
		if item.get("role", "surface") in ["light_volume", "soft_volume"]: continue
		if str(item.get("mesh","")).is_empty(): continue
		if overview_mode and item.has("lod") and int(item.lod)!=2: continue
		if item.has("door_id"):
			var leaf := MeshInstance3D.new()
			leaf.mesh=library.render_mesh(str(item.mesh),item.materials)
			leaf.transform=Library.transform(item.transform)
			add_child(leaf)
			_track_door(item,leaf)
			continue
		var values: Array = item.transform
		var x := int(floor(float(values[9])/64.0))
		var z := int(floor(float(values[11])/64.0))
		var key := str(item.mesh)+"/"+str(item.materials)+"/"+str(x)+"/"+str(z)+"/"+str(item.get("lod",-1))+"/"+str(item.get("source","scene"))+"/"+str(item.get("shadow_mode",1))+"/"+str(item.get("visibility_id",""))
		if not groups.has(key): groups[key] = []
		groups[key].append(item)
	for items in groups.values():
		var first: Dictionary = items[0]
		var first_transform := Library.transform(first.transform)
		var center := Vector3(floorf(first_transform.origin.x/64.0)*64+32,0,floorf(first_transform.origin.z/64.0)*64+32)
		var mesh: ArrayMesh = library.render_mesh(str(first.mesh),first.materials)
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.use_colors = first.has("color")
		batch.use_custom_data = first.has("color")
		batch.mesh = mesh
		batch.instance_count = items.size()
		for i in range(items.size()):
			var placement := Library.transform(items[i].transform)
			placement.origin -= center
			batch.set_instance_transform(i,placement)
			if batch.use_colors:
				var color: Array = items[i].get("color",[1,1,1,1])
				batch.set_instance_color(i,Color(color[0],color[1],color[2],color[3]))
				batch.set_instance_custom_data(i,Color(color[0],color[1],color[2],color[3]))
		var node := MultiMeshInstance3D.new()
		node.name = "Source_"+str(first.mesh)+"_"+str(_render_groups)
		node.multimesh = batch
		node.position = center
		var lod := int(first.get("lod",-1))
		if lod>=0 and not overview_mode:
			node.visibility_range_begin = [0.,48.,120.][mini(lod,2)]
			node.visibility_range_end = [48.,120.,340.][mini(lod,2)]
			node.visibility_range_begin_margin = 4
			node.visibility_range_end_margin = 4
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if lod>0 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		else: node.visibility_range_end = 0 if overview_mode else (70 if first.get("source","")=="terrain_detail" else 380)
		var source_shadow := int(first.get("shadow_mode",1))
		if source_shadow==3: node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		elif source_shadow==0: node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		if first.has("visibility_id"):_track_vision(first,node)
		_render_groups += 1
		if _render_groups%24==0:
			await get_tree().process_frame
			if _cancelled:return

func _build_lights() -> void:
	for spec in data.get("lights",[]):
		if str(spec.type) != "point": continue
		var light := OmniLight3D.new()
		light.position = Library.transform(spec.transform).origin
		var rgb: Array = spec.color
		var energy := maxf(float(rgb[0]),maxf(float(rgb[1]),float(rgb[2])))
		if energy<.001: continue
		light.light_color = Color(float(rgb[0]),float(rgb[1]),float(rgb[2]))/maxf(1,energy)
		light.light_energy = minf(energy,4)
		light.omni_range = maxf(.1,float(spec.get("range",4)))
		light.omni_attenuation = maxf(.1,float(spec.get("attenuation",2)))
		light.distance_fade_enabled = true
		light.distance_fade_begin = 45
		light.distance_fade_length = 15
		add_child(light)

func _project_decals() -> void:
	# Compatibility has no Decal renderer; project the source box onto actual
	# collision surfaces and retain its atlas scale/bias in a small static mesh.
	if build_collisions: await get_tree().physics_frame
	var count := 0
	for entity in data.get("entities",[]):
		if entity.type!="DecalProjector" or not entity.has("material"): continue
		var spec: Dictionary = entity.data
		var placement := Library.transform(entity.transform)
		var size := Vector3(spec.m_Size.x,spec.m_Size.y,spec.m_Size.z)
		var offset := Vector3(spec.m_Offset.x,spec.m_Offset.y,-float(spec.m_Offset.z))
		var direction := -placement.basis.z.normalized()
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var uv := PackedVector2Array()
		var uv2 := PackedVector2Array()
		var valid: Array[bool] = []
		var indices := PackedInt32Array()
		var steps := 12
		for y in range(steps+1):
			for x in range(steps+1):
				var local := offset+Vector3((float(x)/steps-.5)*size.x,(float(y)/steps-.5)*size.y,size.z*.5)
				var start := placement*local
				var end := placement*(local-Vector3(0,0,size.z))
				var hit: Dictionary = {}
				if build_collisions:
					hit=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start,end,1|8))
				elif absf(direction.y)>.5:
					var center := (start+end)*.5
					hit={"position":Vector3(center.x,terrain_height(Vector2(center.x,center.z)),center.z),"normal":Vector3.UP}
				var accepted := not hit.is_empty() and Vector3(hit.get("normal",Vector3.ZERO)).dot(-direction)>.1
				valid.append(accepted)
				vertices.append(Vector3(hit.position)+Vector3(hit.normal)*.025 if accepted else Vector3.ZERO)
				normals.append(hit.normal if accepted else Vector3.UP)
				var atlas := Vector2(float(x)/steps,float(y)/steps)*Vector2(spec.m_UVScale.x,spec.m_UVScale.y)+Vector2(spec.m_UVBias.x,spec.m_UVBias.y)
				uv.append(Vector2(atlas.x,1-atlas.y))
				uv2.append(Vector2(float(x)/steps,float(y)/steps))
		for y in range(steps):
			for x in range(steps):
				var a := y*(steps+1)+x; var b := a+1; var c := a+steps+1;var d := c+1
				if valid[a] and valid[b] and valid[c]: indices.append_array([a,c,b])
				if valid[b] and valid[c] and valid[d]: indices.append_array([b,c,d])
		if indices.is_empty(): continue
		var arrays: Array = [];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_INDEX]=indices
		arrays[Mesh.ARRAY_TEX_UV2]=uv2
		var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var node := MeshInstance3D.new();node.mesh=mesh
		var source: Dictionary = library.definition.materials[str(entity.material)]
		if str(source.get("shader","")).contains("DecalWater"):
			var material := ShaderMaterial.new();material.shader=WATER_DECAL_SHADER
			_vision_materials.append(material)
			material.set_shader_parameter("mask_map",library.texture(str(source.get("water_mask",""))))
			var color: Array = source.albedo
			material.set_shader_parameter("water_tint",Color(color[0],color[1],color[2],color[3]))
			material.render_priority=1
			node.material_override=material
		else:
			var material: StandardMaterial3D = library.material(str(entity.material)).duplicate()
			material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
			material.render_priority=1
			node.material_override=material
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node);count+=1
	print("GROUND_ZERO_DECALS zone=",zone," projected=",count)

func _build_terrain() -> void:
	var spec: Dictionary = data.get("terrain",{})
	if spec.is_empty(): return
	_resolution = int(spec.resolution)
	var terrain_transform := Library.transform(spec.transform)
	_terrain_origin = terrain_transform.origin
	_terrain_scale = Vector3(spec.scale[0],spec.scale[1],spec.scale[2])
	var file := FileAccess.open(Library.ROOT+str(spec.heights),FileAccess.READ)
	_heights = file.get_buffer(file.get_length()).to_float32_array()
	var material := ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	_terrain_material=material
	material.set_shader_parameter("blend_map",library.texture(str(spec.alpha)))
	material.set_shader_parameter("terrain_size",Vector2((_resolution-1)*_terrain_scale.x,(_resolution-1)*_terrain_scale.z))
	var names := ["grass","mud","road"]
	for i in range(3):
		var layer: Dictionary = spec.layers[mini(i,spec.layers.size()-1)]
		material.set_shader_parameter(names[i],library.texture(str(layer.texture)))
		material.set_shader_parameter(names[i]+"_size",Vector2(layer.tile_size[0],layer.tile_size[1]))
	for key in spec.chunks:
		var mesh: ArrayMesh = library.geometry(str(key))
		var node := MeshInstance3D.new()
		node.name = str(key)
		node.mesh = mesh
		node.material_override = material
		node.transform = terrain_transform
		add_child(node)
		if build_collisions:
			var body := StaticBody3D.new()
			body.collision_layer = 1|4|8|16
			body.collision_mask = 0
			var shape := CollisionShape3D.new()
			shape.shape = mesh.create_trimesh_shape()
			body.add_child(shape)
			node.add_child(body)
		if get_child_count()%24==0:
			await get_tree().process_frame
			if _cancelled:return

func _build_collisions() -> void:
	for spec in data.colliders:
		if spec.get("trigger",false): continue
		var character := bool(spec.get("blocks_character",true))
		var projectile := bool(spec.get("blocks_projectile",true))
		if not character and not projectile: continue
		var shape := _shape(spec)
		if shape == null: continue
		var body := StaticBody3D.new()
		body.name = "Solid_"+str(_collider_count)
		body.collision_layer = (1 if character else 0)|(8 if projectile else 0)|16
		body.collision_mask = 0
		body.transform = Library.transform(spec.transform)
		body.set_meta("source_name",str(spec.get("name","")))
		body.set_meta("source_id",int(spec.get("id",0)))
		var collision := CollisionShape3D.new()
		collision.shape = shape
		var center: Dictionary = spec.get("center",{})
		collision.position = Vector3(float(center.get("x",0)),float(center.get("y",0)),-float(center.get("z",0)))
		if spec.type=="CapsuleCollider":
			if int(spec.get("direction",1))==0: collision.rotation.z = PI/2
			elif int(spec.get("direction",1))==2: collision.rotation.x = PI/2
		body.add_child(collision)
		add_child(body)
		if zone=="surface":WalkabilityRepairs.fit_door_headroom(body,int(spec.get("id",-1)))
		if spec.has("door_id"): _track_door(spec,body)
		if spec.has("visibility_id"):_track_vision(spec,body)
		_collider_count += 1
		if _collider_count%256==0:
			await get_tree().process_frame
			if _cancelled:return

func _shape(spec: Dictionary) -> Shape3D:
	var key := str([spec.type,spec.get("size",{}),spec.get("radius",0),spec.get("height",0),spec.get("mesh",""),spec.get("convex",false)])
	if _shapes.has(key): return _shapes[key]
	var result: Shape3D
	match str(spec.type):
		"BoxCollider":
			var box := BoxShape3D.new()
			box.size = Vector3(maxf(.001,absf(float(spec.size.x))),maxf(.001,absf(float(spec.size.y))),maxf(.001,absf(float(spec.size.z))))
			result = box
		"SphereCollider":
			var sphere := SphereShape3D.new()
			sphere.radius = maxf(.001,float(spec.radius))
			result = sphere
		"CapsuleCollider":
			var capsule := CapsuleShape3D.new()
			capsule.radius = maxf(.001,float(spec.radius))
			capsule.height = maxf(capsule.radius*2,float(spec.height))
			result = capsule
		"MeshCollider":
			if str(spec.get("mesh","")).is_empty(): return null
			var mesh: ArrayMesh = library.geometry(str(spec.mesh))
			result = mesh.create_convex_shape() if spec.get("convex",false) else mesh.create_trimesh_shape()
	_shapes[key] = result
	return result

func _build_landmarks() -> void:
	var locations: Dictionary = library.read_json("locations.json")
	var scene_id := "Level_GroundZero_1" if zone=="surface" else "Level_GroundZero_Cave"
	for scene in locations.get("sub_scenes",[]):
		if scene.sceneID!=scene_id: continue
		for item in scene.cachedLocations:
			var source: Dictionary = item.position
			landmarks.append({"path":str(item.path),"pos":Vector3(source.x,source.y,-float(source.z))})
	if zone=="surface":
		var entry := Library.source_location("surface","Special/BunkerEntry")
		_interactions.append({"kind":"travel","uid":"surface_to_bunker","world":zone,"title":"返回地下基地（全队）","pos":Vector2(entry.x,entry.z),"height":entry.y,"destination":"bunker","spawn":Vector3(-1,0,4)})
		var exit := Library.source_location("surface","Exits/Exits_1")
		_interactions.append({"kind":"travel","uid":"surface_extraction","world":zone,"title":"撤离至基地（全队）","pos":Vector2(exit.x,exit.z),"height":exit.y,"destination":"bunker","spawn":Vector3(-1,0,4)})
	for entity in data.entities:
		if entity.type=="Door":
			var at := _door_anchor(entity)
			_interactions.append({"kind":"door","uid":str(int(entity.id)),"world":zone,"title":"开关门","pos":Vector2(at.x,at.z),"height":at.y,"initial_open":not bool(entity.data.closed)})
		if entity.type=="SimpleTeleporter" and entity.has("target_position"):
			var at := Library.transform(entity.transform).origin
			var target: Array = entity.target_position
			_interactions.append({"kind":"travel","scope":"player","uid":zone+"_shortcut_"+str(entity.id),"world":zone,"title":"使用传送点","pos":Vector2(at.x,at.z),"height":at.y,"destination":zone,"spawn":Vector3(target[0],target[1],target[2])})
		if entity.type!="MultiSceneTeleporter": continue
		var at := Library.transform(entity.transform).origin
		var destination := "cave" if entity.data.target.sceneID=="Level_GroundZero_Cave" else "surface"
		_interactions.append({"kind":"travel","uid":zone+"_portal_"+str(entity.id),"world":zone,"title":"进入神秘山洞（全队）" if destination=="cave" else "返回零号区（全队）","pos":Vector2(at.x,at.z),"height":at.y,"destination":destination,"spawn":Library.source_location(destination,str(entity.data.target.locationName))})

func terrain_height(pos: Vector2) -> float:
	if _heights.is_empty(): return 0
	var x := clampf((pos.x-_terrain_origin.x)/_terrain_scale.x,0,_resolution-1.001)
	var z := clampf((-pos.y+_terrain_origin.z)/_terrain_scale.z,0,_resolution-1.001)
	var ix := int(x); var iz := int(z)
	var a := lerpf(_heights[iz*_resolution+ix],_heights[iz*_resolution+ix+1],x-ix)
	var b := lerpf(_heights[(iz+1)*_resolution+ix],_heights[(iz+1)*_resolution+ix+1],x-ix)
	return _terrain_origin.y+lerpf(a,b,z-iz)

func obstacles() -> Array[Rect2]: return []
func interactions() -> Array: return _interactions

func camera_focus_for(pos: Vector2) -> Vector3:
	return Vector3(pos.x,terrain_height(pos),pos.y)

func set_view_points(player: Vector3, camera: Vector3) -> void:
	library.set_view(player,camera,not overview_mode)

# Source Door components can sit on a building root, metres away from the leaf.
func _door_anchor(entity: Dictionary) -> Vector3:
	var collider_id:=int(entity.data.doorCollider.m_PathID)
	for spec in data.colliders:
		if int(spec.get("id",-1))!=collider_id:continue
		var center: Dictionary=spec.get("center",{})
		var point:=Vector3(float(center.get("x",0)),float(center.get("y",0)),-float(center.get("z",0)))
		if spec.type=="BoxCollider":point.y-=float(spec.size.y)*.5
		return Library.transform(spec.transform)*point
	return Library.transform(entity.transform).origin

func can_reach_door(id: String, from: Vector3) -> bool:
	var target: Dictionary={}
	for station in _interactions:
		if station.get("kind")=="door" and station.uid==id:target=station;break
	if target.is_empty():return false
	var excluded: Array[RID]=[]
	for part in _door_nodes.get(id,[]):
		if part.node is StaticBody3D:excluded.append(part.node.get_rid())
	# A door must not occlude its own handle, but intervening walls still block use.
	var point:=Vector3(target.pos.x,float(target.height)+.8,target.pos.y)
	var ray:=PhysicsRayQueryParameters3D.create(from+Vector3(0,.8,0),point,17,excluded)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _track_door(spec: Dictionary, node: Node3D) -> void:
	var id := str(spec.door_id)
	if not _door_nodes.has(id):_door_nodes[id]=[]
	var opened:=Library.transform(spec.open_transform)
	_door_nodes[id].append({"node":node,"closed":Library.transform(spec.transform),"open":opened,"closed_only":bool(spec.get("closed_only",false)),"layer":node.collision_layer if node is StaticBody3D else 0})

func update_doors(states: Dictionary) -> void:
	for id in _door_nodes:
		var opened := bool(states.get(id,false))
		if _door_open.has(id) and _door_open[id]==opened: continue
		_door_open[id]=opened
		for part in _door_nodes[id]:
			part.node.transform=part.open if opened else part.closed
			if part.node is StaticBody3D:
				part.node.collision_layer=0 if opened and part.closed_only else int(part.layer)

func can_close_door(id: String) -> bool:
	for part in _door_nodes.get(id,[]):
		if not part.node is StaticBody3D:continue
		var body: StaticBody3D=part.node
		var collider: CollisionShape3D=body.get_child(0)
		var query:=PhysicsShapeQueryParameters3D.new()
		query.shape=collider.shape;query.transform=part.closed*collider.transform
		query.collision_mask=2;query.margin=.02
		if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return false
	return true

func _track_vision(spec: Dictionary, node: Node3D) -> void:
	var id:=str(spec.visibility_id)
	if not _vision_groups.has(id):
		var excluded: Array[RID]=[]
		_vision_groups[id]={"nodes":[],"exclude":excluded,"bounds":AABB(),"has_bounds":false,"points":[]}
	var group: Dictionary=_vision_groups[id]
	if node is StaticBody3D:
		group.exclude.append(node.get_rid())
	else:
		group.nodes.append(node)
		var bounds: AABB=node.global_transform*node.multimesh.get_aabb()
		group.bounds=group.bounds.merge(bounds) if group.has_bounds else bounds
		group.has_bounds=true
		group.points.clear()

func vision_targets() -> Array:
	var result: Array=[]
	for group in _vision_groups.values():
		if not group.has_bounds:continue
		if group.points.is_empty():
			var bounds: AABB=group.bounds
			group.points.append(bounds.get_center())
			for x in [.1,.9]:
				for z in [.1,.9]:
					group.points.append(bounds.position+bounds.size*Vector3(x,.6,z))
		result.append(group)
	return result

func set_vision(active: bool, parameters: Dictionary) -> void:
	library.set_vision(active,parameters)
	if _terrain_material!=null:
		_terrain_material.set_shader_parameter("vision_enabled",active)
		for key in parameters:_terrain_material.set_shader_parameter(key,parameters[key])
	for material in _vision_materials:
		material.set_shader_parameter("vision_enabled",active)
		for key in parameters:material.set_shader_parameter(key,parameters[key])
