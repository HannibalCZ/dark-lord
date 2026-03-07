# res://scripts/ui/TweenHelper.gd
extends Node

const COLOR_TILE_SELECTED  = Color(0.55, 0.36, 0.86, 0.45) # fialový výběr
const COLOR_TILE_HOVER     = Color(1, 1, 1, 0.18)          # jemný highlight
const COLOR_TILE_CLEAR     = Color(1, 1, 1, 0.0)

# --- Low-level helper: vytvoří tween na konkrétním nodu
func _tween(node: Node) -> Tween:
	return node.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

# --- 1) Hover efekt tile
func tile_hover_in(highlight: ColorRect) -> void:
	var t = _tween(highlight)
	t.tween_property(highlight, "color", COLOR_TILE_HOVER, 0.12)

func tile_hover_out(highlight: ColorRect, is_selected: bool) -> void:
	var target_color := COLOR_TILE_CLEAR
	if is_selected:
		target_color = COLOR_TILE_SELECTED
	var t = _tween(highlight)
	t.tween_property(highlight, "color", target_color, 0.10)

# --- 2) Výběr tile (klik)
func tile_select(highlight: ColorRect) -> void:
	var t = _tween(highlight)
	t.tween_property(highlight, "color", COLOR_TILE_SELECTED, 0.15)

func tile_deselect(highlight: ColorRect) -> void:
	var t = _tween(highlight)
	t.tween_property(highlight, "color", COLOR_TILE_CLEAR, 0.15)

# --- 3) Bounce efekt (kliknutí, spawn)
func bounce(node: Node, scale := 1.07, duration := 0.12) -> void:
	var t = _tween(node)
	t.tween_property(node, "scale", Vector2.ONE * scale, duration * 0.5)
	t.tween_property(node, "scale", Vector2.ONE, duration * 0.5)

# --- 4) Pulzování (např. tag ikona)
func pulse_scale(node: Node, from := 1.0, to := 1.1, duration := 0.6) -> void:
	var t = _tween(node)
	t.set_loops()  # infinite
	t.tween_property(node, "scale", Vector2.ONE * to, duration * 0.5)
	t.tween_property(node, "scale", Vector2.ONE * from, duration * 0.5)
