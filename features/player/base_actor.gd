extends Node3D

const G = preload("res://features/geometry/geometry.gd")
const Motion = preload("res://features/player/animation/duck_motion.gd")
const BONES := [
	["Root", -1, Vector3.ZERO], ["Hips", 0, Vector3(0,.72,.06)],
	["Spine", 1, Vector3(0,.20,-.02)], ["Head", 2, Vector3(0,.38,-.14)],
	["Tail", 1, Vector3(0,-.05,.32)], ["FootL", 0, Vector3(-.19,.20,0)],
	["FootR", 0, Vector3(.19,.20,0)], ["WingL", 2, Vector3(-.37,.03,-.07)],
	["WingR", 2, Vector3(.37,.03,-.07)], ["Gun", 2, Vector3(.30,-.07,-.38)],
	["Pack", 2, Vector3(0,-.02,.34)]
]
var skeleton: Skeleton3D
var motion: RefCounted
var animation_state := "idle"
var action_state := ""
var action_time := 0.0
var magazine: MeshInstance3D
var rifle_mesh: Node3D
var pistol_mesh: Node3D
var held_props: Dictionary = {}
var _eyes: Array[MeshInstance3D] = []
var _clock := 0.0
var _speed := 0.0
var _run_blend := 0.0
var _crouch_blend := 0.0
var _aim_blend := 0.0
var _unarmed_blend := 0.0
var _recoil := 0.0
var _event_seq := 0
var _event_time := 0.0
var _event_action := ""
var _event_duration := 0.0
var _event_suppressed := -1
var _visual_action := ""
var _visual_action_time := 0.0
var _visual_action_weight := 0.0
var _reload_time := 0.0
var _was_reloading := false
var _idle_data: Dictionary = {}
var pivot: Node3D
var left_foot: Node3D
var right_foot: Node3D
var left_wing: Node3D
var right_wing: Node3D
var weapon: Node3D
var flash: MeshInstance3D
var flash_light: OmniLight3D
var backpack: Node3D
var helmet: Node3D
var armor: Node3D
var nameplate: Label3D
var local_ring: MeshInstance3D
var has_previous_pos: bool = false
var previous_shots: int = 0
var flash_time: float = 0
var initialized: bool = false
var base_tint := Color("75834e")

func setup(tint: Color, title: String) -> void:
	if initialized:
		return
	initialized = true
	base_tint = tint
	pivot = Node3D.new()
	pivot.name = "Rig"
	add_child(pivot)
	_build_skeleton()
	var white := Color("f0eee0")
	var shadow_white := Color("c9cabc")
	var orange := Color("e2a044")
	var olive := tint.darkened(0.12)
	# Pear-shaped silhouette, broad cheeks, and a projecting rounded bill.
	var body := G.sphere(pivot, Vector3(0,.72,.06), Vector3(.77,.89,.69), white)
	_bind(body, "Hips")
	var head := Node3D.new()
	pivot.add_child(head)
	G.sphere(head, Vector3(0,1.30,-.10), Vector3(.72,.69,.68), white)
	var tail := G.sphere(pivot, Vector3(0,.67,.38), Vector3(.35,.3,.39), shadow_white)
	tail.rotation.x = -.3
	_bind(tail, "Tail")
	G.sphere(head, Vector3(0,1.18,-.48), Vector3(.46,.15,.39), orange)
	G.sphere(head, Vector3(0,1.125,-.47), Vector3(.42,.07,.32), orange.darkened(.14))
	for side in [-1,1]:
		_eyes.append(G.sphere(head, Vector3(side*.221,1.365,-.369), Vector3(.079,.106,.052), Color("161b1b")))
		_eyes.append(G.sphere(head, Vector3(side*.21,1.389,-.394), Vector3(.021,.025,.014), Color.WHITE))
		G.sphere(head, Vector3(side*.092,1.215,-.613), Vector3(.023,.015,.025), Color("a36a31"))
	_bind(head, "Head")
	# Vest wraps the lower torso, with webbing, buckles and separate ammunition pouches.
	armor = Node3D.new()
	pivot.add_child(armor)
	_build_vest_shell(olive)
	G.box(armor, Vector3(0,.90,-.321), Vector3(.47,.36,.075), tint)
	for side in [-1,1]:
		G.box(armor, Vector3(side*.18,1.07,-.19), Vector3(.105,.25,.13), olive)
		G.box(armor, Vector3(side*.14,.76,-.381), Vector3(.19,.24,.12), tint.lightened(.10))
		G.box(armor, Vector3(side*.14,.84,-.452), Vector3(.17,.047,.025), tint.darkened(.3))
	G.box(armor, Vector3(0,.98,-.37), Vector3(.1,.075,.018), Color("c9b98c"))
	G.box(armor, Vector3(0,.57,-.18), Vector3(.55,.085,.35), Color("393c31"))
	G.box(armor, Vector3(0,.57,-.375), Vector3(.10,.07,.035), Color("a59a71"), .6)
	_bind(armor, "Hips")
	_build_gear()
	_bind(helmet, "Head")
	_bind(backpack, "Pack")
	# Duck feet pivot at their ankles, producing a readable waddle.
	left_foot = Node3D.new()
	left_foot.position = Vector3(-.19,.20,0)
	pivot.add_child(left_foot)
	right_foot = Node3D.new()
	right_foot.position = Vector3(.19,.20,0)
	pivot.add_child(right_foot)
	for foot in [left_foot,right_foot]:
		G.cylinder(foot,Vector3(0,-.035,0),.045,.19,orange.darkened(.15))
		G.sphere(foot,Vector3(0,-.11,-.10),Vector3(.25,.11,.37),orange)
		for toe in [-1,0,1]:
			G.box(foot,Vector3(toe*.07,-.108,-.235),Vector3(.037,.029,.06),orange.lightened(.08))
	_bind(left_foot, "FootL")
	_bind(right_foot, "FootR")
	left_wing = Node3D.new()
	left_wing.position = Vector3(-.37,.95,-.03)
	pivot.add_child(left_wing)
	G.sphere(left_wing,Vector3(0,-.16,-.04),Vector3(.25,.48,.30),white)
	right_wing = Node3D.new()
	right_wing.position = Vector3(.37,.95,-.03)
	pivot.add_child(right_wing)
	G.sphere(right_wing,Vector3(0,-.16,-.10),Vector3(.25,.45,.31),white)
	_bind(left_wing, "WingL")
	_bind(right_wing, "WingR")
	weapon = Node3D.new()
	weapon.position = Vector3(.30,.85,-.34)
	pivot.add_child(weapon)
	_build_weapon()
	_bind(weapon, "Gun")
	_build_props()
	nameplate = G.text(self,title,Vector3(0,2.03,0),25,Color("f2ead4"))
	nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nameplate.outline_size = 7
	nameplate.outline_modulate = Color(0.07,0.09,0.10,.8)
	nameplate.no_depth_test = true
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = .45
	ring_mesh.outer_radius = .49
	ring_mesh.rings = 32
	ring_mesh.ring_segments = 8
	local_ring = G.mesh(self,ring_mesh,Vector3(0,.025,0),Color("bfc28d"),0,.8,.1)
	local_ring.scale.y = .1
	local_ring.visible = false
	motion = Motion.new()
	motion.build(self)
	motion.advance(.001, 0, 0, 0, 0, 1, "", 0, 0)
	set_process(false)

func _build_skeleton() -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	pivot.add_child(skeleton)
	for spec in BONES:
		var index := skeleton.add_bone(spec[0])
		if spec[1] >= 0: skeleton.set_bone_parent(index, spec[1])
		skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, spec[2]))
		skeleton.reset_bone_pose(index)

func _bind(node: Node3D, bone: String) -> void:
	var attachment := BoneAttachment3D.new()
	attachment.name = bone + "Attachment"
	skeleton.add_child(attachment)
	attachment.bone_name = bone
	node.reparent(attachment, false)
	node.position -= skeleton.get_bone_global_rest(skeleton.find_bone(bone)).origin

func _build_vest_shell(color: Color) -> void:
	# A shell follows the body surface, with clean collar/hem edges instead of
	# intersecting two ellipsoids (which exposed jagged white patches in closeups).
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for row in range(13):
		var theta := lerpf(.74, 2.02, float(row)/12)
		for column in range(33):
			var angle := TAU*float(column)/32
			var unit := Vector3(sin(theta)*sin(angle), cos(theta), sin(theta)*cos(angle))
			vertices.append(Vector3(unit.x*.405, .72+unit.y*.445, .06+unit.z*.365))
			normals.append(Vector3(unit.x/.405, unit.y/.445, unit.z/.365).normalized())
	for row in range(12):
		for column in range(32):
			var a := row*33+column
			indices.append_array(PackedInt32Array([a,a+1,a+33,a+1,a+34,a+33]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var shape := ArrayMesh.new()
	shape.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	G.mesh(armor,shape,Vector3.ZERO,color)

func _build_gear() -> void:
	helmet = Node3D.new()
	pivot.add_child(helmet)
	var dome := SphereMesh.new()
	dome.radius = .386
	dome.height = .40
	dome.radial_segments = 24
	dome.rings = 12
	dome.is_hemisphere = true
	G.mesh(helmet,dome,Vector3(0,1.45,-.08),base_tint.darkened(.2)).scale = Vector3(1,.75,1)
	G.cylinder(helmet,Vector3(0,1.445,-.08),.39,.062,base_tint.darkened(.30)).scale.z = 1.03
	G.box(helmet,Vector3(0,1.64,-.334),Vector3(.13,.10,.06),Color("475247"),.4)
	G.box(helmet,Vector3(0,1.64,-.37),Vector3(.072,.05,.025),Color("a3a887"),.7)
	for side in [-1,1]:
		G.box(helmet,Vector3(side*.33,1.35,-.02),Vector3(.045,.26,.13),Color("47513b"))
	backpack = Node3D.new()
	backpack.position = Vector3(0,.90,.38)
	pivot.add_child(backpack)
	G.box(backpack,Vector3.ZERO,Vector3(.52,.58,.28),base_tint.darkened(.10))
	G.box(backpack,Vector3(0,.22,.025),Vector3(.55,.15,.31),base_tint)
	G.box(backpack,Vector3(0,-.07,.17),Vector3(.41,.28,.095),base_tint.lightened(.08))
	for side in [-1,1]:
		G.box(backpack,Vector3(side*.16,0,.23),Vector3(.055,.45,.025),Color("3c4431"))
		G.box(backpack,Vector3(side*.16,.04,.25),Vector3(.08,.065,.025),Color("aba178"),.5)
	G.cylinder(backpack,Vector3(.32,-.05,.02),.085,.35,Color("708079"),-1,.3)

func _build_weapon() -> void:
	var metal := Color("303635")
	var wood := Color("655440")
	rifle_mesh = Node3D.new()
	weapon.add_child(rifle_mesh)
	G.box(rifle_mesh,Vector3(0,0,-.08),Vector3(.15,.15,.43),metal,.6)
	G.box(rifle_mesh,Vector3(0,-.11,.02),Vector3(.08,.24,.10),wood)
	magazine = G.box(rifle_mesh,Vector3(0,-.16,-.20),Vector3(.095,.23,.15),metal.darkened(.18),.4)
	magazine.rotation.x = -.20
	G.box(rifle_mesh,Vector3(0,0,.23),Vector3(.11,.17,.28),wood)
	G.box(rifle_mesh,Vector3(0,.015,-.37),Vector3(.13,.13,.23),wood)
	G.rod(rifle_mesh,Vector3(0,.025,-.46),Vector3(0,.025,-.79),.036,metal,.7)
	G.box(rifle_mesh,Vector3(0,.14,-.08),Vector3(.06,.1,.16),metal)
	G.box(rifle_mesh,Vector3(0,.095,-.64),Vector3(.04,.12,.04),metal)
	pistol_mesh = Node3D.new()
	weapon.add_child(pistol_mesh)
	G.box(pistol_mesh,Vector3(0,.015,-.10),Vector3(.12,.13,.34),metal,.65)
	G.box(pistol_mesh,Vector3(0,-.13,.0),Vector3(.09,.24,.13),Color("554f42")).rotation.x = -.18
	G.box(pistol_mesh,Vector3(0,.09,-.22),Vector3(.025,.035,.04),Color("b3b5a4"),.6)
	G.rod(pistol_mesh,Vector3(0,.015,-.23),Vector3(0,.015,-.30),.027,metal,.7)
	pistol_mesh.visible = false
	var flash_shape := SphereMesh.new()
	flash_shape.radius = .12
	flash_shape.height = .24
	flash = G.mesh(weapon,flash_shape,Vector3(0,.025,-.86),Color("ffd978"),0,.8,5)
	flash.scale = Vector3(.7,.7,1.9)
	flash.visible = false
	flash_light = OmniLight3D.new()
	flash_light.position = flash.position
	flash_light.light_color = Color("ffbc53")
	flash_light.light_energy = 2
	flash_light.omni_range = 3
	flash_light.visible = false
	weapon.add_child(flash_light)

func _build_props() -> void:
	for kind in ["drink", "eat", "heal", "reload"]:
		var prop := Node3D.new()
		left_wing.add_child(prop)
		prop.position = Vector3(0,-.30,-.10)
		if kind in ["drink", "eat"]: prop.position.y = -.42
		prop.visible = false
		held_props[kind] = prop
		match kind:
			"drink":
				G.cylinder(prop,Vector3.ZERO,.06,.22,Color("699ba9"),.05,.25)
				G.cylinder(prop,Vector3(0,.125,0),.032,.045,Color("e3dbc3"))
				G.cylinder(prop,Vector3.ZERO,.061,.07,Color("d9dcc4"))
			"eat":
				G.cylinder(prop,Vector3.ZERO,.075,.12,Color("b9ad7e"),-1,.3)
				G.cylinder(prop,Vector3(0,.067,0),.068,.01,Color("846444"))
			"heal":
				G.cylinder(prop,Vector3.ZERO,.07,.11,Color("e4dfcc"))
				G.box(prop,Vector3(0,0,-.07),Vector3(.07,.022,.01),Color("b96651"))
				G.box(prop,Vector3(0,0,-.071),Vector3(.023,.07,.01),Color("b96651"))
			"reload":
				G.box(prop,Vector3.ZERO,Vector3(.095,.23,.15),Color("282e2c"),.5)

## NPCs opt into independent presentation updates. Players are advanced by Main.
func enable_idle(data: Dictionary) -> void:
	_idle_data = data.duplicate(true)
	set_process(true)

func _process(delta: float) -> void:
	if is_visible_in_tree(): update_actor(_idle_data, delta)

func update_actor(data: Dictionary, delta: float, local: bool = false) -> void:
	if not initialized: setup(base_tint, str(data.get("name", "DUCK")))
	delta = clampf(delta, 0, .1)
	_clock += delta
	var at: Vector2 = data.get("pos", Vector2.ZERO)
	# Main may supply an interpolated display copy. Collision remains in PlayerPhysics.
	position = Vector3(at.x, 0, at.y)
	var velocity: Vector2 = data.get("velocity", Vector2.ZERO)
	var aim: Vector2 = data.get("aim", Vector2.UP)
	if aim.length_squared() > .01:
		var yaw := atan2(-aim.x, -aim.y)
		rotation.y = lerp_angle(rotation.y, yaw, 1.0-exp(-delta*22)) if has_previous_pos else yaw
	local_ring.visible = local
	var kind := "rifle"
	if data.has("equipment"):
		var equipment: Dictionary = data.equipment
		helmet.visible = not equipment.get("helmet", {}).is_empty()
		backpack.visible = not equipment.get("backpack", {}).is_empty()
		armor.visible = not equipment.get("armor", {}).is_empty()
		kind = str(equipment.get("weapon", {}).get("kind", ""))
		weapon.visible = not kind.is_empty()
	rifle_mesh.visible = kind == "rifle"
	pistol_mesh.visible = kind == "pistol"
	flash.position.z = -.37 if kind == "pistol" else -.86
	flash.scale = Vector3(.65,.65,1.4) if kind == "pistol" else Vector3(1.0,1.0,2.4)
	flash_light.light_energy = 1.5 if kind == "pistol" else 3.5
	flash_light.omni_range = 2.2 if kind == "pistol" else 4.0
	flash_light.position = flash.position
	var shots := int(data.get("shots", 0))
	var fired := has_previous_pos and shots > previous_shots and weapon.visible
	if fired:
		flash_time = .065 if kind == "pistol" else .095
		_recoil = .65 if kind == "pistol" else 1.0
		_event_suppressed = int(data.get("anim_seq", 0))
	else:
		flash_time = maxf(0, flash_time-delta)
		_recoil *= exp(-delta*19)
	flash.visible = weapon.visible and flash_time > 0
	flash_light.visible = flash.visible
	_speed = velocity.length() if local else lerpf(_speed, velocity.length(), 1.0-exp(-delta*13))
	_run_blend = move_toward(_run_blend, 1.0 if data.get("sprint", false) and velocity.length() > .1 else 0.0, delta*6)
	if local and velocity.is_zero_approx(): _run_blend = 0.0
	_crouch_blend = move_toward(_crouch_blend, 1.0 if data.get("crouch", false) else 0.0, delta*6)
	_aim_blend = move_toward(_aim_blend, 1.0 if data.get("ads", false) and weapon.visible else 0.0, delta*9)
	_unarmed_blend = move_toward(_unarmed_blend, 0.0 if weapon.visible else 1.0, delta*7)
	var moving := clampf(_speed/.55, 0, 1)
	animation_state = "crouch_walk" if moving > .15 else "crouch_idle"
	if not data.get("crouch", false):
		animation_state = "run" if _run_blend > .5 else ("walk" if moving > .15 else "idle")
	_update_action(data, delta)
	var action_weight := 0.0
	if not action_state.is_empty():
		var duration: float = 1.6 if action_state == "reload" else _event_duration
		action_weight = minf(clampf(action_time/.10, 0, 1), clampf((duration-action_time)/.12, 0, 1))
		_visual_action = action_state
		_visual_action_time = action_time
	_visual_action_weight = move_toward(_visual_action_weight, action_weight, delta*12)
	var tempo := lerpf(1.0, clampf(_speed / (1.78 if _crouch_blend > .5 else 3.7), .65, 1.45), moving)
	motion.advance(delta, moving, _run_blend*moving, _crouch_blend, _aim_blend, tempo, _visual_action, _visual_action_time, _visual_action_weight)
	_apply_direction(velocity, moving, _visual_action_weight)
	_update_props(action_weight, kind)
	var blink := maxf(0, 1.0-absf(fmod(_clock+float(nameplate.text.hash()%100)*.01, 4.3)-.12)/.085)
	for i in range(_eyes.size()): _eyes[i].scale.y = (.106 if i%2 == 0 else .025) * (1-blink*.94)
	previous_shots = shots
	has_previous_pos = true

func _update_action(data: Dictionary, delta: float) -> void:
	var seq := int(data.get("anim_seq", 0))
	var incoming := float(data.get("anim_time", 0))
	if seq != _event_seq:
		_event_seq = seq
		_event_time = incoming
		_event_action = str(data.get("anim_action", ""))
		_event_duration = float(data.get("anim_duration", 0))
	else:
		# Advance between snapshots, never replay the same event from zero.
		_event_time = maxf(_event_time+delta, incoming)
	action_state = ""
	action_time = 0
	if _event_time < _event_duration and seq != _event_suppressed and _event_action in ["drink", "eat", "heal", "pickup", "equip", "interact"]:
		action_state = _event_action
		action_time = _event_time
	var reloading: bool = data.get("reloading", false) and weapon.visible
	if reloading:
		var observed := clampf(float(data.get("reload_progress", 0)), 0, 1)*1.6
		_reload_time = maxf(_reload_time+delta, observed) if _was_reloading else observed
		action_state = "reload"
		action_time = minf(_reload_time, 1.599)
	else: _reload_time = 0
	_was_reloading = reloading

func _apply_direction(velocity: Vector2, moving: float, action_weight: float) -> void:
	var local_move := velocity.rotated(rotation.y).normalized()
	# Authored forward strides are redirected into aim-relative forward/back/strafe.
	for bone in ["FootL", "FootR"]:
		var index := skeleton.find_bone(bone)
		var rest := skeleton.get_bone_rest(index).origin
		var pose := skeleton.get_bone_pose_position(index)
		var stride := -(pose.z-rest.z)
		pose.x = rest.x+local_move.x*stride
		pose.z = rest.z+local_move.y*stride
		skeleton.set_bone_pose_position(index, pose)
		var rotation_pose := skeleton.get_bone_pose_rotation(index).get_euler()
		rotation_pose.x *= -local_move.y if moving > .05 else 1.0
		rotation_pose.z += local_move.x*rotation_pose.x*.35
		rotation_pose.y += clampf(local_move.x*.28, -.28, .28)*moving
		skeleton.set_bone_pose_rotation(index, Quaternion.from_euler(rotation_pose))
	var hip := skeleton.find_bone("Hips")
	var hip_position := skeleton.get_bone_pose_position(hip)
	hip_position.y -= .26*_crouch_blend*action_weight
	skeleton.set_bone_pose_position(hip, hip_position)
	# Aiming and recoil stay above the locomotion layer.
	_rotate("Spine", Vector3(-.075*_recoil, 0, -local_move.x*.055*moving))
	_rotate("Head", Vector3(.035*_recoil, 0, local_move.x*.03*moving))
	_rotate("Gun", Vector3(.15*_recoil, 0, -.035*_recoil))
	var gun := skeleton.find_bone("Gun")
	skeleton.set_bone_pose_position(gun, skeleton.get_bone_pose_position(gun)+Vector3(0, 0, .09*_recoil))
	var relaxed := _unarmed_blend*(1-action_weight)
	for bone in ["WingL", "WingR"]:
		var index := skeleton.find_bone(bone)
		skeleton.set_bone_pose_rotation(index, skeleton.get_bone_pose_rotation(index).slerp(Quaternion.IDENTITY, relaxed))
		skeleton.set_bone_pose_position(index, skeleton.get_bone_pose_position(index).lerp(skeleton.get_bone_rest(index).origin, relaxed))

func _rotate(bone: String, offset: Vector3) -> void:
	var index := skeleton.find_bone(bone)
	skeleton.set_bone_pose_rotation(index, skeleton.get_bone_pose_rotation(index)*Quaternion.from_euler(offset))

func _update_props(action_weight: float, kind: String) -> void:
	for prop in held_props.values(): prop.visible = false
	magazine.visible = true
	if action_state == "reload" and action_weight > .05:
		var exchanging := action_time > .40 and action_time < 1.04
		magazine.visible = not exchanging
		held_props.reload.visible = exchanging and kind == "rifle"
	elif held_props.has(action_state):
		held_props[action_state].visible = action_weight > .25
		if action_state in ["drink", "eat"]:
			var head_pose := skeleton.get_bone_global_pose(skeleton.find_bone("Head"))
			var wing_pose := skeleton.get_bone_global_pose(skeleton.find_bone("WingL"))
			var mouth := head_pose * Vector3(0,-.14,-.55)
			var prop: Node3D = held_props[action_state]
			var direction := wing_pose.basis.inverse() * (mouth-wing_pose*prop.position)
			if direction.length_squared() > .0001:
				prop.quaternion = Quaternion(Vector3.UP, direction.normalized())
