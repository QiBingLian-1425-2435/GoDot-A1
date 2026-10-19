extends RefCounted

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
	result.text = label
	result.font_size = size
	result.pixel_size = 0.008
	result.outline_size = 0
	result.modulate = color
	result.position = at
	parent.add_child(result)
	return result
