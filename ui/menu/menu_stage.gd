extends Node3D
## Original procedural menu scenery: no extracted commercial assets.
var camera: Camera3D
var head: Node3D
var clock := 0.0

func _ready() -> void:
	position = Vector3(100, 0, 0)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 11.5
	add_child(camera)
	camera.position = Vector3(0, 3, 13)
	camera.look_at(global_position + Vector3(0, 2.5, 0))
	var backdrop:=MeshInstance3D.new()
	var quad:=QuadMesh.new()
	quad.size=Vector2(36,24)
	backdrop.mesh=quad
	backdrop.position=Vector3(0,2,-5)
	var fog_shader:=Shader.new()
	fog_shader.code="""shader_type spatial;
render_mode unshaded, fog_disabled;
float h(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(h(i),h(i+vec2(1,0)),f.x),mix(h(i+vec2(0,1)),h(i+vec2(1,1)),f.x),f.y);}
void fragment(){vec2 p=UV;float n=noise(p*4.0+TIME*0.009)*0.6+noise(p*11.0-TIME*0.012)*0.3+noise(p*24.0)*0.1;vec3 c=mix(vec3(0.009,0.019,0.055),vec3(0.018,0.11,0.18),n);c+=vec3(0.08,0.15,0.17)*exp(-length((p-vec2(0.65,0.51))*vec2(1.0,1.4))*18.0);c+=vec3(0.03,0.07,0.11)*exp(-length(p-vec2(0.35,0.4))*8.0);ALBEDO=c;}
"""
	var fog_material:=ShaderMaterial.new()
	fog_material.shader=fog_shader
	backdrop.material_override=fog_material
	add_child(backdrop)
	_box(self, Vector3(4.1, 7.2, -0.2), Vector3(0.65, 5, 0.7), Color("354c59"))
	_box(self, Vector3(4.1, 5, 0), Vector3(2.8, 0.45, 0.65), Color("566c72"))
	head = Node3D.new()
	head.position = Vector3(4, 3.7, 0)
	head.scale=Vector3.ONE*1.42
	head.rotation_degrees = Vector3(-7,-18,0)
	add_child(head)
	_box(head, Vector3.ZERO, Vector3(2.3, 1.9, 3.0), Color("456577"))
	_box(head, Vector3(0,0.89,0.1), Vector3(2.6,0.22,3.5), Color("7c9392"))
	_box(head, Vector3(0,0,1.51), Vector3(2.03,1.63,0.22), Color("9b6560"))
	_box(head, Vector3(0,0,1.65), Vector3(1.77,1.36,0.12), Color("212c3d"))
	_box(head, Vector3(0,0,1.73), Vector3(1.29,1.04,0.04), Color("581e2f"))
	for x in [-1,1]:
		for y in [-1,1]:
			_box(head,Vector3(x*0.55,y*0.41,1.78),Vector3(0.37,0.035,0.02),Color("ff7048"),true)
			_box(head,Vector3(x*0.72,y*0.25,1.78),Vector3(0.035,0.34,0.02),Color("ff7048"),true)
	_box(head,Vector3(0,0,1.8),Vector3(0.2,0.035,0.02),Color("ff9653"),true)
	_box(head,Vector3(0,0,1.8),Vector3(0.035,0.2,0.02),Color("ff9653"),true)
	for x in [-1.3,1.3]:
		var pivot := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.62
		mesh.bottom_radius = 0.62
		mesh.height = 0.28
		pivot.mesh = mesh
		pivot.rotation.z = PI/2
		pivot.position = Vector3(x,0.25,-0.6)
		pivot.material_override = _mat(Color("627d82"))
		head.add_child(pivot)
		_box(head,Vector3(x,1.2,-0.6),Vector3(0.18,1.8,0.38),Color("445b67"))
	for i in range(5):
		_box(head,Vector3(1.17,0,-1.0+i*0.25),Vector3(0.025,0.6,0.055),Color("1b3445"))
	var rim := OmniLight3D.new()
	rim.position = Vector3(4,6,4)
	rim.light_color = Color("8edbe4")
	rim.light_energy = 2.3
	rim.omni_range = 12
	add_child(rim)
	var red := OmniLight3D.new()
	red.position = Vector3(3.2,3.7,3)
	red.light_color = Color("ff633f")
	red.light_energy = 0.8
	red.omni_range = 4
	add_child(red)

func _process(delta:float)->void:
	clock += delta
	if head:
		head.rotation.y = deg_to_rad(-18) + sin(clock*0.27)*0.09

func _mat(color:Color, glow:=false)->StandardMaterial3D:
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=color
	mat.roughness=0.7
	if glow:
		mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled=true
		mat.emission=color
	return mat

func _box(parent:Node3D,p:Vector3,size:Vector3,color:Color,glow:=false)->void:
	var node:=MeshInstance3D.new()
	if parent==head and size.min_axis_index()>=0 and minf(size.x,minf(size.y,size.z))>0.15:
		node.mesh=_rounded_box(size,minf(0.18,minf(size.x,minf(size.y,size.z))*0.24))
	else:
		var mesh:=BoxMesh.new()
		mesh.size=size
		node.mesh=mesh
	node.material_override=_mat(color,glow)
	node.position=p
	parent.add_child(node)

func _rounded_box(size:Vector3,radius:float)->ArrayMesh:
	var surface:=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half:=size*0.5
	var inner:=half-Vector3.ONE*radius
	var axes:=[Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.BACK,Vector3.FORWARD]
	for normal in axes:
		var u:Vector3=Vector3.UP.cross(normal).normalized() if absf(normal.y)<0.9 else Vector3.RIGHT
		var v:Vector3=normal.cross(u)
		var steps:=12
		for x in range(steps):
			for y in range(steps):
				for offset in [Vector2(0,0),Vector2(0,1),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(1,0)]:
					var p:Vector3=(normal+u*((x+offset.x)/steps*2-1)+v*((y+offset.y)/steps*2-1))*half
					var nearest:=p.clamp(-inner,inner)
					var outward:Vector3=(p-nearest).normalized()
					surface.set_normal(outward)
					surface.add_vertex(nearest+outward*radius)
	return surface.commit()
