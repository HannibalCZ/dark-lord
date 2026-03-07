extends Control

@onready var spells_container: VBoxContainer = $VBoxContainer/Spells
var spell_scene: PackedScene = preload("res://scenes/ui/MagicSpell.tscn")

func _ready() -> void:
	_refresh()
	GameState.connect("game_updated", Callable(self, "_refresh"))
	GameState.connect("magic_used", Callable(self, "_refresh"))

func _refresh() -> void:
	for c in spells_container.get_children():
		c.queue_free()

	for spell in GameState.spell_manager.spells:
		var s: Control = spell_scene.instantiate()
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_FILL
		spells_container.add_child(s)
		s.setup(spell)
