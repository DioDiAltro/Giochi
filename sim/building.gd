class_name Building extends RefCounted
## Un edificio piazzato. Dato puro: non e' un Node, non ha _process.
## Tutto lo stato che serve alla simulazione sta qui e viene fatto avanzare
## da MachineSystem, mai dall'edificio stesso.

enum State { IDLE, WORKING, BLOCKED }

var index := -1                       ## posizione in WorldState.buildings
var type_id: StringName = &""
var origin := Vector2i.ZERO           ## angolo alto-sinistro del footprint
var size := Vector2i.ONE
var rot := 0

# --- produzione ---
var recipe_id: StringName = &""
var state := State.IDLE
var ticks_left := 0
var progress_fp := 0
var buf_in: Dictionary = {}
var buf_out: Dictionary = {}
var buf_cap := 20

# --- I/O ---
## Celle adiacenti verso cui espellere, calcolate al piazzamento e a ogni
## modifica dei nastri vicini. Si espelle a rotazione (round robin) per non
## saturare sempre lo stesso nastro.
var out_cells: PackedInt32Array = PackedInt32Array()
var out_cursor := 0

# --- diagnostica ---
var produced_total := 0


func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in size.y:
		for dx in size.x:
			out.append(origin + Vector2i(dx, dy))
	return out


func rect() -> Rect2i:
	return Rect2i(origin, size)


func center() -> Vector2:
	return Vector2(origin) + Vector2(size) * 0.5


func buf_in_total() -> int:
	var t := 0
	for k: Variant in buf_in:
		t += int(buf_in[k])
	return t


func buf_out_total() -> int:
	var t := 0
	for k: Variant in buf_out:
		t += int(buf_out[k])
	return t


func add_in(mat: StringName, qty: int = 1) -> void:
	buf_in[mat] = int(buf_in.get(mat, 0)) + qty


func add_out(mat: StringName, qty: int = 1) -> void:
	buf_out[mat] = int(buf_out.get(mat, 0)) + qty


## Estrae un materiale qualsiasi dal buffer di uscita, o &"" se vuoto.
func pop_out() -> StringName:
	for k: Variant in buf_out:
		var q := int(buf_out[k])
		if q > 0:
			if q == 1:
				buf_out.erase(k)
			else:
				buf_out[k] = q - 1
			return StringName(k)
	return &""
