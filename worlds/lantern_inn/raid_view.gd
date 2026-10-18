extends Node3D
## Snapshot presentation only; never confirms gameplay ownership or rewards.

const ActorScene = preload("res://features/player/actor_view.gd")
const PickupScene = preload("res://features/inventory/pickup_view.gd")
const HudScene = preload("res://ui/hud.gd")
var session
var world
var hud
var camera: Camera3D
var actors: Dictionary = {}
var loot_nodes: Dictionary = {}
var corpse_nodes: Dictionary = {}
var monster
var sound
var extraction: Node3D
var ring: MeshInstance3D
var camera_origin := Vector3.ZERO
var event_clock := 0.0
var input_clock := 0.0
var elapsed := 0.0
var capture_path := ""
var captured := false
var help_open := false
var muted := false
var last_local_status := "alive"
var last_bag_count := 0
var last_round := -1
var last_phase := ""
var automated := false
var last_monster_mode := "patrol"

func setup_environment()->void:
	var env:=WorldEnvironment.new()
	var e:=Environment.new()
	e.background_mode=Environment.BG_COLOR
	e.background_color=Color("101e2a")
	e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color=Color("b5c7d4")
	e.ambient_light_energy=0.28
	e.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	e.tonemap_exposure=1.0
	env.environment=e
	add_child(env)
	var key:=DirectionalLight3D.new()
	key.rotation_degrees=Vector3(-57,-28,0)
	key.light_color=Color("ffe1aa")
	key.light_energy=0.45
	key.shadow_enabled=true
	key.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance=55
	key.shadow_blur=2.0
	add_child(key)
	var fill:=DirectionalLight3D.new()
	fill.rotation_degrees=Vector3(-30,155,0)
	fill.light_color=Color("84a9bd")
	fill.light_energy=0.11
	add_child(fill)
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=27.0
	camera.position=Vector3(18,24,27)
	camera.look_at_from_position(camera.position,Vector3.ZERO)
	camera.h_offset=3.4
	camera.v_offset=0.5
	camera.near=0.1
	camera.far=120
	add_child(camera)
	camera.current=true
	camera_origin=camera.position

func create_extraction()->void:
	extraction=Node3D.new()
	extraction.position=Vector3(8,0.17,5.5)
	add_child(extraction)
	ring=MeshInstance3D.new()
	var mesh:=TorusMesh.new()
	mesh.inner_radius=1.40
	mesh.outer_radius=1.49
	mesh.rings=64
	mesh.ring_segments=8
	ring.mesh=mesh
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=Color("83d3b4")
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled=true
	mat.emission=Color("83d3b4")
	ring.material_override=mat
	extraction.add_child(ring)
	var center:=MeshInstance3D.new()
	var c:=CylinderMesh.new()
	c.top_radius=1.40
	c.bottom_radius=1.40
	c.height=0.008
	center.mesh=c
	var translucent:=StandardMaterial3D.new()
	translucent.albedo_color=Color(0.38,0.75,0.59,0.12)
	translucent.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	translucent.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	center.material_override=translucent
	extraction.add_child(center)
	var label:=Label3D.new()
	label.text="归途之灯  /  撤离"
	label.position=Vector3(0,0.28,1.65)
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size=25
	label.pixel_size=0.012
	label.modulate=Color("c0ebc7")
	label.outline_size=8
	extraction.add_child(label)
	var l:=OmniLight3D.new()
	l.position.y=1.8
	l.light_color=Color("9ce7b4")
	l.light_energy=0.45
	l.omni_range=4
	extraction.add_child(l)

func _process(delta:float)->void:
	if session==null:
		return
	elapsed+=delta
	var state:Dictionary=session.model.state
	var me:Dictionary=state.players.get(session.local_id,{})
	var is_spectating:bool=me.get("status", "alive") in ["dead","extracted"]
	var focus:Vector2=me.get("pos",Vector2.ZERO)
	var viewed_id:int=int(me.get("possessing",0))
	if is_spectating:
		if viewed_id==0 or not state.players.has(viewed_id) or not state.players[viewed_id].status in ["alive","downed"]:
			viewed_id=0
			for id in state.players:
				if state.players[id].get("status", "") in ["alive","downed"]:
					viewed_id=int(id)
					break
		if viewed_id!=0:
			focus=state.players[viewed_id].pos
	var existing_ids:Array=state.players.keys()
	for id in actors.keys():
		if not id in existing_ids:
			actors[id].queue_free()
			actors.erase(id)
	var idx:=0
	for id in state.players:
		var player:Dictionary=state.players[id]
		if not actors.has(id):
			var actor=ActorScene.new()
			var texture_path:="res://assets/characters/hero.png" if idx%2==0 else "res://assets/characters/companion.png"
			actor.setup(texture_path,Color("efd096") if int(id)==session.local_id else Color("8ac5d2"),player.name)
			add_child(actor)
			actors[id]=actor
		var a=actors[id]
		a.visible=player.status!="extracted" and player.status!="dead"
		if is_spectating:
			a.visible=a.visible and (player.pos as Vector2).distance_to(focus)<5.5
		a.update_actor(player,delta,int(id)==session.local_id)
		idx+=1
	if monster==null:
		monster=ActorScene.new()
		monster.setup("res://assets/characters/monster.png",Color("b48fcb"),"巡夜者",true)
		add_child(monster)
	if not state.monster.is_empty():
		monster.visible=state.phase=="raid" and (not is_spectating or state.monster.pos.distance_to(focus)<5.5)
		monster.update_actor(state.monster,delta)
		if state.monster.mode=="chase" and last_monster_mode!="chase" and int(state.monster.get("target",0))==session.local_id and sound!=null:
			sound.play("danger")
		last_monster_mode=state.monster.mode
	update_loot(state,focus,is_spectating)
	update_corpses(state,focus,is_spectating)
	ring.scale=Vector3.ONE*(1.0+sin(elapsed*1.5)*0.014)
	if not me.is_empty():
		if me.status!=last_local_status and sound!=null:
			if me.status=="downed":
				sound.play("down")
			elif me.status=="extracted":
				sound.play("extract")
			elif me.status=="alive" and last_local_status=="downed":
				sound.play("rescue")
		if me.bag.size()>last_bag_count and sound!=null:
			sound.play("pickup")
		last_local_status=me.status
		last_bag_count=me.bag.size()
	event_clock+=delta
	if event_clock>=0.12:
		event_clock=0
		update_hud()
	if capture_path!="" and elapsed>4.0 and not captured:
		captured=true
		await RenderingServer.frame_post_draw
		var img:=get_viewport().get_texture().get_image()
		var err:=img.save_png(capture_path)
		print("CAPTURE_RESULT ",err," ",capture_path)
		if "--quit-after-capture" in OS.get_cmdline_user_args():
			get_tree().quit()
	if automated and elapsed>6 and not captured:
		captured=true
		print("UI_SMOKE_PASS players=",actors.size()," loot=",loot_nodes.size()," phase=",state.phase)
		get_tree().quit()

func update_loot(state:Dictionary,focus:Vector2,restricted:bool)->void:
	var ids:Array=[]
	for item in state.loot:
		ids.append(item.id)
		if not loot_nodes.has(item.id):
			var node=PickupScene.new()
			node.setup(item)
			add_child(node)
			loot_nodes[item.id]=node
		var node=loot_nodes[item.id]
		node.position.x=item.pos.x
		node.position.z=item.pos.y
		node.visible=state.phase=="raid" and (not restricted or item.pos.distance_to(focus)<5.5)
		node.tag.visible=node.visible and item.pos.distance_to(focus)<2.3
	for id in loot_nodes.keys():
		if not id in ids:
			loot_nodes[id].queue_free()
			loot_nodes.erase(id)

func update_corpses(state:Dictionary,focus:Vector2,restricted:bool)->void:
	var ids:Array=[]
	for corpse in state.corpses:
		ids.append(corpse.id)
		if not corpse_nodes.has(corpse.id):
			var n:=Node3D.new()
			n.position=Vector3(corpse.pos.x,0.1,corpse.pos.y)
			var mesh:=MeshInstance3D.new()
			var box:=BoxMesh.new()
			box.size=Vector3(0.7,0.32,0.46)
			mesh.mesh=box
			var mat:=StandardMaterial3D.new()
			mat.albedo_color=Color("735946")
			mesh.material_override=mat
			n.add_child(mesh)
			var label:=Label3D.new()
			label.text="遗留行囊"
			label.font_size=22
			label.position.y=0.75
			label.pixel_size=0.008
			label.modulate=Color("e6bda0")
			label.outline_size=7
			label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
			n.add_child(label)
			add_child(n)
			corpse_nodes[corpse.id]=n
		corpse_nodes[corpse.id].visible=state.phase=="raid" and not corpse.items.is_empty() and (not restricted or corpse.pos.distance_to(focus)<5.5)
	for id in corpse_nodes.keys():
		if not id in ids:
			corpse_nodes[id].queue_free()
			corpse_nodes.erase(id)

func update_hud()->void:
	if hud!=null:
		hud.update_view(session.model.state,session.local_id,session.mode,session.connection_status)
