class_name WorldState extends RefCounted
## Tutto lo stato mutabile del mondo. RefCounted, non Node: deve poter esistere
## e girare senza scene ne' rendering (TDD 00 §2) — e' cio' che rende possibili
## il calcolo offline e i test headless del bilanciamento.
##
## Lo stato spaziale sta in array paralleli, MAI in Dictionary indicizzate per
## cella: un lookup su Dictionary costa 5-10x un accesso ad array, e la
## simulazione ne fa centinaia di migliaia al secondo.

enum Terrain { EMPTY = 0, ROCK = 1, ORE_IRON = 2, ORE_COPPER = 3, WATER = 4 }

const NO_BUILDING := -1

var w: int
var h: int
var n: int

var terrain: PackedByteArray
var building_at: PackedInt32Array     ## indice in `buildings`, o NO_BUILDING
var buildings: Array = []

var core_cell: Vector2i

# --- progressione ---
var data := 0.0
var data_lifetime := 0.0
var theta_rolling := 0.0
var wave_index := 0
var wave_timer_s := 0.0
var inventory: Dictionary = {}

# --- moltiplicatori globali ---
var time_scale := 1.0                 ## 2.5 durante l'Overclock
var power_sigma := 1.0                ## soddisfazione della rete elettrica


func _init(width: int = 96, height: int = 96) -> void:
	w = width
	h = height
	n = w * h
	terrain = PackedByteArray()
	terrain.resize(n)
	terrain.fill(Terrain.EMPTY)
	building_at = PackedInt32Array()
	building_at.resize(n)
	building_at.fill(NO_BUILDING)
	core_cell = Vector2i(w / 2, h / 2)


# ================================================================== GRIGLIA ==

func cell(x: int, y: int) -> int:
	return y * w + x


func cell_v(p: Vector2i) -> int:
	return p.y * w + p.x


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


func in_bounds_v(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h


func terrain_at(x: int, y: int) -> int:
	return terrain[y * w + x] if in_bounds(x, y) else Terrain.ROCK


func is_free(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	var i := y * w + x
	return building_at[i] == NO_BUILDING and terrain[i] != Terrain.ROCK


## Valida un footprint rettangolare. Deve restare sotto i 0.1 ms: viene chiamata
## a ogni frame durante il trascinamento di costruzione (TDD 00 §4).
func can_place(origin: Vector2i, size: Vector2i, needs_patch: int = -1) -> bool:
	for dy in size.y:
		for dx in size.x:
			var x := origin.x + dx
			var y := origin.y + dy
			if not is_free(x, y):
				return false
			if needs_patch >= 0 and terrain[y * w + x] != needs_patch:
				return false
	return true


# ============================================================== INVENTARIO ==

func add_material(id: StringName, amount: float) -> void:
	inventory[id] = float(inventory.get(id, 0.0)) + amount


func take_material(id: StringName, amount: float) -> bool:
	var have := float(inventory.get(id, 0.0))
	if have < amount:
		return false
	inventory[id] = have - amount
	return true


func can_afford(cost: Dictionary) -> bool:
	for id: Variant in cost:
		if float(inventory.get(StringName(id), 0.0)) < float(cost[id]):
			return false
	return true


# ============================================================== GENERAZIONE ==

## Genera terreno deterministico da un seed. Nell'MVP la mappa e' fissa; il seed
## esiste perche' i settori successivi (post-MVP) ne useranno uno diverso.
func generate(map_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed

	terrain.fill(Terrain.EMPTY)

	# Il Core sta al centro e non deve mai essere sopra un giacimento.
	var core_half := 4
	var patches := [
		[Terrain.ORE_IRON, 4, 5.0],
		[Terrain.ORE_COPPER, 3, 4.0],
		[Terrain.WATER, 2, 6.0],
	]
	for spec: Array in patches:
		var kind := int(spec[0])
		var count := int(spec[1])
		var radius := float(spec[2])
		var placed := 0
		var attempts := 0
		while placed < count and attempts < 400:
			attempts += 1
			var cx := rng.randi_range(8, w - 9)
			var cy := rng.randi_range(8, h - 9)
			var d := Vector2i(cx, cy) - core_cell
			# non troppo vicino al Core, non troppo lontano dall'area giocabile
			if absi(d.x) < core_half + 8 and absi(d.y) < core_half + 8:
				continue
			if Vector2(d).length() > float(mini(w, h)) * 0.40:
				continue
			if not _area_is_empty(cx, cy, int(radius) + 2):
				continue
			_blob(rng, cx, cy, radius, kind)
			placed += 1

	# Qualche roccia decorativa che blocca il piazzamento, lontano dal Core.
	for _i in 40:
		var rx := rng.randi_range(2, w - 3)
		var ry := rng.randi_range(2, h - 3)
		if (Vector2i(rx, ry) - core_cell).length() < 14.0:
			continue
		if terrain[ry * w + rx] == Terrain.EMPTY:
			terrain[ry * w + rx] = Terrain.ROCK


func _area_is_empty(cx: int, cy: int, r: int) -> bool:
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if not in_bounds(x, y):
				return false
			if terrain[y * w + x] != Terrain.EMPTY:
				return false
	return true


func _blob(rng: RandomNumberGenerator, cx: int, cy: int, radius: float, kind: int) -> void:
	var r_i := int(ceil(radius))
	for y in range(cy - r_i, cy + r_i + 1):
		for x in range(cx - r_i, cx + r_i + 1):
			if not in_bounds(x, y):
				continue
			var d := Vector2(float(x - cx), float(y - cy)).length()
			# bordo irregolare: niente cerchi perfetti, sono leggibili come "finti"
			if d <= radius * rng.randf_range(0.80, 1.05):
				terrain[y * w + x] = kind


# =================================================================== DEBUG ==

func terrain_counts() -> Dictionary:
	var out := {"empty": 0, "rock": 0, "iron": 0, "copper": 0, "water": 0}
	var keys := ["empty", "rock", "iron", "copper", "water"]
	for i in n:
		out[keys[terrain[i]]] += 1
	return out
