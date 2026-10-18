extends RefCounted
## Pure inventory arithmetic. No model, scene, map or HUD dependencies.
const CAPACITY := 12.0

static func weight(items: Array) -> float:
	var total := 0.0
	for item in items:
		total += float(item.weight)
	return total

static func value(items: Array) -> int:
	var total := 0
	for item in items:
		total += int(item.value)
	return total

static func can_add(items: Array, item: Dictionary, capacity: float = CAPACITY) -> bool:
	return weight(items) + float(item.weight) <= capacity + 0.001
