extends RefCounted
class_name EffectContext

var game: GameStateSingleton
var region: Region = null
var source_faction_id: String = Balance.PLAYER_FACTION
var source_label: String = ""
var unit: Unit = null

static func make(game: GameStateSingleton, region: Region = null, source_faction_id: String = Balance.PLAYER_FACTION, unit: Unit = null) -> EffectContext:
	var ctx := EffectContext.new()
	ctx.game = game
	ctx.region = region
	ctx.source_faction_id = source_faction_id
	ctx.unit = unit
	return ctx
