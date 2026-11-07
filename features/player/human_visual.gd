extends RefCounted
const Appearance=preload("res://features/player/appearance_rules.gd")
const TEXTURE_BASE := {"male":{"hair":"#493329","skin":"#d9ad83","shirt":"#706847","pants":"#967e53"},"female":{"hair":"#493329","skin":"#d9ad83","shirt":"#b58a4b","pants":"#736e4c"}}
var imported_motion:RefCounted
var actor:Node3D
var source:Node3D
var skin:Skeleton3D
var meshes:Array[MeshInstance3D]=[]
var materials:Dictionary={}
var gender:=""
var current:Dictionary={}
func configure(owner:Node3D)->void:
 actor=owner
 var keep:Array=[actor.helmet,actor.backpack,actor.armor,actor.weapon]
 keep.append_array(actor.held_props.values())
 for attachment in actor.skeleton.get_children():
  if attachment is BoneAttachment3D:
   for child in attachment.get_children():
    if child not in keep:child.visible=false
 update(Appearance.defaults())
func update(value:Variant)->void:
 var appearance:Dictionary=Appearance.normalized(value)
 if appearance!=current:
  if gender!=appearance.gender:
   if is_instance_valid(source):source.free()
   meshes.clear();materials.clear();skin=null
   gender=appearance.gender
   source=load("res://assets/characters/adventurers/animated_%s.glb"%gender).instantiate();actor.add_child(source)
   for node in source.find_children("*","Skeleton3D",true,false):skin=node
   for child in source.find_children("*","MeshInstance3D",true,false):
    meshes.append(child)
    for surface in child.mesh.get_surface_count():
     var material:StandardMaterial3D=child.mesh.surface_get_material(surface).duplicate()
     child.set_surface_override_material(surface,material)
     var part:String=material.resource_name.get_slice(".",0)
     if not materials.has(part):materials[part]=[]
     materials[part].append(material)
   imported_motion=preload("res://features/player/animation/imported_motion.gd").new()
   imported_motion.configure(actor,source,skin)
  var defaults:Dictionary=TEXTURE_BASE[gender]
  for part in Appearance.PARTS:
   var color:=Color(appearance[part]);var base:=Color(defaults[part])
   for material in materials.get(part,[]):material.albedo_color=Color(color.r/base.r,color.g/base.g,color.b/base.b,1)
  current=appearance.duplicate(true)
func advance(data:Dictionary,delta:float)->void:
 if imported_motion!=null:imported_motion.advance(data,delta)

func sync_pose()->void:
 if imported_motion!=null:imported_motion.advance({},0.0)

func set_helmet(visible:bool)->void:
 for material in materials.get("hair",[]):
  material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA if visible else BaseMaterial3D.TRANSPARENCY_DISABLED
  material.albedo_color.a=0.0 if visible else 1.0
