extends GutTest

var region: Region

func before_each():
	# Region._init vyžaduje (id, name, faction_id, terrain)
	region = Region.new(0, "Test", "neutral", "plains")
	# population defaultuje na 0


func test_population_3_je_civilized():
	region.population = Balance.CIVILIZED_THRESHOLD
	assert_eq(region.region_kind, "civilized")


func test_population_2_je_wilderness():
	region.population = Balance.CIVILIZED_THRESHOLD - 1
	assert_eq(region.region_kind, "wilderness")


func test_population_0_je_wilderness():
	region.population = 0
	assert_eq(region.region_kind, "wilderness")


func test_region_kind_se_meni_s_populaci():
	region.population = Balance.CIVILIZED_THRESHOLD
	assert_eq(region.region_kind, "civilized")
	region.population = Balance.CIVILIZED_THRESHOLD - 1
	assert_eq(region.region_kind, "wilderness")
