extends Node3D
## Self-contained rigged visual. Animation never moves the CharacterBody3D.
const BODY = preload("res://assets/characters/kaykit/Rogue.glb")
const HOODED_BODY = preload("res://assets/characters/kaykit/Rogue_Hooded.glb")
const TOON = preload("toon.gdshader")
const OUTLINE = preload("outline.gdshader")
const ATLAS = preload("res://assets/characters/kaykit/rogue_texture.png")
@export var hooded: bool = false
@export var toon_enabled: bool = true
var animation_tree: AnimationTree
var skeleton: Skeleton3D
var current_action: StringName = &""
var current_action_sequence: int = -1
var pose_state: StringName = &"active"
var _mount: Node3D
var _asset: Node3D
var _player: AnimationPlayer
var _action_node: AnimationNodeAnimation
var _accent := Color.WHITE
var _toon_material: ShaderMaterial
var _plain_material: StandardMaterial3D
var _meshes: Array[MeshInstance3D] = []
var _external_action: StringName = &""
var _external_sequence: int = -1
var _remaining: float = 0.0
var _continuous_action: bool = false
var _rescue_blend: float = 0.0
var _shot: AnimationNodeOneShot

func _ready() -> void:
	_build_asset()

func _build_asset() -> void:
	_mount = Node3D.new()
	_mount.name = "AssetMount"
	# Upstream is +Z forward and 2.19m high. Correct only the visual, never the motor.
	_mount.rotation.y = PI
	_mount.scale = Vector3.ONE * 0.79
	add_child(_mount)
	_asset = (HOODED_BODY if hooded else BODY).instantiate()
	_mount.add_child(_asset)
	skeleton = _asset.find_child("Skeleton3D", true, false)
	_player = _asset.find_child("AnimationPlayer", true, false)
	# Own the library and its clips: loop settings must never mutate another actor.
	for library_name in _player.get_animation_library_list():
		var original = _player.get_animation_library(library_name)
		var library := AnimationLibrary.new()
		for clip_name in original.get_animation_list():
			var clip: Animation = original.get_animation(clip_name).duplicate(true)
			if clip_name in ["Idle", "Walking_A", "Walking_Backwards", "Running_A",
				"Running_Strafe_Left", "Running_Strafe_Right", "Use_Item", "Interact", "Lie_Idle", "Sit_Chair_Idle"]:
				clip.loop_mode = Animation.LOOP_LINEAR
			# Strip horizontal root displacement, retaining the pose's vertical motion.
			for track in clip.get_track_count():
				if clip.track_get_type(track) == Animation.TYPE_POSITION_3D and str(clip.track_get_path(track)).ends_with(":root"):
					for key in clip.track_get_key_count(track):
						var value: Vector3 = clip.track_get_key_value(track, key)
						value.x = 0.0
						value.z = 0.0
						clip.track_set_key_value(track, key, value)
			library.add_animation(clip_name, clip)
		_player.remove_animation_library(library_name)
		_player.add_animation_library(library_name, library)
	for mesh: MeshInstance3D in _asset.find_children("*", "MeshInstance3D", true, false):
		# Imported optional weapons are demonstration attachments, not game equipment.
		if mesh.name in ["Knife_Offhand", "1H_Crossbow", "2H_Crossbow", "Knife", "Throwable"]:
			mesh.hide()
		else:
			_meshes.append(mesh)
	_build_materials()
	_build_animation_tree()

func _animation(clip: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	return node

func _space(running: bool) -> AnimationNodeBlendSpace2D:
	var space := AnimationNodeBlendSpace2D.new()
	space.min_space = Vector2(-1, -1)
	space.max_space = Vector2(1, 1)
	space.add_blend_point(_animation(&"Idle"), Vector2.ZERO)
	space.add_blend_point(_animation(&"Running_A" if running else &"Walking_A"), Vector2(0, -1))
	space.add_blend_point(_animation(&"Walking_Backwards"), Vector2(0, 1))
	space.add_blend_point(_animation(&"Running_Strafe_Left"), Vector2(-1, 0))
	space.add_blend_point(_animation(&"Running_Strafe_Right"), Vector2(1, 0))
	return space

func _build_animation_tree() -> void:
	animation_tree = AnimationTree.new()
	animation_tree.name = "PoseTree"
	_asset.add_child(animation_tree)
	animation_tree.anim_player = animation_tree.get_path_to(_player)
	var graph := AnimationNodeBlendTree.new()
	graph.add_node(&"walk", _space(false))
	graph.add_node(&"run", _space(true))
	graph.add_node(&"mode", AnimationNodeBlend2.new())
	graph.connect_node(&"mode", 0, &"walk")
	graph.connect_node(&"mode", 1, &"run")
	graph.add_node(&"gait_rate", AnimationNodeTimeScale.new())
	graph.connect_node(&"gait_rate", 0, &"mode")
	graph.add_node(&"kneel", _animation(&"Sit_Chair_Idle"))
	graph.add_node(&"rescue_base", AnimationNodeBlend2.new())
	graph.connect_node(&"rescue_base", 0, &"gait_rate")
	graph.connect_node(&"rescue_base", 1, &"kneel")
	_action_node = _animation(&"Interact")
	graph.add_node(&"action", _action_node)
	graph.add_node(&"action_seek", AnimationNodeTimeSeek.new())
	graph.connect_node(&"action_seek", 0, &"action")
	graph.add_node(&"action_rate", AnimationNodeTimeScale.new())
	graph.connect_node(&"action_rate", 0, &"action_seek")
	_shot = AnimationNodeOneShot.new()
	_shot.fadein_time = 0.10
	_shot.fadeout_time = 0.12
	# Upper-body filter for rescue; full-body actions disable this filter.
	for bone in ["spine", "chest", "head", "upperarm.l", "lowerarm.l", "wrist.l",
		"hand.l", "handslot.l", "upperarm.r", "lowerarm.r", "wrist.r", "hand.r", "handslot.r"]:
		_shot.set_filter_path(NodePath("Rig/Skeleton3D:" + bone), true)
	graph.add_node(&"gesture", _shot)
	graph.connect_node(&"gesture", 0, &"rescue_base")
	graph.connect_node(&"gesture", 1, &"action_rate")
	graph.connect_node(&"output", 0, &"gesture")
	animation_tree.tree_root = graph
	animation_tree.active = true

func _build_materials() -> void:
	_toon_material = ShaderMaterial.new()
	_toon_material.shader = TOON
	_toon_material.set_shader_parameter("albedo_texture", ATLAS)
	_toon_material.set_shader_parameter("accent", _accent)
	var outline := ShaderMaterial.new()
	outline.shader = OUTLINE
	_toon_material.next_pass = outline
	_plain_material = StandardMaterial3D.new()
	_plain_material.albedo_texture = ATLAS
	_plain_material.roughness = 0.9
	set_toon_enabled(toon_enabled)

func set_accent(color: Color) -> void:
	_accent = color
	if _toon_material: _toon_material.set_shader_parameter("accent", color)

func set_toon_enabled(enabled: bool) -> void:
	toon_enabled = enabled
	for mesh in _meshes:
		mesh.material_override = _toon_material if enabled else _plain_material

func set_action_state(kind: StringName, sequence: int, remaining: float) -> void:
	_external_action = kind
	_external_sequence = sequence
	_remaining = maxf(0.0, remaining)

func update_pose(local_velocity: Vector3, mode: StringName, state: StringName, delta: float) -> void:
	if not animation_tree: return
	pose_state = state
	var speed := local_velocity.length()
	var direction := Vector2(local_velocity.x, local_velocity.z)
	if direction.length() > 0.01:
		direction = direction.normalized() * clampf(speed / 1.0, 0.0, 1.0)
	animation_tree.set("parameters/walk/blend_position", direction)
	animation_tree.set("parameters/run/blend_position", direction)
	animation_tree.set("parameters/mode/blend_amount", 1.0 if mode == &"run" else 0.0)
	var reference_speed := 5.1 if mode == &"run" else 3.1
	animation_tree.set("parameters/gait_rate/scale", clampf(speed / reference_speed, 0.35, 1.5))
	_mount.rotation.x = lerp_angle(_mount.rotation.x, -0.14 if mode == &"sneak" else 0.0, 1.0 - exp(-delta * 12.0))
	var wanted := _external_action if _remaining > 0.0 else &""
	var serial := _external_sequence
	if state == &"downed":
		wanted = &"downed"
		serial = -2
	elif state == &"hidden":
		wanted = &""
	if wanted != current_action or (serial != current_action_sequence and wanted != &""):
		_play_action(wanted, serial)
	_rescue_blend = move_toward(_rescue_blend, 1.0 if wanted == &"rescue" else 0.0, delta * 9.0)
	animation_tree.set("parameters/rescue_base/blend_amount", _rescue_blend)
	_remaining = maxf(0.0, _remaining - delta)

func _play_action(kind: StringName, sequence: int) -> void:
	current_action = kind
	current_action_sequence = sequence
	if kind == &"":
		animation_tree.set("parameters/gesture/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
		return
	var clips := {&"pickup": &"PickUp", &"drop": &"PickUp", &"door": &"Interact",
		&"rescue": &"Interact", &"extract": &"Use_Item", &"hit": &"Hit_A",
		&"get_up": &"Lie_StandUp", &"downed": &"Lie_Idle"}
	var clip: StringName = clips.get(kind, &"Interact")
	if not _player.has_animation(clip): return
	_action_node.animation = clip
	_shot.filter_enabled = kind == &"rescue"
	_continuous_action = kind in [&"rescue", &"extract", &"downed"]
	var rate := 1.0
	var seek := 0.0
	if not _continuous_action and _remaining > 0.0:
		var durations := {&"pickup": 0.85, &"drop": 0.65, &"door": 0.8, &"hit": 0.32, &"get_up": 1.2}
		var duration: float = durations.get(kind, _remaining)
		rate = _player.get_animation(clip).length / duration
		seek = maxf(0.0, duration - _remaining) * rate
	animation_tree.set("parameters/action_rate/scale", rate)
	animation_tree.set("parameters/action_seek/seek_request", seek)
	animation_tree.set("parameters/gesture/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
