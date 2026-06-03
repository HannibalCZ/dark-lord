extends GutTest

var region: Region

func before_each():
	# Region._init vyžaduje (id, name, faction_id, terrain)
	region = Region.new(0, "Test", "neutral", "plains")
	# population defaultuje na 0


func test_duration_tag_se_dekrementuje():
	var tag = Balance.TAGS["raid"].duplicate()
	tag["duration"] = 3
	region.add_tag(tag)
	region.tick_tags()
	assert_eq(region.tags[0]["duration"], 2)


func test_duration_tag_zmizi_pri_nule():
	var tag = Balance.TAGS["raid"].duplicate()
	tag["duration"] = 1
	region.add_tag(tag)
	region.tick_tags()
	assert_eq(region.tags.size(), 0)


func test_stavovy_tag_pretrvava():
	var tag = Balance.TAGS["unrest"].duplicate()
	region.add_tag(tag)
	region.tick_tags()
	assert_eq(region.tags.size(), 1)
	# duration zůstane -1
	assert_eq(region.tags[0]["duration"], -1)


func test_dva_tagy_nezavisle():
	var duration_tag = Balance.TAGS["raid"].duplicate()
	duration_tag["duration"] = 2
	var stavovy_tag = Balance.TAGS["unrest"].duplicate()
	region.add_tag(duration_tag)
	region.add_tag(stavovy_tag)
	region.tick_tags()
	# raid dekrementován, unrest přetrvává
	assert_eq(region.tags.size(), 2)
	for tag in region.tags:
		if tag["id"] == "raid":
			assert_eq(tag["duration"], 1)
		if tag["id"] == "unrest":
			assert_eq(tag["duration"], -1)


func test_stejny_tag_prodlouzi_duration():
	var tag1 = Balance.TAGS["raid"].duplicate()
	tag1["duration"] = 2
	region.add_tag(tag1)
	var tag2 = Balance.TAGS["raid"].duplicate()
	tag2["duration"] = 5
	region.add_tag(tag2)
	# add_tag přepíše existující — duration je nyní 5
	assert_eq(region.tags.size(), 1)
	assert_eq(region.tags[0]["duration"], 5)
