extends Control
## Pannello diagnostico.
##
## Esiste perche' il criterio di completamento dello Sprint 0 e' "sul telefono
## vedi la griglia e la console stampa vi(ingot_iron) = 15.625" — e su un
## telefono la console NON si vede. Il controllo va quindi a schermo.
##
## Mostra anche i tre KPI prestazionali del TDD 00 §14 fin dal primo giorno:
## misurarli dallo Sprint 6 significa scoprire i problemi quando costano dieci
## volte tanto.
##
## LAYOUT: occupa SOLO la fascia alta. La parte bassa dello schermo appartiene
## alla barra di costruzione — e' la zona del pollice, e due UI che se la
## contendono e' esattamente il bug che il primo screenshot ha rivelato.

const FONT_SIZE := 24
const DETAIL_FONT_SIZE := 20
const COL_OK := Color("#5fd39a")
const COL_FAIL := Color("#e8635a")
const COL_WARN := Color("#e3b341")
const COL_DIM := Color("#8a97a8")

var _summary: RichTextLabel
var _detail: RichTextLabel
var _toggle: Button
var _panel: PanelContainer
var _margin: MarginContainer
var _expanded := false
var _items_cached := 0
var _item_timer := 0.0
var _selftest_cache := ""
var _selftest_failed_cache := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_margin = MarginContainer.new()
	# Ancorata in alto e libera di crescere verso il basso solo quanto serve.
	_margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_margin)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	_margin.add_child(row)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.08, 0.72)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", sb)
	row.add_child(_panel)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 6)
	_panel.add_child(col)

	_summary = _make_label(FONT_SIZE)
	col.add_child(_summary)

	_detail = _make_label(DETAIL_FONT_SIZE)
	_detail.visible = false
	col.add_child(_detail)

	_toggle = Button.new()
	_toggle.text = "i"
	_toggle.custom_minimum_size = Vector2(72, 72)
	_toggle.add_theme_font_size_override("font_size", 30)
	_toggle.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_toggle.pressed.connect(_on_toggle)
	row.add_child(_toggle)

	_apply_safe_area()
	get_tree().get_root().size_changed.connect(_apply_safe_area)
	_selftest_cache = _build_selftest_text()
	_detail.text = _selftest_cache
	_selftest_failed_cache = int(Database.self_test()["failed"])


func _make_label(size: int) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("normal_font_size", size)
	l.add_theme_font_size_override("bold_font_size", size)
	l.add_theme_color_override("default_color", COL_DIM)
	return l


## Notch su iPhone e barra di stato su Android: si rispettano ora, non quando
## qualcuno segnala che il testo finisce sotto l'orologio. La safe area e' in
## pixel schermo e la UI in pixel viewport: con stretch "canvas_items" i due
## sistemi non coincidono e vanno convertiti.
func _apply_safe_area() -> void:
	if _margin == null:
		return
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.window_get_size()
	var pad := 16
	var l := pad
	var t := pad
	var r := pad
	if screen.x > 0 and screen.y > 0 and safe.size.x > 0:
		var vp := get_viewport_rect().size
		var sx := vp.x / float(screen.x)
		var sy := vp.y / float(screen.y)
		l += int(float(safe.position.x) * sx)
		t += int(float(safe.position.y) * sy)
		r += int(float(screen.x - safe.end.x) * sx)
	_margin.add_theme_constant_override("margin_left", l)
	_margin.add_theme_constant_override("margin_top", t)
	_margin.add_theme_constant_override("margin_right", r)
	_margin.add_theme_constant_override("margin_bottom", 0)


func _process(delta: float) -> void:
	_item_timer += delta
	if _item_timer >= 0.5:
		# count_items() scandisce 27 000 byte: a 60 fps sarebbe uno spreco, e per
		# un indicatore diagnostico bastano due aggiornamenti al secondo.
		_item_timer = 0.0
		_items_cached = SimCore.belts.count_items()

	var fps := Engine.get_frames_per_second()
	var ms_tick := SimCore.avg_tick_usec / 1000.0
	var fps_col := COL_OK if fps >= 55 else (COL_WARN if fps >= 40 else COL_FAIL)
	var tick_col := COL_OK if ms_tick < 5.0 else (COL_WARN if ms_tick < 8.0 else COL_FAIL)
	var db_ok := _selftest_failed_cache == 0

	# Ripartizione per sistema: sapere CHE COSA costa e' l'unico modo di
	# ottimizzare la cosa giusta, e va misurata dallo Sprint 1.
	var belt_ms := float(SimCore.belts.last_usec) / 1000.0
	var mach_ms := float(SimCore.machines.last_usec) / 1000.0

	_summary.text = ("[color=#%s]%d fps[/color]  ·  [color=#%s]tick %.2f ms[/color]"
			% [fps_col.to_html(false), fps, tick_col.to_html(false), ms_tick]
		+ "  ·  [color=#%s]DB %s[/color]\n"
			% [(COL_OK if db_ok else COL_FAIL).to_html(false), "OK" if db_ok else "ERRORI"]
		+ "[b]%d[/b] item · %d corsie · %d edifici  ·  nastri %.2f / macch. %.2f ms"
			% [_items_cached, SimCore.belts.lanes.size(), _count_buildings(), belt_ms, mach_ms])


func _count_buildings() -> int:
	var c := 0
	for b: Variant in SimCore.world.buildings:
		if b != null:
			c += 1
	return c


func _build_selftest_text() -> String:
	var r := Database.self_test()
	var lines := PackedStringArray()

	# Rete di sicurezza per le build esportate. Godot NON importa i .json come
	# risorse: se manca il filtro `data/*.json` nel preset di esportazione, il
	# pacchetto esce senza dati e il gioco parte muto. Su un telefono non c'e'
	# console, quindi l'errore deve gridare a schermo.
	if not Database.loaded:
		lines.append("[bgcolor=#8b1a15][color=#ffffff][b]  DATI NON CARICATI  [/b][/color][/bgcolor]")
		lines.append("[color=#%s]Build esportata: aggiungi [b]data/*.json[/b] ai filtri"
			% COL_FAIL.to_html(false) + " di esportazione (SETUP_EXPORT.md §3)[/color]")
		for e in Database.errors:
			lines.append("[color=#%s]· %s[/color]" % [COL_FAIL.to_html(false), e])
		lines.append("")

	lines.append("[b]DATABASE[/b]  res://data/*.json")
	for c: Dictionary in r["checks"]:
		var ok: bool = c["ok"]
		lines.append("[color=#%s]%s[/color] %s = [b]%s[/b]"
			% [(COL_OK if ok else COL_FAIL).to_html(false), "OK" if ok else "FAIL",
			   c["label"], c["got"]])
	var failed: int = r["failed"]
	var total: int = r["total"]
	lines.append("[color=#%s][b]%d/%d — %s[/b][/color]"
		% [(COL_OK if failed == 0 else COL_FAIL).to_html(false), total - failed, total,
		   "coincide con balance_sim.py" if failed == 0 else "DISALLINEATO"])

	var counts := SimCore.world.terrain_counts()
	lines.append("")
	lines.append("[b]MONDO[/b] %dx%d · ferro %d · rame %d · acqua %d · roccia %d"
		% [SimCore.world.w, SimCore.world.h,
		   counts["iron"], counts["copper"], counts["water"], counts["rock"]])
	return "\n".join(lines)


func _on_toggle() -> void:
	_expanded = not _expanded
	_detail.visible = _expanded
	_toggle.text = "x" if _expanded else "i"
