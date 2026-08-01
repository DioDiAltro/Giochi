extends Node2D
## Anteprima di costruzione e gestione del gesto di trascinamento.
##
## E' il sistema che decide se il gioco e' piacevole su un telefono. Regole,
## tutte derivate dal TDD 00 §13:
##   - snap-to-grid marcato: si prende la cella piu' vicina, niente precisione
##   - percorso auto-instradato a L: l'angolo si ottiene gratis
##   - badge del costo spostato 60 px SOPRA il dito, mai sotto il polpastrello
##   - se i materiali finiscono a meta', si costruisce il tratto che ci si puo'
##     permettere invece di rifiutare tutto

const COL_OK := Color("#5fd39a")
const COL_POOR := Color("#e3b341")
const COL_BAD := Color("#e8635a")
const BADGE_OFFSET := Vector2(0, -60)

enum Tool { NONE, BELT, DRILL, STORAGE, DEMOLISH }

var tool: int = Tool.NONE

var _camera: Camera2D
var _world: WorldState
var _dragging := false
var _drag_finger := -1
var _touch_count := 0
var _has_hover := false
var _from := Vector2i.ZERO
var _to := Vector2i.ZERO
var _finger_screen := Vector2.ZERO
var _planned: Array[Vector2i] = []
var _affordable := 0
var _font: Font

signal tool_changed(t: int)


func _ready() -> void:
	_world = SimCore.world
	z_index = 50
	_font = ThemeDB.fallback_font
	await get_tree().process_frame
	_camera = get_viewport().get_camera_2d()


func set_tool(t: int) -> void:
	tool = t
	_dragging = false
	_planned.clear()
	tool_changed.emit(t)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if tool == Tool.NONE or _camera == null:
		return

	# NOTA: i tocchi NON vengono consumati, solo i trascinamenti a un dito.
	# Cosi' la camera continua a contare le dita e il pinch resta funzionante
	# anche con uno strumento selezionato. Regola risultante, la stessa dei
	# factory game mobile che funzionano: UN DITO COSTRUISCE, DUE MUOVONO.
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			_touch_count += 1
			if _touch_count == 1:
				_dragging = true
				_drag_finger = e.index
				_finger_screen = e.position
				_has_hover = true
				_from = _cell_at(e.position)
				_to = _from
				_replan()
			else:
				# E' arrivato un secondo dito: il gesto e' una manipolazione
				# della vista, non una costruzione. Si annulla senza costruire.
				_cancel_drag()
		else:
			_touch_count = maxi(0, _touch_count - 1)
			if e.index == _drag_finger and _dragging:
				_commit()
				_dragging = false
				_drag_finger = -1
				queue_redraw()

	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_finger_screen = d.position
		_has_hover = true
		if not _dragging or d.index != _drag_finger or _touch_count > 1:
			return
		_to = _cell_at(d.position)
		_replan()
		get_viewport().set_input_as_handled()


func _cancel_drag() -> void:
	_dragging = false
	_drag_finger = -1
	_planned.clear()
	queue_redraw()


func _cell_at(screen_pos: Vector2) -> Vector2i:
	return _camera.call(&"screen_to_cell", screen_pos)


func _replan() -> void:
	match tool:
		Tool.BELT, Tool.DEMOLISH:
			var path := BuildSystem.route_l(_from, _to)
			if tool == Tool.BELT:
				_planned = SimCore.build.plan_belt(path)
				_affordable = SimCore.build.affordable_count(_planned.size())
			else:
				_planned = path
				_affordable = path.size()
		_:
			_planned = [_to]
			_affordable = 1 if SimCore.build.can_place_building(_type_of_tool(), _to) else 0
	queue_redraw()


func _type_of_tool() -> StringName:
	match tool:
		Tool.DRILL: return &"drill"
		Tool.STORAGE: return &"storage"
	return &""


func _commit() -> void:
	if _planned.is_empty():
		return
	match tool:
		Tool.BELT:
			SimCore.build.build_belt_path(_planned)
		Tool.DEMOLISH:
			for p in _planned:
				SimCore.build.demolish(p)
		Tool.DRILL, Tool.STORAGE:
			SimCore.build.place_building(_type_of_tool(), _to)
	_planned.clear()


func _draw() -> void:
	if tool == Tool.NONE:
		return
	var t := float(Database.tile_px)

	# Cella sotto il dito, visibile anche senza trascinamento: da' al giocatore
	# un riferimento di dove "cadra'" il tocco prima che lo faccia.
	if not _dragging:
		if not _has_hover:
			return
		var c := _cell_at(_finger_screen)
		var size := Vector2i.ONE if tool in [Tool.BELT, Tool.DEMOLISH] \
			else Database.building_size(_type_of_tool())
		draw_rect(Rect2(Vector2(c) * t, Vector2(size) * t), Color(COL_OK, 0.20), true)
		return

	if tool == Tool.DEMOLISH:
		for p in _planned:
			draw_rect(Rect2(Vector2(p) * t, Vector2(t, t)), Color(COL_BAD, 0.35), true)
	elif tool == Tool.BELT:
		for i in _planned.size():
			var p := _planned[i]
			var col := COL_OK if i < _affordable else COL_POOR
			draw_rect(Rect2(Vector2(p) * t, Vector2(t, t)), Color(col, 0.30), true)
			# Freccia di direzione: il giocatore deve vedere il verso PRIMA di
			# rilasciare, non scoprirlo dopo.
			if i + 1 < _planned.size():
				var dir := BuildSystem.dir_between(p, _planned[i + 1])
				_draw_arrow(Vector2(p) * t + Vector2(t, t) * 0.5,
					Vector2(WorldState.DIR_VEC[dir]), t, col)
	else:
		var size := Database.building_size(_type_of_tool())
		var col := COL_OK if _affordable > 0 else COL_BAD
		draw_rect(Rect2(Vector2(_to) * t, Vector2(size) * t), Color(col, 0.30), true)
		draw_rect(Rect2(Vector2(_to) * t, Vector2(size) * t), col, false, 2.0)

	_draw_badge()


func _draw_arrow(center: Vector2, dir: Vector2, t: float, col: Color) -> void:
	var half := t * 0.22
	var tip := center + dir * half
	var back := center - dir * half
	var perp := Vector2(-dir.y, dir.x) * half * 0.6
	draw_line(back, tip, col, 2.0)
	draw_line(tip, tip - dir * half * 0.7 + perp, col, 2.0)
	draw_line(tip, tip - dir * half * 0.7 - perp, col, 2.0)


func _draw_badge() -> void:
	if _camera == null:
		return
	# Il badge sta 60 px SOPRA il dito: sotto il polpastrello sarebbe invisibile,
	# ed e' l'errore che rende sgradevoli i factory game su mobile.
	var world_pos: Vector2 = _camera.call(&"screen_to_world", _finger_screen + BADGE_OFFSET)
	var zoom: float = _camera.zoom.x
	var text := ""
	match tool:
		Tool.BELT:
			var n := _planned.size()
			text = "%d nastri" % _affordable
			if _affordable < n:
				text += "  (%d non pagabili)" % (n - _affordable)
		Tool.DEMOLISH:
			text = "%d da demolire" % _planned.size()
		_:
			text = "Non piazzabile" if _affordable == 0 else String(
				Database.building(_type_of_tool()).get("name", ""))
	if text.is_empty():
		return

	var size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	var pad := Vector2(8, 5) / zoom
	var box_size := size / zoom + pad * 2.0
	var origin := world_pos - Vector2(box_size.x * 0.5, box_size.y)
	draw_rect(Rect2(origin, box_size), Color(0, 0, 0, 0.75), true)
	draw_string(_font, origin + Vector2(pad.x, box_size.y - pad.y - 2.0 / zoom),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(16.0 / zoom), Color.WHITE)
