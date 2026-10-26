extends Node3D
const Texts = preload("res://features/localization/game_text.gd")
## Local view of host-owned bodies. The observer shares only the teammate's view.
const Actor = preload("res://features/player/base_actor.gd")
var bodies: Dictionary = {}
var ghost: Node3D
var _environment: Environment
var _lighting: Dictionary = {}

func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new();node.mesh=mesh;node.position=at;node.material_override=material
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

func _build_ghost() -> void:
	ghost=Node3D.new();ghost.name="LocalSoulAvatar";add_child(ghost)
	var glow := StandardMaterial3D.new()
	glow.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.albedo_color=Color(.55,.93,1,.72);glow.emission_enabled=true;glow.emission=Color(.18,.65,.85)
	glow.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var head:=SphereMesh.new();head.radius=.32;head.height=.64
	_mesh(ghost,head,Vector3(0,.5,0),glow)
	var tail:=CylinderMesh.new();tail.top_radius=.29;tail.bottom_radius=.025;tail.height=.65
	_mesh(ghost,tail,Vector3(0,.1,0),glow)
	var dark:=StandardMaterial3D.new();dark.albedo_color=Color(.015,.08,.15);dark.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	for side in [-1,1]:
		var eye:=SphereMesh.new();eye.radius=.045;eye.height=.09
		_mesh(ghost,eye,Vector3(side*.11,.55,-.28),dark)
		var wisp:=SphereMesh.new();wisp.radius=.1;wisp.height=.2
		_mesh(ghost,wisp,Vector3(side*.16,-.28,.12),glow)
	var ring:=TorusMesh.new();ring.inner_radius=.39;ring.outer_radius=.43
	_mesh(ghost,ring,Vector3(0,.95,0),glow)

func _bright(ctx, enabled: bool) -> void:
	if _environment==null:
		for child in ctx.get_children():
			if child is WorldEnvironment:
				_environment=child.environment
				_lighting={"energy":_environment.ambient_light_energy,"color":_environment.ambient_light_color,"source":_environment.ambient_light_source}
	if _environment==null:return
	_environment.ambient_light_energy=1.0 if enabled else _lighting.energy
	_environment.ambient_light_color=Color.WHITE if enabled else _lighting.color
	_environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR if enabled else _lighting.source

func update(ctx) -> void:
	var p: Dictionary=ctx.session.model.state.players.get(ctx.session.local_id,{})
	var roaming: bool=ctx.in_game and not ctx.world_loading and ctx.session.model.Souls.free_soul(p)
	_bright(ctx,roaming)
	if not is_instance_valid(ghost):_build_ghost()
	ghost.visible=roaming
	if roaming:
		var at:=Vector3(p.pos.x,float(p.get("height",0)),p.pos.y)
		if ctx.actors.has(ctx.session.local_id):at=ctx.actors[ctx.session.local_id].position
		ghost.position=at+Vector3(0,.8+sin(Time.get_ticks_msec()*.004)*.12,0)
		var aim: Vector2=p.get("aim",Vector2.UP)
		ghost.rotation.y=atan2(-aim.x,-aim.y)
	var corpses: Dictionary = ctx.session.model.state.get("corpses",{})
	for uid in bodies.keys():
		if not corpses.has(uid): bodies[uid].queue_free(); bodies.erase(uid)
	for uid in corpses:
		var body: Dictionary = corpses[uid]
		if not bodies.has(uid):
			var actor = Actor.new()
			add_child(actor)
			actor.setup(Color("879398"),str(body.container_name))
			bodies[uid] = actor
		var actor = bodies[uid]
		actor.update_actor({"pos":body.pos,"height":body.height,"equipment":{},"aim":Vector2.UP},0)
		actor.pivot.rotation.z = PI*.5
		actor.pivot.position.y = .38
		Texts.bind(actor.nameplate, str(body.container_name)+"⟦soul_view.001⟧", "text")
		actor.visible = ctx.in_game and not ctx.world_loading and ctx.vision.can_see(Vector3(body.pos.x,float(body.height)+.4,body.pos.y))
	for id in ctx.actors:
		if not ctx.session.model.Souls.mobile(ctx.session.model.state.players.get(id,{})): ctx.actors[id].visible=false
