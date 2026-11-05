extends RefCounted
## Ground Zero remains testable without restoring the retired player-facing base route.
static func prepare(game)->void:
 for station in game.session.model.stations:
  if station.get("uid","")=="bunker_to_city":
   station.destination="surface"
   station.spawn=preload("res://worlds/ground_zero/map_library.gd").source_location("surface","Special/BunkerEntry")
static func enter(game)->void:
 prepare(game)
 game.session.send("travel",{"route":"bunker_to_city"})
