extends Control
## Pannello diagnostico dello Sprint 0.
##
## Esiste per un motivo preciso: il criterio di completamento dello Sprint 0 e'
## "sul telefono vedi la griglia e la console stampa vi(ingot_iron) = 15.625".
## Su un telefono la console NON si vede. Quindi il controllo va a schermo.
##
## Mostra anche i tre KPI prestazionali del TDD 00 §14 fin dal primo giorno:
## misurarli dallo Sprint 6 significa scoprire i problemi quando costano dieci
## volte tanto.

const FONT_SIZE := 26
const COL_OK := Color("#5fd39a")
const COL_FAIL := Color("#e8635a")
const COL_WARN := Color("#e3b341")
const COL_DIM := Color("#8a97a8")

var _margin: MarginContainer
var _perf_label: RichTextLabel
var _data_label: RichTextLabel
var _visible_panel := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_margin)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 12)
	_margin.add_child(vbox)

	_perf_label = _make_label()
	vbox.add_child(_perf_label)

	_data_label = _make_label()
	vbox.add_child(_data_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer)

	var toggle := Button.new()
	toggle.text = "Nascondi diagnostica"
	toggle.custom_minimum_size = Vector2(0, 88)   # target touch >= 88 px
	toggle.add_theme_font_size_override("font_size", FONT_SIZE)
	toggle.pressed.connect(_on_toggle)
	vbox.add_child(toggle)

	_apply_safe_area()
	get_tree().get_root().size_changed.connect(_apply_safe_area)
	_fill_selftest()


func _make_label() -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	l.add_theme_font_size_override("bold_font_size", FONT_SIZE)
	l.add_theme_color_override("default_color", COL_DIM)
	return l


## Notch su iPhone e gesture bar su Android: si rispettano allo Sprint 0, non
## alla fine. La safe area e' in pixel schermo, la UI in pixel viewport: con
## stretch "canvas_items" i due sistemi non coincidono e vanno convertiti.
func _apply_safe_area() -> void:
	if _margin == null:
		return
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.window_get_size()
	var pad := 24
	var left := pad
	var top := pad
	var right := pad
	var bottom := pad
	if screen.x > 0 and screen.y > 0 and safe.size.x > 0:
		var vp := get_viewport_rect().size
		var sx := vp.x / float(screen.x)
		var sy := vp.y / float(screen.y)
		left += int(float(safe.position.x) * sx)
		top += int(float(safe.position.y) * sy)
		right += int(float(screen.x - safe.end.x) * sx)
		bottom += int(float(screen.y - safe.end.y) * sy)
	_margin.add_theme_constant_override("margin_left", left)
	_margin.add_theme_constant_override("margin_top", top)
	_margin.add_theme_constant_override("margin_right", right)
	_margin.add_theme_constant_override("margin_bottom", bottom)


func _process(_delta: float) -> void:
	if not _visible_panel:
		return
	var fps := Engine.get_frames_per_second()
	var ms_tick := SimCore.avg_tick_usec / 1000.0
	var peak_ms := float(SimCore.peak_tick_usec) / 1000.0
	var fps_col := COL_OK if fps >= 55 else (COL_WARN if fps >= 40 else COL_FAIL)
	var tick_col := COL_OK if ms_tick < 5.0 else (COL_WARN if ms_tick < 8.0 else COL_FAIL)

	var cam := get_viewport().get_camera_2d()
	var zoom_txt := "%.2fx" % cam.zoom.x if cam != null else "-"

	_perf_label.text = ("[b]PRESTAZIONI[/b]  (target TDD 00 §14)\n"
		+ "[color=#%s]fps %d[/color]   " % [fps_col.to_html(false), fps]
		+ "[color=#%s]tick %.2f ms (picco %.2f)[/color]\n" % [tick_col.to_html(false), ms_tick, peak_ms]
		+ "sim %d tick · %.1f s · zoom %s" % [SimCore.tick_index, SimCore.sim_seconds(), zoom_txt])


func _fill_selftest() -> void:
	var r := Database.self_test()
	var lines := PackedStringArray()

	# Rete di sicurezza per le build esportate. Godot NON importa i .json come
	# risorse: se in Progetto > Esporta manca il filtro `data/*.json`, il PCK
	# esce senza dati e il gioco parte muto. Su un telefono non c'e' console,
	# quindi l'errore deve gridare a schermo.
	if not Database.loaded:
		lines.append("[bgcolor=#8b1a15][color=#ffffff][b]  DATI NON CARICATI  [/b][/color][/bgcolor]")
		lines.append("[color=#%s]Se sei in una build esportata: aggiungi[/color]" % COL_FAIL.to_html(false))
		lines.append("[color=#%s][b]data/*.json[/b] ai filtri di esportazione[/color]" % COL_FAIL.to_html(false))
		lines.append("[color=#%s](vedi docs/SETUP_EXPORT.md §3)[/color]" % COL_DIM.to_html(false))
		for e in Database.errors:
			lines.append("[color=#%s]· %s[/color]" % [COL_FAIL.to_html(false), e])
		lines.append("")

	lines.append("[b]DATABASE[/b]  res://data/*.json")
	for c: Dictionary in r["checks"]:
		var ok: bool = c["ok"]
		var col := COL_OK if ok else COL_FAIL
		var mark := "OK  " if ok else "FAIL"
		lines.append("[color=#%s]%s[/color]  %s = [b]%s[/b]"
			% [col.to_html(false), mark, c["label"], c["got"]])
	var failed: int = r["failed"]
	var total: int = r["total"]
	if failed == 0:
		lines.append("[color=#%s][b]%d/%d — i dati coincidono con balance_sim.py[/b][/color]"
			% [COL_OK.to_html(false), total, total])
	else:
		lines.append("[color=#%s][b]%d/%d FALLITI[/b][/color]"
			% [COL_FAIL.to_html(false), failed, total])

	var counts := SimCore.world.terrain_counts()
	lines.append("")
	lines.append("[b]MONDO[/b]  %d x %d celle" % [SimCore.world.w, SimCore.world.h])
	lines.append("ferro %d · rame %d · acqua %d · roccia %d"
		% [counts["iron"], counts["copper"], counts["water"], counts["rock"]])
	_data_label.text = "\n".join(lines)


func _on_toggle() -> void:
	_visible_panel = not _visible_panel
	_perf_label.visible = _visible_panel
	_data_label.visible = _visible_panel
	var b := _margin.get_child(0).get_child(3) as Button
	if b != null:
		b.text = "Nascondi diagnostica" if _visible_panel else "Mostra diagnostica"
