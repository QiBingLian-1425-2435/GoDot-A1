extends RefCounted
## A per-character graph. Animation resources are read-only; parameters never leak to peers.
const LIBRARY = preload("res://features/player/animation/duck_animations.tres")
const UPPER := ["Spine", "Head", "WingL", "WingR", "Gun", "Pack"]
var tree: AnimationTree
var action_node: AnimationNodeAnimation

func build(actor: Node3D) -> void:
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	actor.add_child(player)
	player.add_animation_library("", LIBRARY)
	var graph := AnimationNodeBlendTree.new()
	var standing := AnimationNodeBlendSpace1D.new()
	standing.min_space = 0.0; standing.max_space = 2.0
	standing.add_blend_point(_clip("idle"), 0.0)
	standing.add_blend_point(_clip("walk"), 1.0)
	standing.add_blend_point(_clip("run"), 2.0)
	var crouching := AnimationNodeBlendSpace1D.new()
	crouching.add_blend_point(_clip("crouch_idle"), 0.0)
	crouching.add_blend_point(_clip("crouch_walk"), 1.0)
	graph.add_node("Standing", standing)
	graph.add_node("Crouching", crouching)
	graph.add_node("Crouch", AnimationNodeBlend2.new())
	graph.connect_node("Crouch", 0, "Standing")
	graph.connect_node("Crouch", 1, "Crouching")
	graph.add_node("Tempo", AnimationNodeTimeScale.new())
	graph.connect_node("Tempo", 0, "Crouch")
	graph.add_node("AimPose", _clip("aim"))
	var aim := AnimationNodeBlend2.new()
	_filter(aim, UPPER)
	graph.add_node("Aim", aim)
	graph.connect_node("Aim", 0, "Tempo")
	graph.connect_node("Aim", 1, "AimPose")
	action_node = _clip("reload")
	graph.add_node("ActionClip", action_node)
	graph.add_node("ActionSeek", AnimationNodeTimeSeek.new())
	graph.connect_node("ActionSeek", 0, "ActionClip")
	var action := AnimationNodeBlend2.new()
	_filter(action, UPPER + ["Hips"])
	graph.add_node("Action", action)
	graph.connect_node("Action", 0, "Aim")
	graph.connect_node("Action", 1, "ActionSeek")
	graph.connect_node("output", 0, "Action")
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	actor.add_child(tree)
	tree.anim_player = NodePath("../AnimationPlayer")
	tree.tree_root = graph
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true

func advance(delta: float, move: float, run: float, crouch: float, aim: float, tempo: float, action: String, time: float, weight: float) -> void:
	tree.set("parameters/Standing/blend_position", move + run)
	tree.set("parameters/Crouching/blend_position", move)
	tree.set("parameters/Crouch/blend_amount", crouch)
	tree.set("parameters/Tempo/scale", tempo)
	tree.set("parameters/Aim/blend_amount", aim)
	if not action.is_empty():
		action_node.animation = action
		tree.set("parameters/ActionSeek/seek_request", time)
	tree.set("parameters/Action/blend_amount", weight)
	tree.advance(delta)

func _clip(value: String) -> AnimationNodeAnimation:
	var result := AnimationNodeAnimation.new()
	result.animation = value
	return result

func _filter(node: AnimationNode, bones: Array) -> void:
	node.filter_enabled = true
	for bone in bones:
		node.set_filter_path(NodePath("Rig/Skeleton3D:" + str(bone)), true)
