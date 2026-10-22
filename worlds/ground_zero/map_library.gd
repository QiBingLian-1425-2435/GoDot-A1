extends RefCounted
## Decodes generated external assets; no game rules or network state live here.
const ROOT := "res://assets/worlds/ground_zero/"
const SURFACE_SHADER = preload("res://worlds/ground_zero/source_surface.gdshader")
const DOUBLE_SURFACE_SHADER = preload("res://worlds/ground_zero/source_surface_double.gdshader")
const ALPHA_SURFACE_SHADER = preload("res://worlds/ground_zero/source_surface_alpha.gdshader")
var definition: Dictionary = {}
var _geometry: Dictionary = {}
var _render_meshes: Dictionary = {}
var _materials: Dictionary = {}
var _textures: Dictionary = {}

func _init() -> void:
	definition = read_json("library.json")

func read_json(path: String) -> Dictionary:
	var file := FileAccess.open(ROOT+path,FileAccess.READ)
	if file == null:
		push_error("Ground Zero external asset missing: "+ROOT+path)
		return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	return value if value is Dictionary else {}

func texture(path: String) -> Texture2D:
	if path.is_empty(): return null
	if not _textures.has(path): _textures[path] = load(ROOT+path)
	return _textures[path]

func material(key: String, roof: bool=false) -> Material:
	var cache_key:=key+"@roof" if roof else key
	if _materials.has(cache_key): return _materials[cache_key]
	var spec: Dictionary = definition.materials.get(key,{})
	if not str(spec.get("shader","")).contains("Decal"):
		var source_material := ShaderMaterial.new()
		source_material.shader = ALPHA_SURFACE_SHADER if spec.get("transparent",false) else (DOUBLE_SURFACE_SHADER if int(spec.get("cull",2))==0 else SURFACE_SHADER)
		source_material.resource_name = str(spec.get("name",key))
		source_material.set_shader_parameter("roof_surface",roof)
		source_material.set_shader_parameter("has_albedo",not str(spec.get("texture","")).is_empty())
		source_material.set_shader_parameter("albedo_map",texture(str(spec.get("texture",""))))
		var color: Array = spec.get("albedo",[1,1,1,1])
		source_material.set_shader_parameter("tint",Color(color[0],color[1],color[2],color[3]))
		var scale: Array = spec.get("uv_scale",[1,1]);var offset: Array = spec.get("uv_offset",[0,0])
		source_material.set_shader_parameter("uv_scale",Vector2(scale[0],scale[1]))
		source_material.set_shader_parameter("uv_offset",Vector2(offset[0],-float(offset[1])))
		source_material.set_shader_parameter("alpha_clip",bool(spec.get("alpha_clip",false)))
		source_material.set_shader_parameter("cutoff",float(spec.get("alpha_cutoff",.5)))
		source_material.set_shader_parameter("surface_roughness",float(spec.get("roughness",.9)))
		var emission: Array = spec.get("emission",[0,0,0])
		source_material.set_shader_parameter("emission_color",Vector3(emission[0],emission[1],emission[2]))
		_materials[cache_key] = source_material
		return source_material
	var result := StandardMaterial3D.new()
	result.resource_name = str(spec.get("name",key))
	var color: Array = spec.get("albedo",[1,1,1,1])
	result.albedo_color = Color(float(color[0]),float(color[1]),float(color[2]),float(color[3]))
	result.albedo_texture = texture(str(spec.get("texture","")))
	result.roughness = clampf(float(spec.get("roughness",.9)),.05,1.0)
	result.cull_mode = {0:BaseMaterial3D.CULL_DISABLED,1:BaseMaterial3D.CULL_FRONT,2:BaseMaterial3D.CULL_BACK}.get(int(spec.get("cull",2)),BaseMaterial3D.CULL_BACK)
	# Original custom shaders use RGB vertex channels as foliage/wind masks.
	# They are not painted surface colors and must not tint a whole tree red.
	result.vertex_color_use_as_albedo = false
	result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var uv_scale: Array = spec.get("uv_scale",[1,1])
	var uv_offset: Array = spec.get("uv_offset",[0,0])
	result.uv1_scale = Vector3(float(uv_scale[0]),float(uv_scale[1]),1)
	result.uv1_offset = Vector3(float(uv_offset[0]),-float(uv_offset[1]),0)
	if spec.get("alpha_clip",false):
		result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		result.alpha_scissor_threshold = float(spec.get("alpha_cutoff",.5))
	elif spec.get("transparent",false): result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var emission: Array = spec.get("emission",[0,0,0])
	var energy := maxf(float(emission[0]),maxf(float(emission[1]),float(emission[2])))
	if energy>.001:
		result.emission_enabled = true
		result.emission = Color(float(emission[0]),float(emission[1]),float(emission[2]))/maxf(1,energy)
		result.emission_energy_multiplier = minf(energy,3)
	_materials[cache_key] = result
	return result

func set_view(player: Vector3, camera: Vector3, enabled: bool) -> void:
	for value in _materials.values():
		if not value is ShaderMaterial: continue
		value.set_shader_parameter("view_player",player+Vector3(0,.65,0))
		value.set_shader_parameter("view_camera",camera)
		value.set_shader_parameter("view_enabled",enabled)

func set_vision(active: bool, parameters: Dictionary) -> void:
	for value in _materials.values():
		if not value is ShaderMaterial:continue
		value.set_shader_parameter("vision_enabled",active)
		for key in parameters:value.set_shader_parameter(key,parameters[key])

func geometry(key: String) -> ArrayMesh:
	if _geometry.has(key): return _geometry[key]
	var path: String = ROOT+str(definition.meshes[key].path)
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_buffer(4).get_string_from_ascii()!="DGM1":
		push_error("Invalid extracted mesh: "+path)
		return ArrayMesh.new()
	var count := file.get_32()
	var surfaces := file.get_32()
	var colors := file.get_32()!=0
	var vertices := file.get_buffer(count*12).to_float32_array()
	var normals := file.get_buffer(count*12).to_float32_array()
	var uv := file.get_buffer(count*8).to_float32_array()
	var vertex_colors := file.get_buffer(count*16).to_float32_array() if colors else PackedFloat32Array()
	var positions := PackedVector3Array()
	var directions := PackedVector3Array()
	var texcoords := PackedVector2Array()
	var tint := PackedColorArray()
	positions.resize(count); directions.resize(count); texcoords.resize(count)
	if colors: tint.resize(count)
	for i in range(count):
		positions[i] = Vector3(vertices[i*3],vertices[i*3+1],vertices[i*3+2])
		directions[i] = Vector3(normals[i*3],normals[i*3+1],normals[i*3+2])
		texcoords[i] = Vector2(uv[i*2],uv[i*2+1])
		if colors: tint[i] = Color(vertex_colors[i*4],vertex_colors[i*4+1],vertex_colors[i*4+2],vertex_colors[i*4+3])
	var mesh := ArrayMesh.new()
	for _surface in range(surfaces):
		var index_count := file.get_32()
		var indices := file.get_buffer(index_count*4).to_int32_array()
		if index_count==0: continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_NORMAL] = directions
		arrays[Mesh.ARRAY_TEX_UV] = texcoords
		arrays[Mesh.ARRAY_INDEX] = indices
		if colors: arrays[Mesh.ARRAY_COLOR] = tint
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_geometry[key] = mesh
	return mesh

func render_mesh(key: String, materials: Array, roof: bool=false) -> ArrayMesh:
	var cache_key := key+"/"+str(materials)+"/"+str(roof)
	if not _render_meshes.has(cache_key):
		var mesh: ArrayMesh = geometry(key).duplicate()
		for i in range(mesh.get_surface_count()):
			mesh.surface_set_material(i,material(str(materials[mini(i,materials.size()-1)]),roof) if not materials.is_empty() else material("",roof))
		_render_meshes[cache_key] = mesh
	return _render_meshes[cache_key]

static func transform(values: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(values[0],values[1],values[2]),Vector3(values[3],values[4],values[5]),Vector3(values[6],values[7],values[8])),Vector3(values[9],values[10],values[11]))

static func source_location(zone: String, path: String) -> Vector3:
	var file := FileAccess.open(ROOT+"locations.json",FileAccess.READ)
	if file==null: return Vector3.ZERO
	var locations: Dictionary = JSON.parse_string(file.get_as_text())
	var scene_id := "Level_GroundZero_1" if zone=="surface" else "Level_GroundZero_Cave"
	for scene in locations.get("sub_scenes",[]):
		if scene.sceneID!=scene_id: continue
		for item in scene.cachedLocations:
			if item.path==path:
				return Vector3(item.position.x,item.position.y,-float(item.position.z))
	return Vector3.ZERO
