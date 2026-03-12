# scripts/models/EventData.gd
extends Resource
class_name EventData

var advisor: String = ""
# identifikátor poradce: "kapitan" | "vezir"
# (další poradci přijdou v pozdějších tascích)

var priority: String = ""
# "critical" | "important" | "routine"

var narrative_text: String = ""
# narativní text s osobností poradce, česky

var mechanical_summary: String = ""
# strohé mechanické shrnutí co se herně stalo, česky

var has_choice: bool = false
# MVP: vždy false, připraveno pro budoucí rozšíření

static func create(
		p_advisor: String,
		p_priority: String,
		p_narrative: String,
		p_summary: String
) -> EventData:
	var e = EventData.new()
	e.advisor = p_advisor
	e.priority = p_priority
	e.narrative_text = p_narrative
	e.mechanical_summary = p_summary
	return e
