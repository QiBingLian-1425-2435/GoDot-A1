extends Node3D

var sprite: Sprite3D
var marker: MeshInstance3D
var tag: Label3D
var health_bar: MeshInstance3D
var base_color := Color("7dc5b7")
var last_pos := Vector3.ZERO
var phase := 0.0
var hit_flash := 0.0
var is_monster := false
var previous_hp := 100.0
var model: Node3D
var facing_yaw := 0.0
var initialized := false
var display_velocity := Vector3.ZERO
var previous_state := "alive"
var previous_bag_count := 0
var action_serial := 0
var was_extracting := false

func setup(texture_path: String, tint: Color, title: String, monster := false) -> void:
	is_monster = monster
	base_color = tint
	var shadow := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.36 if not monster else 0.48
	disc.bottom_radius = disc.top_radius
	disc.height = 0.012
	shadow.mesh = disc
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.025, 0.035, 0.045, 0.32)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow.material_override = sm
	shadow.position.y = 0.095
	add_child(shadow)
	marker = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.33
	ring.outer_radius = 0.37
	ring.rings = 32
	ring.ring_segments = 8
	marker.mesh = ring
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = tint * 0.4
	marker.material_override = mat
	marker.position.y = 0.105
	add_child(marker)
	if not monster:
		model = preload("res://features/player/visuals/rigged_survivor.tscn").instantiate()
		model.hooded = texture_path.ends_with("companion.png")
		add_child(model)
		model.set_accent(tint)
	else:
		_create_sprite(texture_path, monster)
	_create_tag(title)
	last_pos = position

func _create_sprite(texture_path: String, monster: bool) -> void:
	sprite = Sprite3D.new()
	if ResourceLoader.exists(texture_path):
		sprite.texture = load(texture_path)
	else:
		var gradient := GradientTexture2D.new()
		gradient.width = 32
		gradient.height = 48
		sprite.texture = gradient
	var tex_h := float(sprite.texture.get_height())
	sprite.pixel_size = (2.15 if monster else 2.35) / tex_h
	sprite.position.y = 1.02 if monster else 1.08
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = 0.22
	sprite.shaded = false
	sprite.no_depth_test = false
	add_child(sprite)

func _create_tag(title: String) -> void:
	tag = Label3D.new()
	tag.text = title
	tag.font_size = 22
	tag.pixel_size = 0.014
	tag.position.y = 2.58
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color("f3e6cb")
	tag.outline_modulate = Color("17282c")
	tag.outline_size = 6
	add_child(tag)
	last_pos = position

func update_actor(data: Dictionary, delta: float, local := false) -> void:
	var p: Vector2 = data.get("pos", Vector2.ZERO)
	var target := Vector3(p.x, 0.05, p.y)
	if not initialized:
		position = target
		last_pos = target
		initialized = true
	var speed := position.distance_to(target)
	var before := position
	position = position.lerp(target, minf(1.0, delta * 16.0))
	display_velocity = (position - before) / maxf(delta, 0.0001)
	phase += delta * (11.0 if speed > 0.035 else 2.0)
	var state: String = data.get("status", "alive")
	if model != null:
		_update_model(data, state, delta, local, target)
		return
	var bob := absf(sin(phase)) * 0.095 if speed > 0.035 else sin(phase) * 0.025
	if is_monster:
		bob = sin(phase * 0.7) * 0.13
	sprite.position.y = (1.02 if is_monster else 1.08) + bob
	if target.x < last_pos.x - 0.01:
		sprite.flip_h = true
	elif target.x > last_pos.x + 0.01:
		sprite.flip_h = false
	sprite.rotation.z = sin(phase) * 0.035 if speed > 0.035 else 0.0
	sprite.modulate = Color.WHITE
	if state == "downed":
		sprite.rotation.z = -1.25
		sprite.position.y = 0.48
		sprite.modulate = Color("c4a5a2")
	elif state == "dead":
		sprite.modulate = Color(0.55, 0.85, 0.94, 0.24)
		sprite.position.y = 1.35 + sin(phase) * 0.15
	elif state == "extracted":
		visible = false
		return
	var hp: float = data.get("hp", 100.0)
	if hp < previous_hp:
		hit_flash = 0.22
	previous_hp = hp
	hit_flash = maxf(0, hit_flash - delta)
	if hit_flash > 0:
		sprite.modulate = Color(1.8, 0.55, 0.4)
	marker.visible = state != "dead"
	marker.scale = Vector3.ONE * (1.15 if local else 0.86)
	if state == "downed":
		tag.text = data.get("name", "") + " · 等待救援"
		tag.modulate = Color("f3a582")
	elif is_monster:
		tag.text = "追逐中" if data.get("mode", "patrol") == "chase" else "巡夜者"
		tag.modulate = Color("f3a582") if data.get("mode", "patrol") == "chase" else Color("a5a2c7")
	else:
		tag.text = data.get("name", "旅人") + (" · 你" if local else "")
		tag.modulate = base_color
	last_pos = target

func _update_model(data: Dictionary, state: String, delta: float, local: bool, target: Vector3) -> void:
	var look: Vector2 = data.get("look", Vector2.RIGHT)
	if look.length_squared() > 0.001:
		facing_yaw = rotate_toward(facing_yaw, atan2(-look.x, -look.y), delta * 12.0)
	model.rotation.y = facing_yaw
	var motion := display_velocity
	# Snapshot interpolation drives display only; no second motor or collision body.
	if not data.get("moving", false) or state != "alive":
		motion = Vector3.ZERO
	motion = motion.limit_length(3.5)
	var hp: float = data.get("hp", 100.0)
	var bag_count: int = data.get("bag", []).size()
	var extracting: bool = float(data.get("extract_progress", 0.0)) > 0.0
	var action: StringName = &""
	var duration := 0.0
	if previous_state == "downed" and state == "alive":
		action = &"get_up"
		duration = 1.2
	elif hp < previous_hp and state == "alive":
		action = &"hit"
		duration = 0.32
	elif bag_count != previous_bag_count and state == "alive":
		action = &"pickup" if bag_count > previous_bag_count else &"drop"
		duration = 0.85 if bag_count > previous_bag_count else 0.65
	elif extracting and not was_extracting:
		action = &"extract"
		duration = 4.0
	elif was_extracting and not extracting:
		model.set_action_state(&"", action_serial, 0.0)
	if action != &"":
		action_serial += 1
		model.set_action_state(action, action_serial, duration)
	previous_hp = hp
	previous_state = state
	previous_bag_count = bag_count
	was_extracting = extracting
	model.update_pose(Basis(Vector3.UP, -facing_yaw) * motion, &"walk",
		&"downed" if state == "downed" else &"active", delta)
	marker.visible = state not in ["dead", "extracted"]
	marker.scale = Vector3.ONE * (1.15 if local else 0.86)
	tag.text = data.get("name", "旅人") + (" · 等待救援" if state == "downed" else (" · 你" if local else ""))
	tag.modulate = Color("f3a582") if state == "downed" else base_color
	last_pos = target
