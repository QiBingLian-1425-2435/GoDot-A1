extends Node3D
## Local view of host-owned bodies. The observer shares only the teammate's view.
const Actor = preload("res://features/player/base_actor.gd")
var bodies: Dictionary = {}

func update(ctx) -> void:
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
		actor.nameplate.text = str(body.container_name)+"  [E] 搜索  [F] 救援"
		actor.visible = ctx.in_game and not ctx.world_loading and ctx.vision.can_see(Vector3(body.pos.x,float(body.height)+.4,body.pos.y))
	for id in ctx.actors:
		if not ctx.session.model.Souls.alive(ctx.session.model.state.players.get(id,{})): ctx.actors[id].visible=false
