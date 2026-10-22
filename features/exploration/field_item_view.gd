extends Node3D
## Renders confirmed field effects; owns no item consumption or timers.
var nodes:Dictionary={}
func update(ctx) -> void:
	var active:Dictionary={}
	var excluded:Array[RID]=[]
	for effect in ctx.session.model.state.get("field_effects",[]):
		if effect.world!=ctx.world_id or float(effect.ttl)-ctx.session.snapshot_age()<=0:continue
		active[effect.uid]=true
		if not nodes.has(effect.uid):
			var node:=Node3D.new();add_child(node);node.position=effect.pos
			var mesh:=MeshInstance3D.new();var sphere:=SphereMesh.new()
			sphere.radius=3 if effect.kind=="smoke_grenade" else .12;sphere.height=sphere.radius*2;sphere.radial_segments=16;sphere.rings=8;mesh.mesh=sphere
			var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.45,.5,.48,.32) if effect.kind=="smoke_grenade" else Color("6ce5bd") if effect.kind=="glowstick" else Color("69baff")
			if effect.kind=="smoke_grenade":mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;mesh.position.y=1
			else:mat.emission_enabled=true;mat.emission=mat.albedo_color;mat.emission_energy_multiplier=1.5;mesh.position.y=.2
			mesh.material_override=mat;node.add_child(mesh)
			if effect.kind=="glowstick":
				var light:=OmniLight3D.new();light.position.y=.6;light.omni_range=6;light.light_color=Color("99e6c3");light.light_energy=1.2;light.shadow_enabled=true;node.add_child(light)
			if effect.kind=="beacon":
				var label:=Label3D.new();label.text="集合点 · "+str(effect.get("owner_name","队友")).left(8);label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.no_depth_test=true;label.position.y=2;label.font_size=26;label.pixel_size=.015;label.modulate=Color("83caff");node.add_child(label)
			nodes[effect.uid]={"root":node,"mesh":mesh}
		var part:Dictionary=nodes[effect.uid]
		part.root.visible=ctx.in_game and not ctx.world_loading
		part.mesh.visible=effect.kind=="beacon" or ctx.vision.can_see(effect.pos+Vector3.UP,excluded,effect.kind=="smoke_grenade")
	for uid in nodes.keys():
		if not active.has(uid):nodes[uid].root.queue_free();nodes.erase(uid)

func clear() -> void:
	for part in nodes.values():part.root.visible=false;part.root.queue_free()
	nodes.clear()
