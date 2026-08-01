extends Control
## Barra di costruzione inferiore + pulsante ANNULLA.
##
## Regole del TDD 00 §13: tutto raggiungibile col pollice di una mano sola,
## target di tocco >= 88 px, e l'ANNULLA in basso a sinistra dove il pollice
## arriva senza spostare la presa.

const BAR_H := 108
const BTN_MIN := 88
const COL_ACTIVE := Color("#39d3a8")

var ghost: Node2D

var _bar: HBoxContainer
var _undo_btn: Button
var _stock: Label
var _buttons: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_apply_safe_area(root)
	get_tree().get_root().size_changed.connect(func() -> void: _apply_safe_area(root))

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_END
	col.add_theme_constant_override("separation", 10)
	root.add_child(col)

	# --- riga inventario + annulla ---
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 12)
	col.add_child(top)

	_undo_btn = Button.new()
	_undo_btn.text = "ANNULLA"
	_undo_btn.custom_minimum_size = Vector2(150, BTN_MIN)
	_undo_btn.add_theme_font_size_override("font_size", 24)
	_undo_btn.visible = false
	_undo_btn.pressed.connect(func() -> void: SimCore.build.undo())
	top.add_child(_undo_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)

	_stock = Label.new()
	_stock.add_theme_font_size_override("font_size", 24)
	_stock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_stock)

	# --- barra strumenti ---
	_bar = HBoxContainer.new()
	_bar.custom_minimum_size = Vector2(0, BAR_H)
	_bar.add_theme_constant_override("separation", 8)
	col.add_child(_bar)

	_add_tool(BuildGhostTool.NONE, "Muovi")
	_add_tool(BuildGhostTool.BELT, "Nastro")
	_add_tool(BuildGhostTool.DRILL, "Trivella")
	_add_tool(BuildGhostTool.STORAGE, "Silo")
	_add_tool(BuildGhostTool.DEMOLISH, "Demolisci")

	SimCore.build.undo_available.connect(_on_undo_available)
	SimCore.build.rejected.connect(_on_rejected)
	_select(BuildGhostTool.NONE)


## Rispecchia l'enum di build_ghost.gd. Duplicato di proposito: un Control non
## deve dipendere da un Node2D della vista solo per leggere cinque costanti.
class BuildGhostTool:
	const NONE := 0
	const BELT := 1
	const DRILL := 2
	const STORAGE := 3
	const DEMOLISH := 4


func _add_tool(id: int, label: String) -> void:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(0, BTN_MIN)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(func() -> void: _select(id))
	_bar.add_child(b)
	_buttons[id] = b


func _select(id: int) -> void:
	if ghost != null:
		ghost.call(&"set_tool", id)
	for k: Variant in _buttons:
		var b: Button = _buttons[k]
		b.add_theme_color_override("font_color",
			COL_ACTIVE if int(k) == id else Color.WHITE)


func _process(_delta: float) -> void:
	var iron := int(SimCore.world.inventory.get(&"ingot_iron", 0))
	var copper := int(SimCore.world.inventory.get(&"ingot_copper", 0))
	var ore := int(SimCore.world.inventory.get(&"ore_iron", 0)) \
		+ int(SimCore.world.inventory.get(&"ore_copper", 0))
	_stock.text = "Fe %d   Cu %d   grezzo %d" % [iron, copper, ore]


func _on_undo_available(available: bool, label: String) -> void:
	_undo_btn.visible = available
	_undo_btn.text = "ANNULLA" if label.is_empty() else "ANNULLA %s" % label


func _on_rejected(reason: String) -> void:
	_stock.text = reason


## Gesture bar di Android e home indicator di iOS mangiano la parte bassa dello
## schermo: e' esattamente dove sta la barra di costruzione. Va rispettata ora,
## non quando qualcuno segnala che i pulsanti non si premono.
func _apply_safe_area(m: MarginContainer) -> void:
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.window_get_size()
	var pad := 20
	var l := pad
	var t := pad
	var r := pad
	var b := pad
	if screen.x > 0 and screen.y > 0 and safe.size.x > 0:
		var vp := get_viewport_rect().size
		var sx := vp.x / float(screen.x)
		var sy := vp.y / float(screen.y)
		l += int(float(safe.position.x) * sx)
		t += int(float(safe.position.y) * sy)
		r += int(float(screen.x - safe.end.x) * sx)
		b += int(float(screen.y - safe.end.y) * sy)
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", t)
	m.add_theme_constant_override("margin_right", r)
	m.add_theme_constant_override("margin_bottom", b)
