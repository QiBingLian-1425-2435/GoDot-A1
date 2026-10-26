extends RefCounted
## Host positions decide audibility; voice never enters persistent game state.
const RANGE := 20.0
const MAX_PACKET := 8192
const RATE := 16000
const Souls = preload("res://features/rescue/soul_rules.gd")
static func can_speak(players: Dictionary, id: int) -> bool:
	return Souls.alive(players.get(id,{})) or Souls.observer_id(players,id)!=id

static func gain(players: Dictionary, speaker: int, listener: int) -> float:
	if speaker==listener or not players.has(speaker) or not players.has(listener):return 0.0
	if not can_speak(players,speaker) or not can_speak(players,listener): return 0.0
	if players[speaker].get("life","")=="soul" or players[listener].get("life","")=="soul":
		if int(players[speaker].get("possessing",0))==listener and Souls.alive(players[listener]): return 1.0
		if int(players[listener].get("possessing",0))==speaker and Souls.alive(players[speaker]): return 1.0
		return 0.0
	var a: Dictionary=players[Souls.observer_id(players,speaker)];var b: Dictionary=players[Souls.observer_id(players,listener)]
	var horizontal: float=Vector2(a.get("pos",Vector2.ZERO)).distance_squared_to(Vector2(b.get("pos",Vector2.ZERO)))
	var vertical: float=float(a.get("height",0))-float(b.get("height",0))
	var distance:=sqrt(horizontal+vertical*vertical)
	return clampf((RANGE-distance)/(RANGE-3.0),0.0,1.0)
