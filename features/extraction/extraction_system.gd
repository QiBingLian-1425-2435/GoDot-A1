extends RefCounted
## Authority-only subsystem. ctx is the match; no scene/UI dependencies.



func _extract(ctx, p: Dictionary) -> void:
	if p.status != "alive":
		return
	p.status = "extracted"
	p.extract_progress = ctx.EXTRACT_SECONDS
	p.result_value = ctx.bag_value(p)
	p.banked += p.result_value
	ctx.state.total_banked += p.result_value
	ctx.state.round_value += p.result_value
	ctx._inputs.erase(p.id)
	ctx._detach(p.id)
	ctx._clear_requests(p.id)
	ctx._event("%s 安全撤离，带回 %d 金币" % [p.name, p.result_value])

func _check_end(ctx) -> void:
	if ctx.state.phase != "raid":
		return
	for p in ctx.state.players.values():
		if p.status == "alive" or p.status == "downed":
			return
	_finish_round(ctx)

func _finish_round(ctx) -> void:
	if ctx.state.phase != "raid":
		return
	ctx.state.phase = "results"
	ctx._inputs.clear()
	for p in ctx.state.players.values():
		ctx._detach(p.id)
		p.request_from = 0
	ctx._event("本次夜探结束 · 团队带回 %d 金币" % ctx.state.round_value)
