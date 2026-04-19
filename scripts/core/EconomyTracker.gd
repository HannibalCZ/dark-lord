extends RefCounted
class_name EconomyTracker

var entries: Array[Dictionary] = []

func reset() -> void:
	entries.clear()

func record(label: String, gold: int = 0, mana: int = 0) -> void:
	if gold == 0 and mana == 0:
		return
	entries.append({
		"source_label": label,
		"gold_delta":   gold,
		"mana_delta":   mana
	})

func get_gold_total() -> int:
	var total: int = 0
	for e in entries:
		total += e.get("gold_delta", 0)
	return total

func get_mana_total() -> int:
	var total: int = 0
	for e in entries:
		total += e.get("mana_delta", 0)
	return total
