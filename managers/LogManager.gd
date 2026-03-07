extends Node
class_name LogManager

signal log_updated

var entries: Array[Dictionary] = []

func add(entry:Dictionary) -> void:
	entries.push_front(entry)
	emit_signal("log_updated")

func clear() -> void:
	entries.clear()
	emit_signal("log_updated")
