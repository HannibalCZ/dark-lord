extends GutTest

var manager: MissionManager
var region: Region
var unit: Unit

func before_each():
	# Region._init vyžaduje (id, name, faction_id, terrain)
	region = Region.new(0, "Test", "neutral", "plains")
	region.population = 4  # civilized (>= Balance.CIVILIZED_THRESHOLD = 3)
	region.fear = 0
	region.stability = 70
	unit = Unit.new()
	# MissionManager extends Node — autofree() zajistí uvolnění po každém testu
	manager = autofree(MissionManager.new())


func test_region_kind_in_pass():
	var req = {"region_kind_in": ["civilized"]}
	assert_true(manager._check_requirements(req, unit, region))


func test_region_kind_in_fail():
	region.population = 1  # wilderness (< CIVILIZED_THRESHOLD)
	var req = {"region_kind_in": ["civilized"]}
	assert_false(manager._check_requirements(req, unit, region))


func test_min_fear_splneno():
	region.fear = 40
	var req = {"min_fear": 30}
	assert_true(manager._check_requirements(req, unit, region))


func test_min_fear_nesplneno():
	region.fear = 20
	var req = {"min_fear": 30}
	assert_false(manager._check_requirements(req, unit, region))


func test_max_stability_splneno():
	region.stability = 40
	var req = {"max_stability": 50}
	assert_true(manager._check_requirements(req, unit, region))


func test_max_stability_nesplneno():
	region.stability = 60
	var req = {"max_stability": 50}
	assert_false(manager._check_requirements(req, unit, region))


func test_requires_secret_pass():
	region.secret_id = "ancient_ruins"
	region.secret_known = true
	region.secret_state = "in_progress"
	var req = {
		"requires_secret": true,
		"secret_known": true,
		"secret_state_not_in": ["resolved"]
	}
	assert_true(manager._check_requirements(req, unit, region))


func test_requires_secret_bez_tajemstvi():
	region.secret_id = ""
	var req = {"requires_secret": true}
	assert_false(manager._check_requirements(req, unit, region))
