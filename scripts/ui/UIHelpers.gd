# res://scripts/ui/UIHelpers.gd
extends RefCounted
class_name UIHelpers

# Přidá položku do OptionButton a uloží "key" do metadata.
# Vrací index přidané položky.
static func add_option_with_key(opt: OptionButton, label: String, key: String) -> int:
	opt.add_item(label)
	var idx: int = opt.get_item_count() - 1
	# metadata musí být String (ne null), jinak se to začne rozpadat při typed assignu
	opt.set_item_metadata(idx, key)
	return idx


# Přidá placeholder s metadata = "" (bezpečné proti Nil).
static func set_single_placeholder(opt: OptionButton, label: String) -> void:
	opt.clear()
	opt.add_item(label)
	opt.set_item_metadata(0, "")
	opt.select(0)


# Vrátí "key" z metadata vybrané položky. (Používá INDEX, ne ID.)
# Nikdy nehází, vrací "" pokud není vybráno/není metadata.
static func get_selected_key(opt: OptionButton) -> String:
	if opt == null or opt.disabled:
		return ""

	var idx: int = opt.get_selected() # index
	if idx < 0:
		return ""

	var meta: Variant = opt.get_item_metadata(idx)
	if meta == null:
		return ""

	# Godot 4: metadata může být StringName, String…
	var t: int = typeof(meta)
	if t == TYPE_STRING or t == TYPE_STRING_NAME:
		return str(meta)

	# Pokud tam někdo omylem uloží int apod., raději vrátit ""
	return ""


# (Volitelné) Vrátí true, pokud je vybrán neprázdný key
static func has_valid_selected_key(opt: OptionButton) -> bool:
	return get_selected_key(opt) != ""
