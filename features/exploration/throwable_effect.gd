extends Node3D
const Rules=preload("res://features/combat/throwable_system.gd")
var phase:=""
var parts:Array[MeshInstance3D]=[]
var lamp:OmniLight3D

func mesh(shape:Mesh,color:Color,emission:float=0.0)->MeshInstance3D:
	var node:=MeshInstance3D.new();node.mesh=shape
	var mat:=StandardMaterial3D.new();mat.albedo_color=color
	mat.roughness=1.0
	if color.a<1:mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission>0:mat.emission_enabled=true;mat.emission=color;mat.emission_energy_multiplier=emission
	node.material_override=mat;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node);parts.append(node);return node

func build(kind:String,next_phase:String)->void:
	for child in get_children():remove_child(child);child.queue_free()
	parts.clear();lamp=null;phase=next_phase
	if phase=="flight":
		var model:Node3D=load("res://assets/props/throwables/"+kind+".glb").instantiate();add_child(model);return
	if kind=="smoke_grenade":
		for i in range(28):
			var sphere:=SphereMesh.new();sphere.radius=.8;sphere.height=1.6;sphere.radial_segments=12;sphere.rings=6
			mesh(sphere,Color(.48+float(i%3)*.04,.51+float(i%3)*.04,.49+float(i%3)*.04,.7))
	elif kind=="molotov":
		var pool:=CylinderMesh.new();pool.top_radius=Rules.RADIUS;pool.bottom_radius=Rules.RADIUS;pool.height=.025;pool.radial_segments=48
		mesh(pool,Color(.12,.045,.015,.32)).position.y=.04
		for i in range(42):
			mesh(flame_shape(),Color(1,.25 if i%3 else .62,.035),.9)
	else:
		var flash:=SphereMesh.new();flash.radius=1;flash.height=2;flash.radial_segments=16;flash.rings=8
		mesh(flash,Color(1,.55,.09,.7),4.0)
		var ring:=TorusMesh.new();ring.inner_radius=.93;ring.outer_radius=1;ring.rings=32;ring.ring_segments=8
		mesh(ring,Color(1,.7,.28,.7),2.0)
		for i in range(18):
			var debris:=SphereMesh.new();debris.radius=.12;debris.height=.24;debris.radial_segments=6;debris.rings=3
			mesh(debris,Color(.34,.27,.21,.65))
	if kind!="smoke_grenade":
		lamp=OmniLight3D.new();lamp.omni_range=7;lamp.light_color=Color(1,.38,.1);lamp.light_energy=2;add_child(lamp);lamp.position.y=.6

func update_effect(effect:Dictionary,age_offset:float)->void:
	var next_phase:String=effect.get("phase","active")
	if phase!=next_phase:build(effect.kind,next_phase)
	var age:float=float(effect.get("age",0))+age_offset
	if phase=="flight":
		for child in get_children():
			if child is Node3D:child.visible=age>=0
		position=Rules.point(effect.path,(age)/float(effect.duration));rotation=Vector3(age*8,age*4,age*3);return
	position=effect.pos;rotation=Vector3.ZERO
	var fade:float=clampf(float(effect.ttl)-age_offset,0,1)
	if effect.kind=="smoke_grenade":
		for i in parts.size():
			var a:float=float(i)*2.399+age*.035
			var r:float=sqrt(float(i)/28)*2.0
			parts[i].position=Vector3(cos(a)*r,.55+float(i%4)*.42+sin(age*.8+i)*.13,sin(a)*r)
			parts[i].scale=Vector3.ONE*(.8+.18*sin(age+i))*minf(1,.3+age*2)*fade
	elif effect.kind=="molotov":
		for i in range(1,parts.size()):
			var a:float=i*2.399;var r:float=sqrt(float(i-1)/42)*2.6
			var height:float=.45+.5*(.5+.5*sin(age*12+i*1.7))
			parts[i].position=Vector3(cos(a)*r,height*.45,sin(a)*r)
			parts[i].position.y=.04
			parts[i].scale=Vector3(1.3,height,1.3)*fade
			parts[i].rotation.y=age*.7+i
		if lamp!=null:lamp.light_energy=(1.8+sin(age*20)*.4)*fade
	else:
		parts[0].scale=Vector3.ONE*maxf(.01,(1.0-age/.45)*2.0)
		parts[1].position.y=.1;parts[1].scale=Vector3.ONE*minf(Rules.RADIUS,age*9)
		for i in range(2,parts.size()):
			var a:float=i*2.399;var r:float=minf(3,age*(2+i%4))
			parts[i].position=Vector3(cos(a)*r,maxf(.1,age*3-age*age*4),sin(a)*r)
			parts[i].scale=Vector3.ONE*fade
		if lamp!=null:lamp.light_energy=maxf(0,3-age*8)

func flame_shape()->ArrayMesh:
	var vertices:=PackedVector3Array()
	for j in 3:
		var heights:=[0.0,.32,.7,1.2]
		var radii:=[.12,.25,.14,0.0]
		for i in 6:
			var a:float=TAU*i/6;var b:float=TAU*(i+1)/6
			var p:=Vector3(cos(a)*radii[j],heights[j],sin(a)*radii[j])
			var q:=Vector3(cos(b)*radii[j],heights[j],sin(b)*radii[j])
			var r:=Vector3(cos(a)*radii[j+1]+.05*j,heights[j+1],sin(a)*radii[j+1])
			var s:=Vector3(cos(b)*radii[j+1]+.05*j,heights[j+1],sin(b)*radii[j+1])
			vertices.append_array(PackedVector3Array([p,r,q,q,r,s]))
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices
	var result:=ArrayMesh.new();result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result
