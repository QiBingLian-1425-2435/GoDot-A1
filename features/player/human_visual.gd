extends RefCounted
const Appearance=preload("res://features/player/appearance_rules.gd")
var actor:Node3D
var meshes:Array[MeshInstance3D]=[]
var attachments:Array[Node3D]=[]
var materials:Dictionary={}
var gender:=""
var current:Dictionary={}

func configure(owner:Node3D) -> void:
	actor=owner
	# Keep equipment and held props on the existing tested animation rig.
	var keep:Array=[actor.helmet,actor.backpack,actor.armor,actor.weapon]
	keep.append_array(actor.held_props.values())
	for attachment in actor.skeleton.get_children():
		if attachment is BoneAttachment3D:
			for child in attachment.get_children():
				if child not in keep:child.visible=false
	update(Appearance.defaults())

func update(value:Variant) -> void:
	var appearance:Dictionary=Appearance.normalized(value)
	if appearance==current:return
	if gender!=appearance.gender:
		for attachment in attachments:attachment.free()
		attachments.clear();meshes.clear();materials.clear()
		gender=appearance.gender
		var path:="res://assets/characters/humans/%s.glb"%gender
		var scene:PackedScene=load(path)
		if scene==null:return
		var source:Node3D=scene.instantiate()
		actor.add_child(source)
		for child in source.find_children("*","MeshInstance3D",true,false):
			var bone:String=str(child.name).split("__")[0]
			var index:int=actor.skeleton.find_bone(bone)
			if index<0:continue
			var local:Transform3D=source.global_transform.affine_inverse()*child.global_transform
			var attachment:=BoneAttachment3D.new()
			attachment.bone_name=bone;actor.skeleton.add_child(attachment)
			child.reparent(attachment,false)
			child.transform=actor.skeleton.get_bone_global_rest(index).affine_inverse()*local
			attachments.append(attachment);meshes.append(child)
			for surface in range(child.mesh.get_surface_count()):
				var material:StandardMaterial3D=child.mesh.surface_get_material(surface).duplicate()
				child.set_surface_override_material(surface,material)
				var part:String=material.resource_name.get_slice(".",0)
				if not materials.has(part):materials[part]=[]
				materials[part].append(material)
		source.free()
	for part in Appearance.PARTS:
		for material in materials.get(part,[]):material.albedo_color=Color(appearance[part])
	current=appearance

func set_helmet(visible:bool) -> void:
	for mesh in meshes:
		if "hair" in str(mesh.name) or "fringe" in str(mesh.name) or "bob_side" in str(mesh.name) or "crown_lock" in str(mesh.name):mesh.visible=not visible
