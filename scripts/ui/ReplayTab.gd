# scripts/ui/ReplayTab.gd
extends Control

const MAX_LINES: int = 100
var _lines: Array[String] = []

@onready var log: RichTextLabel = $VBoxContainer/Log
@onready var world_ai_log: RichTextLabel = $VBoxContainer/WorldAILog

func _ready() -> void:
	Log_Manager.connect("log_updated", Callable(self, "_refresh"))
	GameState.connect("game_updated", Callable(self, "_refresh_world_ai"))
	_refresh()
	_refresh_world_ai()

func _refresh() -> void:
	if not log:
		push_error("ReplayTab: log node is null!")
		return

	_lines.clear()
	for entry in Log_Manager.entries:
		_lines.append("[color=%s]• %s[/color]" % [_get_color(entry["type"]), entry["text"]])
		if _lines.size() > MAX_LINES:
			_lines.pop_front()

	log.clear()
	log.append_text("\n".join(_lines))

	await get_tree().process_frame
	log.scroll_to_line(log.get_line_count() - 1)

func _refresh_world_ai() -> void:
	if not world_ai_log:
		return

	var snapshots: Array = GameState.world_ai_manager.get_all_actor_snapshots()
	if snapshots.is_empty():
		world_ai_log.text = "Čekám na první tah..."
		return

	var blocks: Array[String] = []
	for snapshot in snapshots:
		var entry: Dictionary = snapshot.get("log", {})
		if entry.is_empty():
			var fid: String = snapshot.get("faction_id", "?")
			blocks.append("[%s] Čekám na první tah..." % fid)
			continue

		var turn: int = entry.get("turn", 0)
		var faction_id: String = snapshot.get("faction_id", "?")
		var active_plan: String = snapshot.get("active_plan", "—")
		var plan_turn: int = snapshot.get("plan_turn", 0)
		var reason: String = entry.get("reason", "?")
		var switched: bool = entry.get("switched", false)
		var scores: Dictionary = entry.get("scores", {})

		# Seřaď akce sestupně podle skóre
		var pairs: Array = []
		for action_key in scores.keys():
			pairs.append([action_key, scores[action_key]])
		pairs.sort_custom(func(a, b): return a[1] > b[1])

		var score_parts: Array[String] = []
		for pair in pairs:
			score_parts.append("%s=%.2f" % [pair[0], pair[1]])

		var line1: String = "[T%d] %s → %s (%s)" % [turn, faction_id, active_plan, reason]
		var line2: String = "  scores: %s" % " | ".join(score_parts)
		var line3: String = "  switched: %s  plan_since: T%d" % [str(switched), plan_turn]
		blocks.append("%s\n%s\n%s" % [line1, line2, line3])

	world_ai_log.text = "\n\n".join(blocks)

func _get_color(t: String) -> String:
	match t:
		"success": return "#7CFC00"  # zelená
		"failure": return "#FF6347"  # červená
		"heat":    return "#FFA500"  # oranžová
		"cycle":   return "#BA55D3"  # fialová
		"neutral": return "#AAAAAA"  # šedá
		_:         return "#FFFFFF"  # bílá
