extends Node3D

var phase := 0.0
var inner: Node3D
var tag: Label3D
var kind := ""

func setup(data: Dictionary) -> void:
	kind = str(data.get("kind", "relic"))
	var pos: Vector2 = data.get("pos", Vector2.ZERO)
	position = Vector3(pos.x, 0.18, pos.y)
	phase = pos.x + pos.y
	var color := Color(str(data.get("color", "dfbd75")))
	var disc := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.23
	ring.outer_radius = 0.27
	ring.rings = 24
	ring.ring_segments = 6
	disc.mesh = ring
	disc.material_override = material(Color(color, 0.6), true)
	add_child(disc)
	inner = Node3D.new()
	inner.position.y = 0.3
	add_child(inner)
	if "book" in kind or "tome" in kind:
		box(Vector3(0.43,0.12,0.34),Vector3.ZERO,Color("d2b888"))
		box(Vector3(0.46,0.035,0.37),Vector3(0,0.08,0),color)
		box(Vector3(0.46,0.035,0.37),Vector3(0,-0.08,0),color)
	elif "bottle" in kind or "potion" in kind or "vial" in kind:
		ball(0.22, Vector3.ZERO,color)
		box(Vector3(0.12,0.22,0.12), Vector3(0,0.23,0),Color("d8b87a"))
	elif "coin" in kind:
		for i in range(3):
			var m := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius=0.22
			cyl.bottom_radius=0.22
			cyl.height=0.07
			m.mesh=cyl
			m.position.y=i*0.08
			m.material_override=material(color)
			inner.add_child(m)
	elif "crown" in kind or "relic" in kind or "idol" in kind:
		box(Vector3(0.35,0.12,0.35),Vector3(0,-0.15,0),Color("9c713e"))
		ball(0.22,Vector3(0,0.13,0),color)
		box(Vector3(0.10,0.42,0.10),Vector3(0,0.12,0),color)
	else:
		var m := MeshInstance3D.new()
		var crystal := CylinderMesh.new()
		crystal.top_radius=0.0
		crystal.bottom_radius=0.23
		crystal.height=0.58
		crystal.radial_segments=5
		m.mesh=crystal
		m.material_override=material(color,true)
		inner.add_child(m)
	tag = Label3D.new()
	tag.text = str(data.get("name", "遗物"))
	tag.position.y = 1.0
	tag.font_size = 22
	tag.pixel_size = 0.008
	tag.outline_size=7
	tag.modulate = Color("f3ddb0")
	tag.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	add_child(tag)
	tag.visible=false

func material(color: Color, glow := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color=color
	m.roughness=0.65
	if glow:
		m.emission_enabled=true
		m.emission=color*0.5
	return m

func box(size:Vector3,pos:Vector3,color:Color) -> void:
	var m:=MeshInstance3D.new()
	var shape:=BoxMesh.new()
	shape.size=size
	m.mesh=shape
	m.position=pos
	m.material_override=material(color)
	inner.add_child(m)

func ball(radius:float,pos:Vector3,color:Color) -> void:
	var m:=MeshInstance3D.new()
	var shape:=SphereMesh.new()
	shape.radius=radius
	shape.height=radius*2
	shape.radial_segments=10
	shape.rings=6
	m.mesh=shape
	m.position=pos
	m.material_override=material(color)
	inner.add_child(m)

func _process(delta: float) -> void:
	phase += delta
	if inner:
		inner.position.y = 0.32 + sin(phase * 2.2) * 0.07
		inner.rotation.y += delta * 0.35
