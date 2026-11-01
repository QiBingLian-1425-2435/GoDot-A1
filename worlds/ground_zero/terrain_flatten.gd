extends RefCounted
## Level Ground Zero's surface hills into one walkable plain.
##
## Only terrain above the common ground level is lowered; lake and river basins
## stay so water, bridges and fishing points keep working. Every source object is
## lowered by the hill height that was under its origin, so buildings, trees,
## colliders, doors, lights, landmarks and spawn points stay seated on the ground.
## Runtime-only: the extracted external assets are never rewritten.
const ROOT := "res://assets/worlds/ground_zero/"
const ENABLED_ZONES := ["surface"]
## Shared ground height of the source map (most of the plain sits here).
const GROUND_LEVEL := -0.0064
## Appended to the map revision so rooms never mix levelled and hilly builds.
const REVISION_TAG := "+flat1"
## Ignore sub-centimetre noise so flat ground is not touched.
const EPSILON := 0.02

static var _sources: Dictionary = {}

static func enabled(zone: String) -> bool:
	return zone in ENABLED_ZONES

## Loads (once) the original height field of a zone, independent of map nodes.
static func _source(zone: String) -> Dictionary:
	if _sources.has(zone): return _sources[zone]
	var result: Dictionary = {}
	var file := FileAccess.open(ROOT+zone+".json",FileAccess.READ)
	if file != null:
		var data: Variant = JSON.parse_string(file.get_as_text())
		var spec: Dictionary = data.get("terrain",{}) if data is Dictionary else {}
		if not spec.is_empty():
			var heights_file := FileAccess.open(ROOT+str(spec.heights),FileAccess.READ)
			if heights_file != null:
				var values: Array = spec.transform
				result = {
					"heights":heights_file.get_buffer(heights_file.get_length()).to_float32_array(),
					"resolution":int(spec.resolution),
					"origin":Vector3(float(values[9]),float(values[10]),float(values[11])),
					"scale":Vector3(spec.scale[0],spec.scale[1],spec.scale[2]),
				}
	_sources[zone] = result
	return result

## Original (un-flattened) terrain height in world space.
static func source_height(zone: String, x: float, z: float) -> float:
	var source := _source(zone)
	if source.is_empty(): return GROUND_LEVEL
	var heights: PackedFloat32Array = source.heights
	var resolution: int = source.resolution
	var origin: Vector3 = source.origin
	var scale: Vector3 = source.scale
	var gx := clampf((x-origin.x)/scale.x,0,resolution-1.001)
	var gz := clampf((-z+origin.z)/scale.z,0,resolution-1.001)
	var ix := int(gx); var iz := int(gz)
	var a := lerpf(heights[iz*resolution+ix],heights[iz*resolution+ix+1],gx-ix)
	var b := lerpf(heights[(iz+1)*resolution+ix],heights[(iz+1)*resolution+ix+1],gx-ix)
	return origin.y+lerpf(a,b,gz-iz)

## Vertical change (zero or negative) applied to anything that stood at x/z.
static func offset(zone: String, x: float, z: float) -> float:
	if not enabled(zone): return 0.0
	var hill := source_height(zone,x,z)-GROUND_LEVEL
	return -hill if hill>EPSILON else 0.0

static func lower(zone: String, point: Vector3) -> Vector3:
	return point+Vector3(0,offset(zone,point.x,point.z),0)

## Heights stored relative to the terrain origin, clamped to the plain.
static func flatten_heights(heights: PackedFloat32Array, origin_y: float) -> PackedFloat32Array:
	var result := heights.duplicate()
	var level := GROUND_LEVEL-origin_y
	for i in range(result.size()):
		if result[i]>level: result[i]=level
	return result

## Copy of a terrain chunk with every vertex above the plain pressed onto it.
static func flatten_chunk(mesh: ArrayMesh, origin_y: float) -> ArrayMesh:
	var level := GROUND_LEVEL-origin_y
	var result := ArrayMesh.new()
	for surface in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in range(vertices.size()):
			if vertices[i].y>level:
				vertices[i].y=level
				if i<normals.size(): normals[i]=Vector3.UP
		arrays[Mesh.ARRAY_VERTEX]=vertices
		if not normals.is_empty(): arrays[Mesh.ARRAY_NORMAL]=normals
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		result.surface_set_material(surface,mesh.surface_get_material(surface))
	return result

## Re-seat all source placements of an extracted zone in place.
static func apply(data: Dictionary, zone: String) -> void:
	if not enabled(zone): return
	for key in ["renderers","colliders","entities","lights"]:
		for item in data.get(key,[]):
			if not item is Dictionary: continue
			# Door leaves keep their hinge: open/closed poses move together.
			var shift := _lower_transform(zone,item,"transform",null)
			_lower_transform(zone,item,"open_transform",shift)
			if item.has("target_position") and item.target_position is Array and item.target_position.size()>=3:
				var target: Array = item.target_position
				target[1]=float(target[1])+offset(zone,float(target[0]),float(target[2]))

static func _lower_transform(zone: String, item: Dictionary, key: String, forced: Variant) -> float:
	if not item.has(key) or not item[key] is Array: return 0.0
	var values: Array = item[key]
	if values.size()<12: return 0.0
	var shift: float = float(forced) if forced!=null else offset(zone,float(values[9]),float(values[11]))
	if shift!=0.0: values[10]=float(values[10])+shift
	return shift
