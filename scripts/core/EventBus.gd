extends Node

signal mission_planned(mission: Mission)
signal mission_cancelled(mission: Mission)
signal mission_resolved(data)   # { mission, success, unit_id, region_id }

signal tag_added(region_id, tag_id)

signal unit_lost(unit_id, region_id)
signal unit_moved(unit_id: int, from_region: int, to_region: int)

signal resources_changed(faction_id: String)

signal heat_threshold_reached(threshold)

signal council_events_ready(events: Array[EventData])
