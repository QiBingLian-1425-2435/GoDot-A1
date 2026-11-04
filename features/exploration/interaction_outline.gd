extends Node3D
## Observer-local shells. Shared meshes/materials and authoritative state remain untouched.
const OUTLINE=preload("res://features/exploration/interaction_outline.gdshader")
var shells:Array[GeometryInstance3D]=[]
var key:=""
func clear()->void:
 for node in shells:
  if is_instance_valid(node):node.hide();node.free()
 shells.clear();key=""
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
func _outline(node:Variant)->void:
 if node is Dictionary:
  var shell:=MeshInstance3D.new();shell.mesh=node.source.multimesh.mesh
  var material:=ShaderMaterial.new();material.shader=OUTLINE;shell.material_override=material
  shell.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;shell.name="LocalInteractionOutline"
  node.source.add_child(shell);shell.transform=node.source.multimesh.get_instance_transform(node.index);shells.append(shell)
  return
 if node.has_node("LocalInteractionOutline"):return
 if node is GeometryInstance3D and not node is Label3D:
  var shell:GeometryInstance3D
  if node is MeshInstance3D:
   var mesh:=MeshInstance3D.new();mesh.mesh=node.mesh;shell=mesh
  elif node is MultiMeshInstance3D:
   var mesh:=MultiMeshInstance3D.new();mesh.multimesh=node.multimesh;shell=mesh
  if shell!=null:
   var material:=ShaderMaterial.new();material.shader=OUTLINE
   shell.material_override=material;shell.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
   shell.name="LocalInteractionOutline";node.add_child(shell);shells.append(shell)
 # Snapshot children before recursion so shells never recursively outline themselves.
 for child in node.get_children():
  if child.name!="LocalInteractionOutline":_outline(child)
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
