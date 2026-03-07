# scripts/ui/ReplayTab.gd
extends Control

@onready var log: RichTextLabel = $VBoxContainer/Log

func _ready() -> void:
	Log_Manager.connect("log_updated", Callable(self, "_refresh"))
	_refresh()

func _refresh() -> void:
	if not log:
		push_error("ReplayTab: log node is null!")
		return

	log.clear()
	for entry in Log_Manager.entries:
		log.append_text("[color=%s]• %s[/color]\n" % [_get_color(entry["type"]), entry["text"]])

func _get_color(t: String) -> String:
	match t:
		"success": return "#7CFC00"  # zelená
		"failure": return "#FF6347"  # červená
		"heat":    return "#FFA500"  # oranžová
		"cycle":   return "#BA55D3"  # fialová
		"neutral": return "#AAAAAA"  # šedá
		_:         return "#FFFFFF"  # bílá
