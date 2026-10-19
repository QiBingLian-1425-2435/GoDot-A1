extends SceneTree
const Model = preload("res://features/base/base_model.gd")
const Local = preload("res://features/player/local_movement.gd")
const Actor = preload("res://features/player/base_actor.gd")
const Session = preload("res://app/network/session.gd")
const DT := 1.0/60.0
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("LOCAL MOVEMENT FAIL: " + label)

func run() -> void:
	test_latency(12,false)
	test_latency(15,true)
	test_isolation_and_reset()
	test_rest_correction()
	print("LOCAL_MOVEMENT ",checks," checks, ",failures," failures")
	quit(0 if failures == 0 else 1)

func test_latency(delay: int, drop_stop: bool) -> void:
	var host = Model.new(); host.add_player(2,"fixture")
	host.bounds = Rect2(-100,-100,200,200)
	var predictor = Local.new()
	predictor.solver = host.solve_motion.bind(0)
	var observed: Dictionary = host.state.players[2].duplicate(true)
	predictor.confirm(observed)
	var outbound: Array = []
	var inbound: Array = []
	var seq := 0
	var last_direction := Vector2.ZERO
	var stopped_at := Vector2.ZERO
	var stop_drift := 0.0
	var max_error := 0.0
	var stop_replayed := false
	var reverse_replayed := false
	# 30 seconds of repeated direction changes, including transitions shorter than RTT.
	for frame in range(1800):
		var cycle := frame % 240
		var direction := Vector2.ZERO
		if cycle >= 30 and cycle < 90: direction = Vector2.RIGHT
		if cycle >= 150 and cycle < 160: direction = Vector2.UP
		if cycle >= 160 and cycle < 200: direction = Vector2.DOWN
		var input := {"direction":direction,"aim":Vector2.UP,"sprint":false,"crouch":false,"ads":false}
		predictor.set_input(input)
		var edge := direction != last_direction
		if frame % 3 == 0 or edge:
			seq += 1
			predictor.note_sent(seq,edge)
			if not (drop_stop and cycle == 90):
				outbound.append({"due":frame+delay,"seq":seq,"input":input.duplicate()})
		last_direction = direction
		while not outbound.is_empty() and outbound.front().due <= frame:
			var packet: Dictionary = outbound.pop_front()
			var p: Dictionary = host.state.players[2]
			p.input_seq = packet.seq; p.input_origin = p.pos; p.input_stamina = p.stamina
			p.input_weight = p.weight; p.input_max_weight = p.max_weight
			host.command(2,"move",packet.input)
		host.tick(DT)
		if frame % 3 == 0: inbound.append({"due":frame+delay,"pose":host.state.players[2].duplicate(true)})
		while not inbound.is_empty() and inbound.front().due <= frame:
			observed = inbound.pop_front().pose
			predictor.confirm(observed)
		var original := observed.duplicate(true)
		predictor.advance(DT,observed)
		var display: Dictionary = predictor.sample_player(observed)
		if observed != original: failures += 1; push_error("LOCAL MOVEMENT FAIL: modified confirmed data")
		if cycle == 30: check(display.velocity.x > 3.6,"first physics step starts before ACK (%d frames one-way)" % delay)
		if cycle == 90: stopped_at = display.pos
		if cycle >= 90 and cycle < 150:
			stop_drift = maxf(stop_drift,Vector2(display.pos).distance_to(stopped_at))
			if not Vector2(display.velocity).is_zero_approx(): stop_replayed = true
		if cycle >= 160 and cycle < 200 and display.velocity.y < 0: reverse_replayed = true
		if cycle == 149:
			max_error = maxf(max_error,Vector2(display.pos).distance_to(host.state.players[2].pos))
	check(not stop_replayed,"no old ACK revives walking after release")
	check(not reverse_replayed,"old ACK cannot reverse the latest direction")
	check(stop_drift < (.22 if drop_stop else .08),"bounded correction after release: %.4f" % stop_drift)
	check(max_error < .015,"stationary prediction converges without accumulating error: %.5f" % max_error)
	check(predictor._history.size() <= 122 and predictor._sent.size() <= 45,"history remains bounded after 30 seconds")
	print("LOCAL_LATENCY one_way_frames=",delay," lost_stop=",drop_stop," max_stop_drift=",stop_drift," settled_error=",max_error)

func test_isolation_and_reset() -> void:
	var model = Model.new(); model.add_player(1,"fixture")
	var original: Dictionary = model.state.duplicate(true)
	var prediction = Local.new(); prediction.solver = model.solve_motion.bind(0)
	var p: Dictionary = model.state.players[1]
	prediction.confirm(p)
	prediction.set_input({"direction":Vector2.RIGHT,"aim":Vector2.RIGHT,"sprint":true})
	prediction.note_sent(1,true)
	for i in range(12): prediction.advance(DT,p)
	check(model.state == original,"prediction cannot change authority, inventory, ammo, timers or targets")
	var actor = Actor.new(); root.add_child(actor)
	actor.update_actor(prediction.sample_player(p),DT,true)
	check(actor.animation_state in ["walk","run"],"local actor follows predicted movement")
	prediction.set_input({"direction":Vector2.ZERO,"aim":Vector2.RIGHT})
	prediction.note_sent(2,true)
	prediction.advance(DT,p)
	actor.update_actor(prediction.sample_player(p),DT,true)
	check(actor.animation_state == "idle" and actor._speed == 0 and actor._run_blend == 0,"local legs stop on the first rendered zero-input frame")
	for i in range(90):
		prediction.set_input({"direction":Vector2.RIGHT})
		prediction.advance(DT,p)
	check(prediction.sample_player(p).velocity == Vector2.ZERO,"outbound outage stops unconfirmed prediction after its bound")
	prediction.clear()
	check(prediction._history.is_empty() and prediction._sent.is_empty() and prediction._state.is_empty(),"exit clears pending input, anchors and correction")
	var next := p.duplicate(true); next.pos = Vector2(-8,5)
	prediction.confirm(next)
	check(prediction.sample_player(next).pos == next.pos,"new session spawns without replaying previous inputs")
	prediction.note_sent(2,false)
	prediction.note_sent(3,true)
	var stale := next.duplicate(true)
	stale.input_seq = 2; stale.input_origin = next.pos
	for i in range(150):
		prediction.set_input({"direction":Vector2.RIGHT})
		prediction.confirm(stale)
		prediction.advance(DT,next)
	check(prediction.sample_player(next).velocity == Vector2.ZERO,"repeated ACK older than the input barrier cannot keep an outbound outage alive")
	var session = Session.new()
	session._last_sent_move = {"direction":Vector2(.5812382,.8137335),"sprint":false,"crouch":false,"ads":false}
	var noisy: Dictionary = session._last_sent_move.duplicate()
	noisy.direction += Vector2(.0000001,-.0000001)
	check(not session._is_movement_edge(noisy),"camera rounding noise cannot create a new input barrier")
	noisy.direction = Vector2.ZERO
	check(session._is_movement_edge(noisy),"actual release still bypasses the network send throttle")
	session.free()
	actor.free()

func test_rest_correction() -> void:
	var model = Model.new(); model.add_player(1,"rest")
	var p: Dictionary = model.state.players[1].duplicate(true)
	p.pos = Vector2.ZERO
	var prediction = Local.new(); prediction.solver = model.solve_motion.bind(0)
	prediction.confirm(p)
	prediction.set_input({"direction":Vector2.ZERO})
	prediction.note_sent(1,true)
	p.input_seq = 1; p.input_origin = Vector2(-.1,0); p.pos = p.input_origin
	prediction.confirm(p)
	for i in range(20): prediction.advance(DT,p)
	check(Vector2(prediction._state.pos).distance_to(p.pos) < .001,"small resting correction still fixes logical prediction immediately")
	check(prediction.sample_player(p).pos.is_equal_approx(Vector2.ZERO),"small delayed confirmation cannot move a resting display")
	var previous: Vector2 = prediction.sample_player(p).pos
	prediction.set_input({"direction":Vector2.RIGHT,"crouch":true,"ads":true})
	prediction.advance(DT,p)
	check(prediction.sample_player(p).pos.x > previous.x,"resuming slowly cannot move backwards while releasing held visual error")
	for i in range(25): prediction.advance(DT,p)
	check(prediction._offset.length() < .002,"held small correction clears during subsequent actual movement")
	# A correction that began while walking can have a small remainder at release.
	prediction._offset = Vector2(.08,0); prediction._settling = true
	prediction.set_input({"direction":Vector2.ZERO})
	prediction.advance(DT,p)
	var released: Vector2 = prediction.sample_player(p).pos
	for i in range(10): prediction.advance(DT,p)
	check(prediction.sample_player(p).pos.distance_to(released) < .001,"release holds the small remainder of a previously moving correction")
	# A host correction received after the player is already idle must still finish.
	prediction._offset = Vector2(.3,0); prediction._settling = true
	for i in range(20):
		prediction.set_input({"direction":Vector2.ZERO})
		prediction.advance(DT,p)
	check(prediction._offset.length() < .001,"repeated zero input cannot freeze a large host correction")
