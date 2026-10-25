extends RefCounted
## Migrated reference behavior; called only through the owning composition/model.

const Items = preload("res://features/inventory/item_catalog.gd")

static func _empty_slots(size: int) -> Array:
	var result: Array = []
	for i in range(size): result.append({})
	return result

static func _index(value: Variant, size: int) -> int:
	return int(value) if value is int and value >= 0 and value < size else -1

static func _insert(container: Array, item: Dictionary) -> bool:
	var remaining := int(item.count)
	var limit := int(Items.definition(item.kind).stack)
	# Work on a copy: callers never lose a partially inserted stack on failure.
	var trial: Array = container.duplicate(true)
	for existing in trial:
		if not existing.is_empty() and existing.kind == item.kind and int(existing.count) < limit:
			var amount := mini(remaining, limit - int(existing.count))
			existing.count += amount; remaining -= amount
			if remaining == 0: break
	if remaining > 0:
		for i in range(trial.size()):
			if trial[i].is_empty():
				trial[i] = item.duplicate(true); trial[i].count = remaining; remaining = 0
				break
	if remaining > 0: return false
	container.assign(trial)
	return true

static func _consume(container: Array, kind: String, count: int) -> int:
	var used := 0
	for i in range(container.size()):
		var item: Dictionary = container[i]
		if item.is_empty() or item.kind != kind: continue
		var amount := mini(count - used, int(item.count))
		item.count -= amount; used += amount
		if item.count <= 0: container[i] = {}
		if used >= count: break
	return used

static func _count(container: Array, kind: String) -> int:
	var count := 0
	for item in container:
		if not item.is_empty() and item.kind == kind: count += int(item.count)
	return count

static func _update_weight(p: Dictionary) -> void:
	p.weight = Items.weight(p.bag) + Items.weight(p.equipment.values())
	p.max_weight = (44.0 if not p.equipment.backpack.is_empty() else 28.0)+float(p.get("camp_weight_bonus",0))
