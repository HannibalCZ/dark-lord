# scripts/ui/AIDebugTab.gd
# Debug tab — zobrazuje WorldAI utility scoring breakdown pro každého aktéra.
# Znovu se builduje po každém game_updated signálu.
extends Control

@onready var actors_container: VBoxContainer = $ScrollContainer/ActorsContainer

func _ready() -> void:
	var parent = get_parent()
	if parent is TabContainer:
		parent.set_tab_title(parent.get_tab_idx_from_control(self), "⚙ AI Debug")
	GameState.game_updated.connect(_refresh)
	_refresh()

func _refresh() -> void:
	for child in actors_container.get_children():
		child.queue_free()

	if not GameState.world_ai_manager:
		return

	var snapshots: Array = GameState.world_ai_manager.get_all_actor_snapshots()
	for snapshot in snapshots:
		actors_container.add_child(_build_block(snapshot))

func _build_block(snapshot: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1a1a2e")
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	card.add_theme_stylebox_override("panel", style)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", 11)
	label.add_theme_font_size_override("bold_font_size", 12)
	card.add_child(label)

	label.text = _format_snapshot(snapshot)
	return card

func _format_snapshot(snapshot: Dictionary) -> String:
	var faction_id: String = snapshot.get("faction_id", "?")
	var active_plan: String = snapshot.get("active_plan", "—")
	var plan_turn: int = snapshot.get("plan_turn", 0)
	var log: Dictionary = snapshot.get("log", {})

	if log.is_empty():
		return "[b]═══ %s ═══[/b]\nČekám na první tah..." % faction_id.to_upper()

	var turn: int = log.get("turn", 0)
	var switched: bool = log.get("switched", false)
	var reason: String = log.get("reason", "?")
	var scores: Dictionary = log.get("scores", {})
	var breakdowns: Dictionary = log.get("breakdowns", {})
	var best_action: String = log.get("best_action", "")

	var lines: Array = []
	lines.append("[b]═══ %s [T%d] ═══[/b]" % [faction_id.to_upper(), turn])
	lines.append("Aktivní plán: [b]%s[/b]  (od T%d, switched: %s)" % [active_plan, plan_turn, str(switched)])
	lines.append("Důvod: %s" % reason)
	lines.append("")

	# Seřaď sestupně podle skóre
	var action_keys: Array = scores.keys()
	action_keys.sort_custom(func(a, b):
		return scores[a].get("score", 0.0) > scores[b].get("score", 0.0)
	)

	for action_key in action_keys:
		var score_dict: Dictionary = scores.get(action_key, {})
		var final_score: float = score_dict.get("score", 0.0)
		var base_score: float = score_dict.get("base", 0.0)
		var breakdown: Array = breakdowns.get(action_key, [])
		var is_winner: bool = (action_key == best_action)

		var header_color: String = "#ffd700" if is_winner else "#cccccc"
		var winner_str: String = "  [color=#ffd700]← VÍTĚZ[/color]" if is_winner else ""
		lines.append("[color=%s][b]  %s[/b][/color]   výsledek: %.2f%s" % [header_color, action_key.to_upper(), final_score, winner_str])
		lines.append("    base:   %.2f" % base_score)

		for step in breakdown:
			var cond: String = step.get("condition", "")
			var met: bool = step.get("met", false)
			var mult: float = step.get("multiplier", 1.0)
			var score_after: float = step.get("score_after", 0.0)
			var check: String = "[color=#7cfc00]✓[/color]" if met else "[color=#ff6347]✗[/color]"
			var mult_color: String = "#ffffff" if met else "#666666"
			var result_str: String = "%.2f" % score_after if met else "(nesplněno)"
			lines.append("    %s %s [color=%s]×%.1f[/color]  →  %s" % [check, cond, mult_color, mult, result_str])

		lines.append("")

	return "\n".join(lines)
