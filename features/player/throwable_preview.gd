extends Node3D
const Rules=preload("res://features/combat/throwable_system.gd")
var target:=Vector3.ZERO
var requested:=Vector3.ZERO
var line:MeshInstance3D

func _ready()->void:
	line=MeshInstance3D.new();add_child(line)
	var mat:=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo=true;mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	line.material_override=mat;line.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func update(ctx,p:Dictionary,show_preview:bool)->void:
	visible=show_preview
	if not visible:return
	var mouse:Vector2=ctx.get_viewport().get_mouse_position()
	var plane:=Plane(Vector3.UP,float(p.get("height",0)))
	var point:Variant=plane.intersects_ray(ctx.camera.project_ray_origin(mouse),ctx.camera.project_ray_normal(mouse))
	if not point is Vector3:visible=false;return
	update_target(p,point,func(a:Vector3,b:Vector3)->Dictionary:return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,9)))

func update_target(p:Dictionary,point:Vector3,query:Callable=Callable())->void:
	requested=point
	var path:=Rules.arc(p,point,query);target=path.back()
	var mesh:=ImmediateMesh.new();mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_set_color(Color(1,.91,.6,.95))
	for i in range(path.size()-1):
		if i%3==2:continue
		mesh.surface_add_vertex(path[i]);mesh.surface_add_vertex(path[i+1])
	mesh.surface_set_color(Color(1,.8,.4,.85))
	for i in range(96):
		var a:float=TAU*i/96;var b:float=TAU*(i+1)/96
		mesh.surface_add_vertex(target+Vector3(cos(a),.05,sin(a))*Rules.RADIUS)
		mesh.surface_add_vertex(target+Vector3(cos(b),.05,sin(b))*Rules.RADIUS)
	mesh.surface_end();line.mesh=mesh
