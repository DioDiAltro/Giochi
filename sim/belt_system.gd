class_name BeltSystem extends RefCounted
## Il sistema che decide se il gioco gira a 60 fps su un Android di fascia media.
##
## DUE REGOLE NON NEGOZIABILI (TDD 00 §5):
##   1. Un item su un nastro non e' mai un Node. E' un byte in un array.
##   2. Tutti gli item del mondo si disegnano con una sola draw call.
##
## STRUTTURA
## Gli slot vivono in un unico array globale `world.belt_slots`, indicizzato
## `cella * 3 + slot`. Le CORSIE non possiedono gli item: sono solo un indice di
## ordinamento sopra quell'array. Conseguenza pratica enorme: ricostruire le
## corsie quando il giocatore piazza un nastro NON tocca gli item, che restano
## esattamente dove sono. Niente snapshot, niente ripristino, niente item persi.
##
## COSTO
## _step() e' O(slot della corsia) ma NON gira a 20 Hz: gira alla velocita' del
## nastro (6 slot/s per il nastro base). Misurato con tools/test_packed.gd:
## ~0.28 ms per tick su 4500 slot, cioe' il 5.6% del budget di 5 ms.

const FP_ONE := 256
const SLOTS := 3                       ## slot per cella

## Velocita' in slot/tick, in virgola fissa. Nastro base: 6 slot/s a 20 Hz
## = 0.3 slot/tick = 77/256.
const SPEED_FP := [77, 115]            ## [nastro base, nastro veloce]

var world: WorldState
var lanes: Array[BeltLane] = []
var _dirty := true

# --- diagnostica ---
var last_usec := 0
var items_on_belts := 0


func _init(w: WorldState) -> void:
	world = w


func mark_dirty() -> void:
	_dirty = true


func tick(_tick_index: int) -> void:
	var t0 := Time.get_ticks_usec()
	if _dirty:
		rebuild_lanes()
		_dirty = false

	# Alias locale: verificato da tools/test_packed.gd che condivide il buffer
	# invece di copiarlo, ed e' 2x piu' veloce dell'accesso via membro.
	# Se un aggiornamento di Godot cambiasse questa semantica il test lo
	# segnalerebbe subito, ed e' l'unico motivo per cui quel test esiste.
	var slots := world.belt_slots

	for lane in lanes:
		lane.accum += lane.speed_fp
		while lane.accum >= FP_ONE:
			lane.accum -= FP_ONE
			_step(lane, slots)

	last_usec = Time.get_ticks_usec() - t0


func _step(lane: BeltLane, slots: PackedByteArray) -> void:
	var idx := lane.slot_idx
	var last := idx.size() - 1
	if last < 0:
		return

	# 1. La testa prova a uscire. Se il destinatario rifiuta, la corsia ingorga
	#    e NESSUN item si muove: e' corretto e costa O(1).
	var head := idx[last]
	if slots[head] != 0:
		if not _try_push(lane.out_cell, slots[head] - 1):
			return
		slots[head] = 0

	# 2. Tutti gli altri avanzano di uno slot. Scansione dalla testa alla coda:
	#    cosi' ogni item si sposta al massimo una volta per step.
	for i in range(last, 0, -1):
		var a := idx[i]
		var b := idx[i - 1]
		if slots[a] == 0 and slots[b] != 0:
			slots[a] = slots[b]
			slots[b] = 0


## Consegna un materiale alla cella indicata. Ritorna false se non accetta.
func _try_push(cell: int, mat_id: int) -> bool:
	if cell < 0:
		return false
	# Nastro: entra nello slot 0 della cella.
	if world.belt_dir[cell] != WorldState.NO_BELT:
		var s := cell * SLOTS
		if world.belt_slots[s] == 0:
			world.belt_slots[s] = mat_id + 1
			return true
		return false
	# Edificio: finisce nel buffer di ingresso, se c'e' spazio.
	var bi := world.building_at[cell]
	if bi != WorldState.NO_BUILDING:
		var b: Building = world.buildings[bi]
		if b != null and b.buf_in_total() < b.buf_cap:
			b.add_in(world.material_id_to_name(mat_id))
			return true
	return false


## Inserisce un materiale in coda a una cella di nastro. Usato dalle macchine.
func try_insert(cell: int, mat: StringName) -> bool:
	if cell < 0 or world.belt_dir[cell] == WorldState.NO_BELT:
		return false
	var s := cell * SLOTS
	if world.belt_slots[s] != 0:
		return false
	world.belt_slots[s] = world.material_name_to_id(mat) + 1
	return true


# ============================================================ COSTRUZIONE ===
## Ricostruisce TUTTE le corsie da zero.
##
## Scelta deliberata: niente logica incrementale di divisione/unione. Gira solo
## quando il giocatore modifica un nastro (azione umana, poche volte al secondo
## nel caso peggiore), mai per tick. Elimina l'80% della complessita' del
## sistema a costo zero sul frame rate, e siccome gli item stanno nell'array
## globale non ne perde nemmeno uno.
func rebuild_lanes() -> void:
	lanes.clear()
	var n := world.n
	var dirs := world.belt_dir

	# 1. Quanti nastri puntano dentro ciascuna cella.
	var in_deg := PackedByteArray()
	in_deg.resize(n)
	for c in n:
		var d := dirs[c]
		if d == WorldState.NO_BELT:
			continue
		var nxt := world.neighbor(c, d)
		if nxt >= 0 and dirs[nxt] != WorldState.NO_BELT:
			in_deg[nxt] = mini(255, in_deg[nxt] + 1)

	var visited := PackedByteArray()
	visited.resize(n)

	# 2. Le corsie partono dove la catena non e' ambigua: nessun predecessore,
	#    oppure piu' di uno (un innesto deve iniziare una corsia nuova, altrimenti
	#    l'ordine di avanzamento non sarebbe ben definito).
	for c in n:
		if dirs[c] == WorldState.NO_BELT or visited[c] == 1:
			continue
		if in_deg[c] == 1:
			continue
		_walk_lane(c, visited)

	# 3. Quel che resta sono anelli chiusi (tutti con in_deg 1): si parte da una
	#    cella arbitraria. Senza questo passaggio un nastro ad anello smetterebbe
	#    di funzionare, ed e' una cosa che i giocatori costruiscono spesso.
	for c in n:
		if dirs[c] != WorldState.NO_BELT and visited[c] == 0:
			_walk_lane(c, visited)


func _walk_lane(start: int, visited: PackedByteArray) -> void:
	var tiles := PackedInt32Array()
	var c := start
	var guard := 0
	while c >= 0 and world.belt_dir[c] != WorldState.NO_BELT and visited[c] == 0:
		visited[c] = 1
		tiles.append(c)
		guard += 1
		if guard > world.n:
			break                                   # cintura di sicurezza
		var nxt := world.neighbor(c, world.belt_dir[c])
		if nxt < 0 or world.belt_dir[nxt] == WorldState.NO_BELT:
			c = -1
			break
		# Un innesto interrompe la corsia: la cella successiva ne inizia un'altra.
		if visited[nxt] == 1:
			break
		c = nxt

	if tiles.is_empty():
		return

	var lane := BeltLane.new()
	lane.tiles = tiles
	# Mappa posizione-nella-corsia -> indice globale nello slot array.
	# Precalcolata per evitare una divisione e un modulo a ogni accesso.
	var si := PackedInt32Array()
	si.resize(tiles.size() * SLOTS)
	var k := 0
	for t in tiles:
		for s in SLOTS:
			si[k] = t * SLOTS + s
			k += 1
	lane.slot_idx = si

	var last_tile := tiles[tiles.size() - 1]
	lane.out_cell = world.neighbor(last_tile, world.belt_dir[last_tile])
	lane.speed_fp = SPEED_FP[world.belt_speed[last_tile]]
	lanes.append(lane)


# ============================================================ DIAGNOSTICA ===
func count_items() -> int:
	var c := 0
	for i in world.belt_slots.size():
		if world.belt_slots[i] != 0:
			c += 1
	items_on_belts = c
	return c


func total_slots() -> int:
	var t := 0
	for lane in lanes:
		t += lane.slot_idx.size()
	return t
