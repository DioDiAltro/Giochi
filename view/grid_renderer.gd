extends Node2D
## Disegna la griglia e il terreno.
##
## SPRINT 0: _draw() con culling sul rettangolo visibile. Nessun asset richiesto,
## quindi il progetto gira prima che esista un solo pixel di grafica.
##
## SPRINT 1: sostituito da TileMapLayer + atlas unico (TDD 00 §2). Il contratto
## pubblico di questo nodo — leggere WorldState e non scriverci mai — non cambia.

const COL_BG := Color("#12161c")
const COL_GRID := Color("#1e2733")
const COL_GRID_MAJOR := Color("#2b3a4d")
const COL_ROCK := Color("#39404a")
const COL_IRON := Color("#7a6a5a")
const COL_COPPER := Color("#8a6242")
const COL_WATER := Color("#2f5f9e")
const COL_CORE := Color("#39d3a8")
const COL_BELT := Color("#4a5464")
const COL_BELT_DIR := Color("#8fa2ba")
const COL_OK := Color("#5fd39a")
const COL_WARN := Color("#e3b341")


func _building_color(type_id: StringName) -> Color:
	match type_id:
		&"drill": return Color("#6b5a8a")
		&"storage": return Color("#4a6b8a")
		&"crusher": return Color("#8a5a4a")
	return Color("#5a5a5a")


func _arrow(center: Vector2, dir: Vector2, t: float, col: Color) -> void:
	var half := t * 0.20
	var tip := center + dir * half
	var perp := Vector2(-dir.y, dir.x) * half * 0.55
	draw_line(center - dir * half, tip, col, 1.5)
	draw_line(tip, tip - dir * half * 0.8 + perp, col, 1.5)
	draw_line(tip, tip - dir * half * 0.8 - perp, col, 1.5)

## Sotto questo livello di zoom le linee della griglia diventano rumore visivo.
const GRID_LINE_MIN_ZOOM := 0.55

## Ridisegnare ogni frame significherebbe migliaia di draw_rect al secondo su
## mobile. Si ridisegna solo quando serve: la vista cambia, il giocatore
## costruisce, oppure ogni STATUS_REDRAW_FRAMES per animare gli indicatori di
## stato delle macchine. 6 ridisegni al secondo invece di 60.
const STATUS_REDRAW_FRAMES := 10

var _camera: Camera2D
var _world: WorldState
var _frames := 0


func _ready() -> void:
	_world = SimCore.world
	z_index = -100
	SimCore.build.changed.connect(queue_redraw)
	await get_tree().process_frame
	_camera = get_viewport().get_camera_2d()
	if _camera != null and _camera.has_signal(&"view_changed"):
		_camera.connect(&"view_changed", queue_redraw)
	queue_redraw()


func _process(_delta: float) -> void:
	_frames += 1
	if _frames % STATUS_REDRAW_FRAMES == 0:
		queue_redraw()


func _draw() -> void:
	if _world == null:
		return
	var t := float(Database.tile_px)
	var map_rect := Rect2(Vector2.ZERO, Vector2(float(_world.w), float(_world.h)) * t)
	draw_rect(map_rect, COL_BG, true)

	var view := _visible_rect()
	# Culling: non disegniamo mai piu' delle celle effettivamente inquadrate.
	var x0 := maxi(0, int(floor(view.position.x / t)))
	var y0 := maxi(0, int(floor(view.position.y / t)))
	var x1 := mini(_world.w - 1, int(ceil(view.end.x / t)))
	var y1 := mini(_world.h - 1, int(ceil(view.end.y / t)))
	if x1 < x0 or y1 < y0:
		return

	# --- terreno ---
	for y in range(y0, y1 + 1):
		var row := y * _world.w
		for x in range(x0, x1 + 1):
			var kind := _world.terrain[row + x]
			if kind == WorldState.Terrain.EMPTY:
				continue
			var c := COL_ROCK
			match kind:
				WorldState.Terrain.ORE_IRON: c = COL_IRON
				WorldState.Terrain.ORE_COPPER: c = COL_COPPER
				WorldState.Terrain.WATER: c = COL_WATER
			draw_rect(Rect2(Vector2(float(x), float(y)) * t, Vector2(t, t)), c, true)

	# --- griglia ---
	var zoom_level: float = _camera.zoom.x if _camera != null else 1.0
	if zoom_level >= GRID_LINE_MIN_ZOOM:
		var width := 1.0 / zoom_level
		for x in range(x0, x1 + 2):
			var col := COL_GRID_MAJOR if x % 8 == 0 else COL_GRID
			draw_line(Vector2(float(x) * t, float(y0) * t),
					Vector2(float(x) * t, float(y1 + 1) * t), col, width)
		for y in range(y0, y1 + 2):
			var col := COL_GRID_MAJOR if y % 8 == 0 else COL_GRID
			draw_line(Vector2(float(x0) * t, float(y) * t),
					Vector2(float(x1 + 1) * t, float(y) * t), col, width)

	# --- nastri ---
	# Disegnati come corpo + freccia. Il verso DEVE essere leggibile a colpo
	# d'occhio: un nastro di cui non capisci la direzione e' un nastro che
	# ricostruirai tre volte.
	for y in range(y0, y1 + 1):
		var brow := y * _world.w
		for x in range(x0, x1 + 1):
			var c := brow + x
			var d := _world.belt_dir[c]
			if d == WorldState.NO_BELT:
				continue
			var o := Vector2(float(x), float(y)) * t
			draw_rect(Rect2(o + Vector2(t, t) * 0.18, Vector2(t, t) * 0.64), COL_BELT, true)
			if zoom_level >= 0.45:
				_arrow(o + Vector2(t, t) * 0.5, Vector2(WorldState.DIR_VEC[d]), t, COL_BELT_DIR)

	# --- edifici ---
	for bv: Variant in _world.buildings:
		if bv == null:
			continue
		var b: Building = bv
		var r := Rect2(Vector2(b.origin) * t, Vector2(b.size) * t)
		if not view.intersects(r):
			continue
		draw_rect(r, _building_color(b.type_id), true)
		draw_rect(r, COL_GRID_MAJOR, false, 2.0 / maxf(zoom_level, 0.01))
		# Pallino di stato: verde = sta lavorando, giallo = output bloccato.
		if b.type_id == &"drill":
			var col := COL_OK if b.state != Building.State.BLOCKED else COL_WARN
			draw_circle(r.position + Vector2(t, t) * 0.28, t * 0.12, col)

	# --- Core ---
	var cs := float(Database.core_size)
	var core_origin := Vector2(_world.core_cell - Vector2i(int(cs) / 2, int(cs) / 2)) * t
	draw_rect(Rect2(core_origin, Vector2(cs, cs) * t), COL_CORE, false, 3.0 / maxf(zoom_level, 0.01))
	draw_rect(Rect2(core_origin, Vector2(cs, cs) * t), Color(COL_CORE, 0.15), true)

	# --- bordo mappa ---
	draw_rect(map_rect, COL_GRID_MAJOR, false, 2.0 / maxf(zoom_level, 0.01))


func _visible_rect() -> Rect2:
	if _camera != null and _camera.has_method(&"visible_world_rect"):
		return _camera.call(&"visible_world_rect")
	return Rect2(Vector2.ZERO, Vector2(float(_world.w), float(_world.h)) * float(Database.tile_px))
