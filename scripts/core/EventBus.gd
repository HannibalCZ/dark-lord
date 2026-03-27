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

signal combat_resolved(result: Dictionary)

signal org_founded(org: Dictionary)
signal org_destroyed(region_id: int)
signal org_doctrine_changed(region_id: int, new_doctrine: String)

signal ai_unit_spawned(faction_id: String, unit_key: String, region_id: int)
