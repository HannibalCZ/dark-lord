extends GutTest

var manager: WorldAIManager

func before_each():
	# WorldAIManager.new() funguje — _evaluate_condition nepotřebuje game_state
	manager = WorldAIManager.new()


func test_heat_vetsi_nez_splneno():
	assert_true(manager._evaluate_condition("heat > 25", {"heat": 50}))


func test_heat_vetsi_nez_nesplneno():
	assert_false(manager._evaluate_condition("heat > 25", {"heat": 25}))


func test_heat_vetsi_rovno_splneno():
	assert_true(manager._evaluate_condition("heat >= 25", {"heat": 25}))


func test_awareness_mensi_nez():
	assert_true(manager._evaluate_condition("awareness < 50", {"awareness": 30}))


func test_turn_rovnost():
	assert_true(manager._evaluate_condition("turn == 5", {"turn": 5}))


func test_neplatny_format_nevycrashuje():
	assert_false(manager._evaluate_condition("blabla", {}))


func test_prazdny_string_nevycrashuje():
	assert_false(manager._evaluate_condition("", {}))


func test_neznamy_stat_vraci_false():
	assert_false(manager._evaluate_condition("neznamy_stat > 10", {}))


func test_rival_present_true():
	assert_true(manager._evaluate_condition(
		"rival_present > 0",
		{"rival_present": true}
	))
