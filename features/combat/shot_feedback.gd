extends Node3D
## Local, bounded presentation of confirmed shot events. Never changes damage.
const G = preload("res://features/geometry/geometry.gd")
var context
var seen: Dictionary = {}
var impacts: Array = []
var kick := 0.0

func observe(shot: Dictionary, age: float) -> void:
	var id: int = int(shot.get("player_id",0))
	var sequence: int = int(shot.get("sequence",0))
	if sequence <= int(seen.get(id,0)): return
	seen[id] = sequence
	if age > 0.16: return
	var rifle: bool = shot.get("weapon","rifle") != "pistol"
	if id == context.session.local_id: kick = minf(0.12,kick + (0.075 if rifle else 0.035))
	if shot.get("impact","none") == "none": return
	if impacts.size() >= 16:
		impacts.pop_front().node.queue_free()
	var node := Node3D.new()
	var point: Vector2 = shot.to
	node.position = Vector3(point.x,float(shot.get("height",.9)),point.y)
	add_child(node)
	var bits: Array = []
	for i in range(6):
		var angle := float(i)*TAU/6.0
		var direction := Vector3(cos(angle),0.4+float(i%3)*0.3,sin(angle))
		var spark = G.box(node,Vector3.ZERO,Vector3(.025,.025,.15),Color("ffe6a1"),0,2.0)
		spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spark.look_at_from_position(node.global_position,node.global_position+direction)
		bits.append({"node":spark,"velocity":direction*(1.4 if rifle else 1.0)})
	var dust = G.sphere(node,Vector3.ZERO,Vector3(.15,.12,.15),Color("b9ac8d"))
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(.65,.60,.49,.4)
	dust.material_override = mat
	var light := OmniLight3D.new()
	light.light_color = Color("ffcb7a"); light.light_energy = 2.0 if rifle else 1.0
	light.omni_range = 2.3; light.shadow_enabled = false
	node.add_child(light)
	impacts.append({"node":node,"bits":bits,"dust":dust,"light":light,"energy":light.light_energy,"target_id":int(shot.get("target_id",-1)),"age":0.0,"sounded":false,"delay":maxf(0.0,Vector2(shot.from).distance_to(point)/140.0-age)})
	node.visible = false

func _process(delta: float) -> void:
	kick = move_toward(kick,0.0,delta*1.2)
	if not is_instance_valid(context) or not context.in_game:
		for impact in impacts: impact.node.queue_free()
		impacts.clear(); seen.clear(); kick = 0.0
		return
	for id in seen.keys():
		if not context.session.model.state.players.has(id): seen.erase(id)
	for target in context.world.target_nodes.values(): target.rotation.z *= exp(-delta*18.0)
	for i in range(impacts.size()-1,-1,-1):
		var impact: Dictionary = impacts[i]
		impact.age += delta
		var time: float = impact.age-impact.delay
		if time < 0: continue
		impact.node.visible = context.vision.can_see(impact.node.global_position)
		if not impact.sounded:
			context.sound.play("impact"); impact.sounded = true
			if context.world.target_nodes.has(impact.target_id):
				context.world.target_nodes[impact.target_id].rotation.z = .12
		if time >= .28:
			impact.node.queue_free(); impacts.remove_at(i); continue
		for bit in impact.bits:
			bit.node.position = bit.velocity*time + Vector3(0,-3*time*time,0)
			bit.node.scale = Vector3.ONE*maxf(0.0,1.0-time/.18)
		impact.dust.scale = Vector3.ONE*(1.0+time*5.0)
		impact.dust.position.y = time*.3
		impact.dust.material_override.albedo_color.a = .4*(1.0-time/.28)
		impact.light.light_energy = maxf(0.0,float(impact.energy)*(1.0-time/.07))
		impact.light.visible = time < .07
