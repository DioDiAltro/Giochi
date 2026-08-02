extends Camera2D
## Camera touch: pan a un dito, pinch-zoom a due dita.
##
## Usa InputEventScreenTouch/Drag, non gli eventi mouse. Con
## input_devices/pointing/emulate_touch_from_mouse=true lo stesso codice funziona
## col mouse durante lo sviluppo su desktop: un solo percorso da mantenere.
##
## In Godot 4 `zoom` e' un moltiplicatore di ingrandimento: zoom = 2 significa
## zoom IN al doppio (opposto di Godot 3).

const ZOOM_MIN := 0.30
const ZOOM_MAX := 3.00
const WHEEL_STEP := 1.12          ## zoom da rotellina, solo per lo sviluppo

signal view_changed()

var _touches: Dictionary = {}     ## index dito -> posizione schermo
var _pinch_dist := 0.0
var _last_pos := Vector2.INF
var _last_zoom := 0.0


func _ready() -> void:
	make_current()
	var t := Database.tile_px
	position = Vector2(float(Database.grid_w) * t, float(Database.grid_h) * t) * 0.5
	zoom = Vector2(0.6, 0.6)


func _process(_delta: float) -> void:
	if position != _last_pos or zoom.x != _last_zoom:
		_last_pos = position
		_last_zoom = zoom.x
		view_changed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = t.position
		else:
			_touches.erase(t.index)
		# Al cambio del numero di dita la distanza di pinch va riazzerata,
		# altrimenti alzando un dito la vista fa un salto.
		_pinch_dist = 0.0

	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_touches[d.index] = d.position
		if _touches.size() == 1:
			# Pan: la vista segue il dito, quindi la camera va nella direzione opposta.
			position -= d.relative / zoom
			_clamp_to_map()
		elif _touches.size() >= 2:
			_handle_pinch()

	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_at(mb.position, WHEEL_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at(mb.position, 1.0 / WHEEL_STEP)


func _handle_pinch() -> void:
	var keys := _touches.keys()
	var a: Vector2 = _touches[keys[0]]
	var b: Vector2 = _touches[keys[1]]
	var dist := a.distance_to(b)
	if dist < 1.0:
		return
	if _pinch_dist > 0.0:
		zoom_at((a + b) * 0.5, dist / _pinch_dist)
	_pinch_dist = dist


## Zoom ancorato a un punto dello schermo: il punto del mondo sotto le dita
## resta sotto le dita. Senza questo il pinch "scivola" ed e' sgradevole.
func zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := screen_to_world(screen_pos)
	var z := clampf(zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2(z, z)
	position += before - screen_to_world(screen_pos)
	_clamp_to_map()


## Valida con anchor_mode = ANCHOR_MODE_DRAG_CENTER (default), rotazione 0 e
## offset 0. Calcolata a mano invece che con get_canvas_transform() perche'
## quella si aggiorna solo al frame successivo, e lo zoom la userebbe stantia.
func screen_to_world(screen_pos: Vector2) -> Vector2:
	return position + (screen_pos - get_viewport_rect().size * 0.5) / zoom


func world_to_cell(world_pos: Vector2) -> Vector2i:
	var t := float(Database.tile_px)
	return Vector2i(int(floor(world_pos.x / t)), int(floor(world_pos.y / t)))


func screen_to_cell(screen_pos: Vector2) -> Vector2i:
	return world_to_cell(screen_to_world(screen_pos))


## Tiene la camera entro un margine attorno alla mappa: senza, il primo pan
## troppo energico lascia il giocatore nel vuoto senza punti di riferimento.
func _clamp_to_map() -> void:
	var t := float(Database.tile_px)
	var margin := 12.0 * t
	position.x = clampf(position.x, -margin, float(Database.grid_w) * t + margin)
	position.y = clampf(position.y, -margin, float(Database.grid_h) * t + margin)


## Rettangolo di mondo visibile. Serve al renderer per il culling.
func visible_world_rect() -> Rect2:
	var half := get_viewport_rect().size * 0.5 / zoom
	return Rect2(position - half, half * 2.0)
