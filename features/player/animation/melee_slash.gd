extends Node3D
const Sweep=preload("res://features/combat/melee_sweep.gd")
var geometry:=ImmediateMesh.new()
var visual:=MeshInstance3D.new()
func _init():
	name="MeleeSlash";visual.mesh=geometry
	visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode=BaseMaterial3D.BLEND_MODE_ADD
	material.vertex_color_use_as_albedo=true
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	visual.material_override=material;add_child(visual);visible=false
func update_slash(kind:String,phase:float,enabled:bool,crouched:bool)->void:
	visible=enabled and phase>Sweep.START and phase<Sweep.FADE_END
	geometry.clear_surfaces()
	if not visible:return
	var fade:float=1.0-smoothstep(Sweep.END,Sweep.FADE_END,phase)
	var last:float=Sweep.angle(minf(phase,Sweep.END))
	var count:int=maxi(1,ceili((Sweep.HALF_ANGLE-last)/.045))
	var radius:=Sweep.reach(kind);var at_y:=Sweep.height(crouched)
	geometry.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in count:
		var a:float=lerpf(Sweep.HALF_ANGLE,last,float(i)/count)
		var b:float=lerpf(Sweep.HALF_ANGLE,last,float(i+1)/count)
		var ra:float=_clear_radius(a,radius,at_y);var rb:float=_clear_radius(b,radius,at_y)
		# Pale outer crescent with a translucent filled sweep, all inside hit reach.
		var head:float=lerpf(.35,1.0,float(i+1)/count)*fade
		for band in 3:
			var fractions:=[0.0,.72,.93,1.0]
			var opacity:=[.025,.09,.65,0.0]
			var inner_a:float=lerpf(minf(Sweep.INNER_RADIUS,ra),ra,fractions[band]);var outer_a:float=lerpf(minf(Sweep.INNER_RADIUS,ra),ra,fractions[band+1])
			var inner_b:float=lerpf(minf(Sweep.INNER_RADIUS,rb),rb,fractions[band]);var outer_b:float=lerpf(minf(Sweep.INNER_RADIUS,rb),rb,fractions[band+1])
			var low:=Color(.15,.65,1,opacity[band]*head);var high:=Color(.72,.94,1,opacity[band+1]*head)
			_vertex(a,inner_a,at_y,low);_vertex(a,outer_a,at_y,high);_vertex(b,outer_b,at_y,high)
			_vertex(a,inner_a,at_y,low);_vertex(b,outer_b,at_y,high);_vertex(b,inner_b,at_y,low)
	geometry.surface_end()
func _vertex(angle:float,radius:float,y:float,color:Color)->void:
	geometry.surface_set_color(color);geometry.surface_add_vertex(Vector3(sin(angle)*radius,y,-cos(angle)*radius))
func _clear_radius(angle:float,radius:float,y:float)->float:
	if not is_inside_tree():return radius
	var start:Vector3=global_transform*Vector3(0,y,0)
	var end:Vector3=global_transform*Vector3(sin(angle)*radius,y,-cos(angle)*radius)
	var hit:Dictionary=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start,end,8))
	return maxf(0.0,minf(radius,start.distance_to(hit.position)-.025)) if not hit.is_empty() else radius
