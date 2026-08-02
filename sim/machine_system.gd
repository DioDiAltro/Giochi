class_name MachineSystem extends RefCounted
## Macchina a stati a 3 stati guidata da un contatore di tick.
## Nessun timer, nessun await, nessuna coroutine: tutto avanza dentro il tick
## di SimCore, quindi il calcolo offline potra' riusare esattamente questa logica.
##
## SPRINT 1: solo Trivella (sorgente) e Silo (pozzo), il minimo per vedere gli
## item scorrere e misurare le prestazioni.
## SPRINT 2: la stessa funzione tick_machine() gestira' Trituratore, Purificatore
## e Fornace — cambiano le ricette, non il motore.

var world: WorldState
var belts: BeltSystem

var last_usec := 0


func _init(w: WorldState, b: BeltSystem) -> void:
	world = w
	belts = b


func tick(_tick_index: int) -> void:
	var t0 := Time.get_ticks_usec()
	for b: Variant in world.buildings:
		if b == null:
			continue
		var m: Building = b
		match m.type_id:
			&"drill": _tick_producer(m)
			&"storage": _tick_storage(m)
	last_usec = Time.get_ticks_usec() - t0


func _tick_producer(b: Building) -> void:
	var rec := Database.recipe(b.recipe_id)
	if rec.is_empty():
		return

	match b.state:
		Building.State.IDLE:
			b.ticks_left = Database.recipe_ticks(b.recipe_id)
			b.state = Building.State.WORKING

		Building.State.WORKING:
			# sigma = soddisfazione della rete elettrica. In Sprint 1 vale 1.0:
			# il PowerSystem arriva nello Sprint 3. Il brownout NON fermera' le
			# macchine, le rallentera' — e' gia' previsto qui.
			b.progress_fp += int(world.power_sigma * 256.0)
			while b.progress_fp >= 256 and b.ticks_left > 0:
				b.progress_fp -= 256
				b.ticks_left -= 1
			if b.ticks_left <= 0:
				var outs: Dictionary = rec.get("out", {})
				for k: Variant in outs:
					b.add_out(StringName(k), int(outs[k]))
				b.state = Building.State.BLOCKED

		Building.State.BLOCKED:
			# Lo stato BLOCKED esiste perche' una macchina con piu' output (il
			# Purificatore fa prodotto + fanghiglia) non deve poter espellere
			# meta' risultato. O escono tutti, o il ciclo resta trattenuto.
			if _eject_all(b):
				b.state = Building.State.IDLE


## Espelle il buffer di uscita sui nastri adiacenti, a rotazione.
## Ritorna true solo se il buffer si e' svuotato del tutto.
func _eject_all(b: Building) -> bool:
	if b.out_cells.is_empty():
		return false
	var guard := b.out_cells.size() * 4
	while b.buf_out_total() > 0 and guard > 0:
		guard -= 1
		var mat := b.pop_out()
		if mat == &"":
			break
		var placed := false
		for _i in b.out_cells.size():
			var cell := b.out_cells[b.out_cursor]
			b.out_cursor = (b.out_cursor + 1) % b.out_cells.size()
			if belts.try_insert(cell, mat):
				placed = true
				b.produced_total += 1
				break
		if not placed:
			b.add_out(mat)          # rimettilo in buffer, riproveremo al prossimo tick
			return false
	return b.buf_out_total() == 0


## Il Silo assorbe tutto quello che gli arriva e lo versa nell'inventario globale.
func _tick_storage(b: Building) -> void:
	if b.buf_in.is_empty():
		return
	for k: Variant in b.buf_in:
		world.add_material(StringName(k), float(b.buf_in[k]))
	b.buf_in.clear()
