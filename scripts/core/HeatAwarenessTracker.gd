extends RefCounted
class_name HeatAwarenessTracker

# Záznamy heat/awareness změn za aktuální tah.
# Resetuje se na začátku každého advance_turn().
# Každý záznam odpovídá jednomu effects_system.apply() volání
# které měnilo heat nebo awareness.
var entries: Array[Dictionary] = []

func record(
		source_label: String,
		heat_delta: int,   heat_after: int,
		awareness_delta: int, awareness_after: int
) -> void:
	if heat_delta == 0 and awareness_delta == 0:
		return
	entries.append({
		"source":           source_label if source_label != "" else "?",
		"heat_delta":       heat_delta,
		"heat_after":       heat_after,
		"awareness_delta":  awareness_delta,
		"awareness_after":  awareness_after
	})

func reset() -> void:
	entries.clear()

func get_heat_total() -> int:
	var total := 0
	for e in entries:
		total += int(e.get("heat_delta", 0))
	return total

func get_awareness_total() -> int:
	var total := 0
	for e in entries:
		total += int(e.get("awareness_delta", 0))
	return total
