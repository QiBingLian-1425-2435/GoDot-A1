extends RefCounted
const Texts = preload("res://features/localization/game_text.gd")

static var materials: Dictionary = {}

static func material(color: Color, metallic: float = 0.0, roughness: float = 0.82, glow: float = 0.0) -> StandardMaterial3D:
	var key := str(color) + ":" + str(metallic) + ":" + str(roughness) + ":" + str(glow)
	if materials.has(key):
		return materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	if glow > 0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glow
	materials[key] = mat
	return mat

static func mesh(parent: Node3D, shape: Mesh, at: Vector3, color: Color, metallic: float = 0.0, roughness: float = 0.82, glow: float = 0.0) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.mesh = shape
	result.material_override = material(color, metallic, roughness, glow)
	result.position = at
	parent.add_child(result)
	return result

static func box(parent: Node3D, at: Vector3, size: Vector3, color: Color, metallic: float = 0.0, glow: float = 0.0) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	return mesh(parent, shape, at, color, metallic, 0.82, glow)

static func sphere(parent: Node3D, at: Vector3, size: Vector3, color: Color, metallic: float = 0.0) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radius = 0.5
	shape.height = 1.0
	shape.radial_segments = 20
	shape.rings = 12
	var result := mesh(parent, shape, at, color, metallic)
	result.scale = size
	return result

static func cylinder(parent: Node3D, at: Vector3, radius: float, height: float, color: Color, top: float = -1.0, metallic: float = 0.0) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.top_radius = radius if top < 0 else top
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 20
	return mesh(parent, shape, at, color, metallic)

static func rod(parent: Node3D, start: Vector3, end: Vector3, radius: float, color: Color, metallic: float = 0.0) -> MeshInstance3D:
	var result := cylinder(parent, (start + end) / 2.0, radius, start.distance_to(end), color, -1, metallic)
	var direction := (end-start).normalized()
	result.quaternion = Quaternion(Vector3.UP, direction)
	return result

static func text(parent: Node3D, label: String, at: Vector3, size: int = 32, color: Color = Color("cbd5bf")) -> Label3D:
	var result := Label3D.new()
	Texts.bind(result, label, "text")
	result.font_size = size
	result.pixel_size = 0.008
	result.outline_size = 0
	result.modulate = color
	result.position = at
	parent.add_child(result)
	return result

static var rounded_meshes: Dictionary = {}

## Soft-cornered box (superellipsoid) for clay-style props; size is the full extent.
static func rounded_box(parent: Node3D, at: Vector3, size: Vector3, color: Color, softness: float = 0.3) -> MeshInstance3D:
	var key := str(size) + ":" + str(softness)
	if not rounded_meshes.has(key):
		rounded_meshes[key] = _superellipsoid(size * .5, lerpf(12.0, 2.2, clampf(softness, 0, 1)))
	return mesh(parent, rounded_meshes[key], at, color)

static func _signed_pow(value: float, exponent: float) -> float:
	return signf(value) * pow(absf(value), exponent)

static func _superellipsoid(half: Vector3, exponent: float) -> ArrayMesh:
	var rings := 14
	var segments := 28
	var power := 2.0 / exponent
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in range(rings + 1):
		var theta := PI * ring / rings
		for segment in range(segments + 1):
			var phi := TAU * segment / segments
			var s := _signed_pow(sin(theta), power)
			tool.add_vertex(Vector3(half.x * s * _signed_pow(cos(phi), power), half.y * _signed_pow(cos(theta), power), half.z * s * _signed_pow(sin(phi), power)))
	for ring in range(rings):
		for segment in range(segments):
			var a := ring * (segments + 1) + segment
			var b := a + segments + 1
			tool.add_index(a); tool.add_index(a + 1); tool.add_index(b)
			tool.add_index(a + 1); tool.add_index(b + 1); tool.add_index(b)
	tool.generate_normals()
	return tool.commit()
