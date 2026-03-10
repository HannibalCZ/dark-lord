# scripts/ui/ReplayTab.gd
extends Control

const MAX_LINES: int = 100
var _lines: Array[String] = []

@onready var log: RichTextLabel = $VBoxContainer/Log

func _ready() -> void:
	Log_Manager.connect("log_updated", Callable(self, "_refresh"))
	_refresh()

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

func _get_color(t: String) -> String:
	match t:
		"success": return "#7CFC00"  # zelená
		"failure": return "#FF6347"  # červená
		"heat":    return "#FFA500"  # oranžová
		"cycle":   return "#BA55D3"  # fialová
		"neutral": return "#AAAAAA"  # šedá
		_:         return "#FFFFFF"  # bílá
