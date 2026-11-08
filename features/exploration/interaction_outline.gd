extends Node3D
## Observer-local silhouette mask; shared meshes, materials and state remain untouched.
const OUTLINE=preload("res://features/exploration/interaction_outline.gdshader")
var shells:Array[GeometryInstance3D]=[]
var key:=""
var mask:SubViewport
var mask_camera:Camera3D
var layer:CanvasLayer
var overlay:TextureRect
func clear()->void:
 for node in shells:
  if is_instance_valid(node):node.hide();node.free()
 shells.clear();key=""
 if is_instance_valid(overlay):overlay.hide()
 if is_instance_valid(mask):mask.render_target_update_mode=SubViewport.UPDATE_DISABLED
func update(ctx)->void:
 var target:Dictionary=ctx.nearest
 if not ctx.in_game or ctx.world_loading or target.is_empty():clear();return
 var next_key:String=str(ctx.world.get_instance_id())+":"+str(target.get("kind",""))+":"+str(target.get("uid",target.get("id","")))
 if key==next_key:return
 clear();key=next_key
 var nodes:Array=[]
 match str(target.get("kind","")):
  "pickup":
   if ctx.drops.has(target.uid):nodes=[ctx.drops[target.uid]]
  "corpse":
   if ctx.soul_view.bodies.has(target.uid):nodes=[ctx.soul_view.bodies[target.uid]]
  _:
   if ctx.world.has_method("interaction_visuals"):nodes=ctx.world.interaction_visuals(target)
 for node in nodes:_outline(node)
 # Nearby opaque geometry writes the occluder channel into the same depth-tested mask, so
 # tables, walls and players hide the portions of the target behind them.
 var selected:Array=[]
 for shell in shells:selected.append(shell.get_meta("original"))
 var point:=Vector3(target.get("pos",Vector2.ZERO).x,1,target.get("pos",Vector2.ZERO).y)
 if not shells.is_empty():point=shells[0].global_position
 for node in nearby_visuals(ctx.world,point,5.0):
  var original=node.source if node is Dictionary else node
  if original not in selected:_outline(node,true)
 for actor in ctx.actors.values():_outline(actor,true)
func _outline(node:Variant,occluder:bool=false)->void:
 if node is Dictionary:
  _copy_mesh(node.source.multimesh.mesh,node.source,node.source.multimesh.get_instance_transform(node.index),occluder);return
 if node is MeshInstance3D and node.mesh!=null:_copy_mesh(node.mesh,node,Transform3D.IDENTITY,occluder)
 elif node is MultiMeshInstance3D and node.multimesh!=null:
  for i in node.multimesh.instance_count:_copy_mesh(node.multimesh.mesh,node,node.multimesh.get_instance_transform(i),occluder)
 for child in node.get_children():_outline(child,occluder)
func _copy_mesh(mesh:Mesh,original:Node3D,offset:Transform3D,occluder:bool=false):
 _setup_mask()
 mask.render_target_update_mode=SubViewport.UPDATE_ALWAYS
 var copy:=MeshInstance3D.new();copy.mesh=mesh
 var material:=ShaderMaterial.new();material.shader=OUTLINE;material.set_shader_parameter("mask_value",0.0 if occluder else 1.0);copy.material_override=material
 mask.add_child(copy);copy.global_transform=original.global_transform*offset
 # Reuse the live skin/skeleton for animated blockers and targets. Copying
 # only the mesh renders its bind pose and leaves a detached human silhouette.
 if original is MeshInstance3D:
  var skeleton:Node=original.get_node_or_null(original.skeleton)
  if skeleton is Skeleton3D:
   copy.skin=original.skin;copy.skeleton=copy.get_path_to(skeleton)
  for i in original.get_blend_shape_count():copy.set_blend_shape_value(i,original.get_blend_shape_value(i))
 copy.set_meta("original",original);copy.set_meta("offset",offset);shells.append(copy)
func _setup_mask():
 if is_instance_valid(mask):return
 mask=SubViewport.new();mask.own_world_3d=true;mask.transparent_bg=true;mask.render_target_update_mode=SubViewport.UPDATE_ALWAYS;mask.msaa_3d=Viewport.MSAA_DISABLED;add_child(mask)
 mask_camera=Camera3D.new();mask.add_child(mask_camera)
 layer=CanvasLayer.new();layer.layer=1;add_child(layer)
 overlay=TextureRect.new();overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE;overlay.texture=mask.get_texture();layer.add_child(overlay)
 var material:=ShaderMaterial.new();material.shader=load("res://features/exploration/interaction_silhouette.gdshader");overlay.material=material
func _process(_delta:float):
 if not is_instance_valid(mask):return
 overlay.visible=not shells.is_empty()
 if shells.is_empty():return
 var camera:=get_viewport().get_camera_3d()
 if camera==null:return
 var size:Vector2i=Vector2i(get_viewport().get_visible_rect().size)
 if mask.size!=size:mask.size=size;overlay.size=Vector2(size)
 mask_camera.global_transform=camera.global_transform;mask_camera.projection=camera.projection;mask_camera.size=camera.size;mask_camera.fov=camera.fov;mask_camera.near=camera.near;mask_camera.far=camera.far;mask_camera.keep_aspect=camera.keep_aspect
 for copy in shells:
  var original=copy.get_meta("original")
  if is_instance_valid(original):
   copy.global_transform=original.global_transform*copy.get_meta("offset");copy.visible=original.is_visible_in_tree()
   if original is MeshInstance3D:
    for i in original.get_blend_shape_count():copy.set_blend_shape_value(i,original.get_blend_shape_value(i))
  else:copy.visible=false
static func nearby_visuals(root:Node3D,point:Vector3,radius:float=2.0)->Array:
 var result:Array=[]
 for node in root.find_children("*","GeometryInstance3D",true,false):
  if node is Label3D or node.name=="LocalInteractionOutline":continue
  if node is MultiMeshInstance3D:
   var mesh_bounds:AABB=node.multimesh.mesh.get_aabb()
   for i in node.multimesh.instance_count:
    var instance_bounds:AABB=node.global_transform*node.multimesh.get_instance_transform(i)*mesh_bounds
    if instance_bounds.size.y<.12 or instance_bounds.size.length()>6:continue
    if point.clamp(instance_bounds.position,instance_bounds.end).distance_to(point)<radius:result.append({"source":node,"index":i})
   continue
  var bounds:AABB=node.global_transform*node.get_aabb()
  if bounds.size.y<.12 or bounds.size.length()>6:continue
  var nearest:Vector3=point.clamp(bounds.position,bounds.end)
  if nearest.distance_to(point)<radius:result.append(node)
 return result
