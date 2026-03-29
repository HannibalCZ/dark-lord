extends Control
signal tile_selected(region_id: int)

var region_id: int = -1
var button: Button

@onready var terrain_sprite: TextureRect = $TerrainSprite
@onready var highlight: ColorRect   = $Highlight
@onready var overlay: Control          = $Overlay
@onready var crest: TextureRect        = $Overlay/Crest
@onready var tag_icon: TextureRect     = $Overlay/TagIcon
@onready var player_icon: TextureRect  = $Overlay/PlayerIcon
@onready var player_count: Label       = $Overlay/PlayerCount
@onready var enemy_icon: TextureRect   = $Overlay/EnemyIcon
@onready var enemy_count: Label        = $Overlay/EnemyCount
@onready var corruption_overlay: TextureRect = $CorruptionSprite
@onready var secret_icon: TextureRect = $Overlay/SecretIcon
@onready var lair_icon: TextureRect = $Overlay/LairIcon

var _is_selected: bool = false
var _is_hovered: bool = false
var _tag_pulsing: bool = false
var _is_movement_target: bool = false

const ICON_W := 16
const ICON_H := 16
const COUNT_H := 10

func _ready() -> void:
	button = $Button
	button.pressed.connect(_on_pressed)
	button.mouse_entered.connect(_on_mouse_entered)
	button.mouse_exited.connect(_on_mouse_exited)

func setup(id: int, region: Region) -> void:
	region_id = id

	# terrain podle typu
	terrain_sprite.texture = load(_get_terrain_texture_path(region.region_type))

	# crest podle ownera / controllera
	_update_crest(region.owner_faction_id, region.controller_faction_id)

	# tag icon podle toho, zda tagy existují
	_update_tag_icon(region.tags)

func _on_mouse_entered() -> void:
	TweenHelper.tile_hover_in(highlight)
	

func _on_mouse_exited() -> void:
	TweenHelper.tile_hover_out(highlight, _is_selected)

func set_selected(sel: bool) -> void:
	_is_selected = sel
	if sel:
		TweenHelper.tile_select(highlight)
		TweenHelper.bounce(self)  # malý bounce při výběru
	else:
		TweenHelper.tile_deselect(highlight)

func set_movement_target(active: bool) -> void:
	_is_movement_target = active
	if active:
		highlight.color = Color(0.2, 0.7, 0.3, 0.35)
	else:
		_update_highlight()

func _update_highlight() -> void:
	if _is_selected:
		# 10.2 – vybraný region: fialový highlight
		highlight.color = Color(0.55, 0.36, 0.86, 0.25)  # něco jako #8b5cf6, alpha 0.45
	elif _is_hovered:
		# 10.1 – jen hover: jemný světlý nádech
		highlight.color = Color(1, 1, 1, 0.18)           # bílé, ale slabá alpha
	else:
		# nic – průhledné
		highlight.color = Color(1, 1, 1, 0)

func _get_corruption_alpha_for_phase(phase_id: int) -> float:
	match phase_id:
		0:
			return 0.0
		1:
			return 0.40
		2:
			return 0.60
		3:
			return 0.80
		4:
			return 0.95
		_:
			return 0.0

func _get_terrain_texture_path(region_type: String) -> String:
	match region_type:
		"forest":
			return "res://art/tiles/forest.png"
		"plains":
			return "res://art/tiles/plains.png"
		"mountains":
			return "res://art/tiles/mountains.png"
		"wasteland":
			return "res://art/tiles/wasteland.png"
		"town":
			return "res://art/tiles/mountains.png" # need to change
		_:
			return "res://art/tiles/mountains.png" # need to change

func refresh_from_region(region: Region) -> void:
	_update_crest(region.owner_faction_id, region.controller_faction_id)
	_update_tag_icon(region.tags)
	_update_secret_icon(region)
	_update_lair_icon(region)
	# případně později nějaké další vizuály (např. corruption aura)
	# --- NOVÉ: korupční overlay ---
	var corr: float = region.get_corruption_for(Balance.PLAYER_FACTION)

	if corr <= 0.0:
		# žádná korupce → overlay schovat
		corruption_overlay.visible = false
	else:
		var phase_def: Dictionary = region.get_corruption_phase_def_for(Balance.PLAYER_FACTION)
		var phase_id: int = int(phase_def.get("id", 0))
		var alpha: float = _get_corruption_alpha_for_phase(phase_id)

		if alpha <= 0.0:
			corruption_overlay.visible = false
		else:
			corruption_overlay.visible = true
			# zachovej barvu, změň jen alpha
			var col: Color = corruption_overlay.self_modulate
			col.a = alpha
			corruption_overlay.self_modulate = col

func _update_secret_icon(region: Region) -> void:
	if region.secret_known and region.has_active_secret():
		secret_icon.visible = true
	else:
		secret_icon.visible = false

func _update_lair_icon(region: Region) -> void:
	if region == null:
		lair_icon.visible = false
		return

	if region.has_lair():
		lair_icon.visible = true
	else:
		lair_icon.visible = false

func _update_crest(owner_id: String, controller_id: String) -> void:
	# jeden společný sprite pro všechny frakce
	if crest.texture == null:
		crest.texture = load("res://art/ui/crest.png")
	
	if owner_id == "neutral": crest.visible = false
	else: crest.visible = true
	# barva podle OWNera
	var color := Color.WHITE
	match owner_id:
		"elf":      color = Color("4caf50")
		"paladin":  color = Color("cca644")
		"merchant": color = Color("55aadd")
		Balance.PLAYER_FACTION:
			color = Color("5e2b8f")
		_:
			color = Color("aaaaaa")

	# pokud controller != owner -> zkorumpovaný, přidej fialový nádech
	if controller_id != "" and controller_id != owner_id:
		color = color.lerp(Color("b45cd1"), 0.5)

	crest.modulate = color

func _on_pressed() -> void:
	tile_selected.emit(region_id)
	
func play_feedback(success: bool):
	var color
	if success :
		color = Color(0,1,0,1)
	else :
		color = Color(1,0,0,1)
	var tween = create_tween()
	tween.tween_property(self, "modulate", color, 0.3).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "modulate", Color.WHITE, 0.5)

func _update_tag_icon(tags: Array) -> void:
	var has_tags := tags.size() > 0

	if has_tags:
		if tag_icon.texture == null:
			tag_icon.texture = load("res://art/ui/tag.png")
		tag_icon.visible = true

		## tooltip – poskládáme z display_name
		#var names: Array[String] = []
		#for t in tags:
			#if typeof(t) == TYPE_DICTIONARY and t.has("display_name"):
				#names.append(str(t["display_name"]))
		#tag_icon.hint_tooltip = names.is_empty() ? "Aktivní efekty" : "\n".join(names)

		# spustit pulz JEN pokud ještě neběží
		if not _tag_pulsing:
			_tag_pulsing = true
			TweenHelper.pulse_scale(tag_icon)

	else:
		tag_icon.visible = false
		_tag_pulsing = false
		tag_icon.scale = Vector2.ONE  # reset pro jistotu

func update_units_display(units_here: Array, enemy_here: Array) -> void:
	# počty pro hráče
	var player_armies := 0
	var player_agents := 0
	var has_busy_player: bool = false

	for u in units_here:
		if u.type == "army":
			player_armies += 1
		elif u.type == "agent":
			player_agents += 1
		if u.state == "busy":
			has_busy_player = true

	# počty pro AI
	var enemy_armies := 0
	var enemy_agents := 0

	for u in enemy_here:
		if u.type == "army":
			enemy_armies += 1
		elif u.type == "agent":
			enemy_agents += 1

	# ----------------------------------------------------
	# Player units
	# ----------------------------------------------------
	var p_total := player_armies + player_agents
	if p_total > 0:
		var tex := _select_icon(player_armies, player_agents)
		player_icon.texture = tex
		player_icon.visible = true

		if p_total > 1:
			player_count.text = str(p_total)
			player_count.visible = true
		else:
			player_count.visible = false
	else:
		player_icon.visible = false
		player_count.visible = false

	# ----------------------------------------------------
	# Enemy units
	# ----------------------------------------------------
	var e_total := enemy_armies + enemy_agents
	if e_total > 0:
		var tex := _select_icon(enemy_armies, enemy_agents)
		enemy_icon.texture = tex
		enemy_icon.visible = true

		if e_total > 1:
			enemy_count.text = str(e_total)
			enemy_count.visible = true
		else:
			enemy_count.visible = false
	else:
		enemy_icon.visible = false
		enemy_count.visible = false

	# ----------------------------------------------------
	# Positioning logic:
	# - pokud je pouze hráč NEBO pouze AI → zarovnat doprostřed dole
	# - pokud jsou oba → hráč vlevo dole, AI vpravo dole
	# ----------------------------------------------------

	var has_player := p_total > 0
	var has_enemy := e_total > 0

	if has_player and not has_enemy:
		_align_center_bottom(player_icon, player_count)

	elif has_enemy and not has_player:
		_align_center_bottom(enemy_icon, enemy_count)

	else:
		_align_left_bottom(player_icon, player_count)
		_align_right_bottom(enemy_icon, enemy_count)

	# ----------------------------------------------------
	# Helper: který typ ikony zobrazit?
	# ----------------------------------------------------
func _select_icon(armies: int, agents: int) -> Texture:
	if armies > 0:
		return preload("res://art/ui/army.png")
	elif agents > 0:
		return preload("res://art/ui/agent.png")
	return null

func _align_center_bottom(icon: TextureRect, count: Label) -> void:
	# Ikona: dole uprostřed
	icon.anchor_left = 0.5
	icon.anchor_top = 1.0
	icon.anchor_right = 0.5
	icon.anchor_bottom = 1.0

	icon.offset_left = -ICON_W / 2
	icon.offset_top = -ICON_H - 2  

	# Count text: hned pod ikonou
	count.anchor_left = 0.5
	count.anchor_top = 1.0
	count.anchor_right = 0.5
	count.anchor_bottom = 1.0

	count.offset_left = +20
	count.offset_top = -COUNT_H - 2  # text těsně nad spodní hranou

func _align_left_bottom(icon: TextureRect, count: Label) -> void:
	icon.anchor_left = 0.0
	icon.anchor_top  = 1.0
	icon.anchor_right = 0.0
	icon.anchor_bottom = 1.0

	icon.offset_left = 4
	icon.offset_top = -ICON_H - 2

	count.anchor_left = 0.0
	count.anchor_top  = 1.0
	count.anchor_right = 0.0
	count.anchor_bottom = 1.0

	count.offset_left = ICON_W + 4
	count.offset_top  = -COUNT_H - 4

func _align_right_bottom(icon: TextureRect, count: Label) -> void:
	icon.anchor_left = 1.0
	icon.anchor_top  = 1.0
	icon.anchor_right = 1.0
	icon.anchor_bottom = 1.0

	icon.offset_left = -ICON_W - 4
	icon.offset_top = -ICON_H - 2

	count.anchor_left = 1.0
	count.anchor_top  = 1.0
	count.anchor_right = 1.0
	count.anchor_bottom = 1.0

	count.offset_left = -ICON_W - 20
	count.offset_top  = -COUNT_H - 4

#func play_move_animation() -> void:
	#var tween = create_tween()
	##tween.tween_property(self, "scale", Vector2(1.15, 1.15), 0.1)
	##tween.tween_property(self, "scale", Vector2.ONE, 0.1)
	#tween.tween_property(player_count, "scale", Vector2(1.15, 1.15), 0.1)
	#tween.tween_property(player_count, "scale", Vector2.ONE, 0.1)
	##tween.tween_property(self, "modulate:a", 0.3, 0.15)
	##tween.tween_property(self, "modulate:a", 1.0, 0.15)
