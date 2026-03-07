extends Control

signal spell_cast(spell_id: int)

var spell_data: Dictionary

func setup(data: Dictionary) -> void:
	# deferred zajistí, že UI nody už existují
	call_deferred("_setup_internal", data)

func _setup_internal(data: Dictionary) -> void:
	spell_data = data

	var name_label: Label = $PanelContainer/HBoxContainer/VBoxContainer/NameLabel
	var desc_label: Label = $PanelContainer/HBoxContainer/VBoxContainer/DescLabel
	var cast_btn: Button = $PanelContainer/HBoxContainer/CastButton

	name_label.text = "%s (%s)" % [data["name"], data["branch"]]
	desc_label.text = "%s\nCena: %d výzkum" % [data["desc"], data["cost"]]

	_refresh_button_state()

	cast_btn.pressed.connect(_on_cast_pressed)
	GameState.connect("game_updated", Callable(self, "_refresh"))

func _refresh_button_state() -> void:
	if not is_inside_tree() or spell_data.is_empty():
		return
	var cast_btn: Button = $PanelContainer/HBoxContainer/CastButton
	cast_btn.disabled = GameState.faction_manager.get_faction(Balance.PLAYER_FACTION).resources["research"] < spell_data["cost"]

func _on_cast_pressed() -> void:
	GameState.cast_spell(spell_data["id"])
	spell_cast.emit(spell_data["id"])
