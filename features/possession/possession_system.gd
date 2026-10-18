extends RefCounted
## Authority-only subsystem. ctx is the match; no scene/UI dependencies.



func _request_possession(ctx, p: Dictionary, target_id: int) -> void:
	if p.status != "dead" or p.possessing != 0 or not ctx.state.players.has(target_id):
		return
	var target: Dictionary = ctx.state.players[target_id]
	if target.status != "alive" or target.request_from != 0:
		return
	for other in ctx.state.players.values():
		if int(other.possessing) == target_id:
			return
	_clear_requests(ctx, p.id)
	target.request_from = p.id
	ctx._event("%s 请求共享 %s 的视角" % [p.name, target.name])
	if target.bot:
		_accept_possession(ctx, target)

func _accept_possession(ctx, target: Dictionary) -> void:
	var source_id = int(target.request_from)
	if target.status != "alive" or source_id == 0 or not ctx.state.players.has(source_id):
		return
	var source: Dictionary = ctx.state.players[source_id]
	if source.status != "dead" or source.possessing != 0:
		target.request_from = 0
		return
	for other in ctx.state.players.values():
		if int(other.possessing) == int(target.id):
			return
	source.possessing = target.id
	target.request_from = 0
	ctx._event("%s 正与 %s 共享视角，双方均可解除" % [source.name, target.name])

func _detach(ctx, id: int) -> void:
	var detached = false
	for p in ctx.state.players.values():
		if (p.id == id and p.possessing != 0) or p.possessing == id:
			p.possessing = 0
			detached = true
	_clear_requests(ctx, id)
	if detached:
		ctx._event("视角共享已解除")

func _clear_requests(ctx, id: int) -> void:
	for p in ctx.state.players.values():
		if p.id == id or p.request_from == id:
			p.request_from = 0
