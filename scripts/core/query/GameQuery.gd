extends RefCounted
class_name GameQuery

var game: GameStateSingleton
var units: UnitQuery
var regions: RegionQuery

func _init(gs: GameStateSingleton) -> void:
	game = gs
	units = UnitQuery.new(gs)
	regions = RegionQuery.new(gs)

func rebuild_indexes() -> void:
	units.rebuild()
	regions.rebuild()
