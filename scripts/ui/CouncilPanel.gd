# scripts/ui/CouncilPanel.gd
extends CanvasLayer

@onready var cards_container: VBoxContainer = $PanelContainer/VBoxContainer/ScrollContainer/CardsContainer
@onready var close_button: Button = $PanelContainer/VBoxContainer/CloseButton

func _ready() -> void:
	EventBus.council_events_ready.connect(_on_council_events_ready)
	close_button.pressed.connect(_on_close_pressed)
	hide()

# ---------------------------
func _on_council_events_ready(events: Array[EventData]) -> void:
	if events.is_empty():
		return
	_populate(events)
	show()

# ---------------------------
func _populate(events: Array[EventData]) -> void:
	for child in cards_container.get_children():
		child.queue_free()
	for ev in events:
		cards_container.add_child(_create_card(ev))

# ---------------------------
func _create_card(ev: EventData) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Styl karty - tmave pozadi + levy barevny pruh podle priority
	var style := StyleBoxFlat.new()
	style.bg_color                   = Color(0.12, 0.10, 0.10, 1.0)
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left  = 6
	style.content_margin_left        = 14.0
	style.content_margin_right       = 12.0
	style.content_margin_top         = 10.0
	style.content_margin_bottom      = 10.0

	match ev.priority:
		Balance.EVENT_CRITICAL:
			style.border_width_left = 4
			style.border_color = Color(0.85, 0.15, 0.15, 1.0)
		Balance.EVENT_IMPORTANT:
			style.border_width_left = 4
			style.border_color = Color(0.85, 0.65, 0.10, 1.0)
		# EVENT_ROUTINE - bez pruhu (filtrem se sem nedostane, styl pripraven pro budoucnost)

	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	# Jmeno poradce - male, barevne podle priority
	var advisor_label := Label.new()
	advisor_label.text = _advisor_display_name(ev.advisor)
	advisor_label.add_theme_font_size_override("font_size", 13)
	match ev.priority:
		Balance.EVENT_CRITICAL:
			advisor_label.add_theme_color_override("font_color", Color(0.90, 0.35, 0.35, 1.0))
		Balance.EVENT_IMPORTANT:
			advisor_label.add_theme_color_override("font_color", Color(0.90, 0.75, 0.30, 1.0))
		_:
			advisor_label.add_theme_color_override("font_color", Color(0.60, 0.60, 0.60, 1.0))
	vbox.add_child(advisor_label)

	# Narativni text - hlavni, vetsi
	var narrative := Label.new()
	narrative.text = ev.narrative_text
	narrative.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	narrative.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(narrative)

	vbox.add_child(HSeparator.new())

	# Mechanicke shrnutí - mensi, sede
	var summary := Label.new()
	summary.text = ev.mechanical_summary
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_theme_font_size_override("font_size", 13)
	summary.add_theme_color_override("font_color", Color(0.60, 0.60, 0.60, 1.0))
	vbox.add_child(summary)

	return card

# ---------------------------
func _advisor_display_name(advisor: String) -> String:
	match advisor:
		Balance.ADVISOR_KAPITAN:
			return "Temny kapitan"
		Balance.ADVISOR_VEZIR:
			return "Stinovy vezir"
		_:
			return advisor

# ---------------------------
func _on_close_pressed() -> void:
	GameState.pending_events.clear()
	hide()
