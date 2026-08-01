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

## Sotto questo livello di zoom le linee della griglia diventano rumore visivo.
const GRID_LINE_MIN_ZOOM := 0.55

var _camera: Camera2D
var _world: WorldState


func _ready() -> void:
	_world = SimCore.world
	z_index = -100
	await get_tree().process_frame
	_camera = get_viewport().get_camera_2d()
	if _camera != null and _camera.has_signal(&"view_changed"):
		_camera.connect(&"view_changed", queue_redraw)
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
	var zoom_level := _camera.zoom.x if _camera != null else 1.0
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
