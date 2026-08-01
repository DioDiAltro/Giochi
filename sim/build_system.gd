class_name BuildSystem extends RefCounted
## Piazzamento, demolizione e annullamento.
##
## Non e' un "sistema di tick": non fa nulla per frame. Espone comandi che la UI
## invoca, e mantiene lo storico per l'ANNULLA. Vive comunque nello Strato 3
## perche' e' l'unico autorizzato a scrivere in WorldState.

## Ogni azione del giocatore genera un gruppo annullabile. Un trascinamento che
## piazza 200 nastri e' UN gruppo, non 200: annullare deve disfare il gesto, non
## l'ultima cella.
class UndoGroup extends RefCounted:
	var belts_added: PackedInt32Array = PackedInt32Array()
	var buildings_added: PackedInt32Array = PackedInt32Array()
	var refund: Dictionary = {}
	var label := ""

const UNDO_WINDOW_S := 5.0

var world: WorldState
var belts: BeltSystem
var _undo_stack: Array[UndoGroup] = []
var _undo_time := 0.0

signal changed()
signal rejected(reason: String)
signal undo_available(available: bool, label: String)


func _init(w: WorldState, b: BeltSystem) -> void:
	world = w
	belts = b


func process_ui(delta: float) -> void:
	if _undo_stack.is_empty():
		return
	_undo_time -= delta
	if _undo_time <= 0.0:
		_undo_stack.clear()
		undo_available.emit(false, "")


# ================================================================= NASTRI ===

## Instrada un percorso a L fra due celle. Prima l'asse con la delta maggiore,
## poi l'altro: il giocatore ottiene l'angolo gratis, senza doverlo disegnare.
## E' la scelta che rende la costruzione praticabile con un pollice.
static func route_l(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var d := to - from
	var horizontal_first := absi(d.x) >= absi(d.y)
	var cur := from
	path.append(cur)
	if horizontal_first:
		while cur.x != to.x:
			cur.x += signi(d.x)
			path.append(cur)
		while cur.y != to.y:
			cur.y += signi(d.y)
			path.append(cur)
	else:
		while cur.y != to.y:
			cur.y += signi(d.y)
			path.append(cur)
		while cur.x != to.x:
			cur.x += signi(d.x)
			path.append(cur)
	return path


static func dir_between(a: Vector2i, b: Vector2i) -> int:
	var d := b - a
	if d.x > 0: return 0
	if d.y > 0: return 1
	if d.x < 0: return 2
	return 3


## Quante celle del percorso sono effettivamente costruibili, in ordine.
## Si ferma al primo ostacolo: cosi' il ghost mostra sempre la verita'.
func plan_belt(path: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for p in path:
		if not world.in_bounds_v(p):
			break
		var c := world.cell_v(p)
		# Ripassare sopra un nastro esistente e' consentito: lo ri-orienta.
		var occupied := world.building_at[c] != WorldState.NO_BUILDING
		var blocked := world.terrain[c] == WorldState.Terrain.ROCK \
			or world.terrain[c] == WorldState.Terrain.WATER
		if occupied or blocked:
			break
		out.append(p)
	return out


func belt_cost(count: int) -> Dictionary:
	var per: Dictionary = Database.building(&"belt").get("cost", {"ingot_iron": 1})
	var out: Dictionary = {}
	for k: Variant in per:
		out[StringName(k)] = int(per[k]) * count
	return out


## Quante celle del percorso puoi permetterti. Se i materiali finiscono a meta',
## si costruisce il tratto che parte dalla sorgente invece di rifiutare tutto:
## interrompere una costruzione con un errore e' la cosa che rende sgradevoli i
## factory game su mobile.
func affordable_count(planned: int) -> int:
	if planned <= 0:
		return 0
	var per: Dictionary = Database.building(&"belt").get("cost", {"ingot_iron": 1})
	var limit := planned
	for k: Variant in per:
		var unit := int(per[k])
		if unit <= 0:
			continue
		var have := int(world.inventory.get(StringName(k), 0))
		limit = mini(limit, have / unit)
	return maxi(0, limit)


func build_belt_path(path: Array[Vector2i]) -> int:
	var planned := plan_belt(path)
	var count := affordable_count(planned.size())
	if count <= 0:
		rejected.emit("Materiali insufficienti")
		return 0

	var g := UndoGroup.new()
	g.label = "%d nastri" % count
	for i in count:
		var p := planned[i]
		var c := world.cell_v(p)
		# La direzione punta alla cella successiva; l'ultima eredita la precedente.
		var dir := 0
		if i + 1 < planned.size():
			dir = dir_between(p, planned[i + 1])
		elif i > 0:
			dir = dir_between(planned[i - 1], p)
		if world.belt_dir[c] == WorldState.NO_BELT:
			g.belts_added.append(c)
		world.belt_dir[c] = dir
		world.belt_speed[c] = 0

	var cost := belt_cost(count)
	for k: Variant in cost:
		world.take_material(StringName(k), float(cost[k]))
	g.refund = cost

	_push_undo(g)
	belts.mark_dirty()
	_refresh_outputs_near(planned)
	changed.emit()
	return count


# =============================================================== EDIFICI ===

func can_place_building(type_id: StringName, origin: Vector2i) -> bool:
	var def := Database.building(type_id)
	if def.is_empty():
		return false
	var size := Database.building_size(type_id)
	var patch := -1
	if bool(def.get("must_be_on_patch", false)):
		patch = _patch_for(type_id)
	return world.can_place(origin, size, patch)


func _patch_for(type_id: StringName) -> int:
	match type_id:
		&"drill": return -2      # -2 = "un giacimento qualsiasi", gestito sotto
		&"pump": return WorldState.Terrain.WATER
	return -1


func place_building(type_id: StringName, origin: Vector2i, rot: int = 0) -> int:
	var def := Database.building(type_id)
	if def.is_empty():
		rejected.emit("Edificio sconosciuto")
		return -1
	var size := Database.building_size(type_id)

	# La Trivella accetta qualsiasi giacimento, ma tutte le sue celle devono
	# stare sullo stesso: mezza trivella sul ferro e mezza sul rame non ha senso.
	var need_patch := bool(def.get("must_be_on_patch", false))
	var patch := -1
	if need_patch:
		if not world.in_bounds_v(origin):
			rejected.emit("Fuori mappa")
			return -1
		patch = world.terrain[world.cell_v(origin)]
		if patch == WorldState.Terrain.EMPTY or patch == WorldState.Terrain.ROCK:
			rejected.emit("Va posizionato su un giacimento")
			return -1

	if not world.can_place(origin, size, patch):
		rejected.emit("Spazio occupato" if not need_patch else "Serve un giacimento libero")
		return -1

	var cost: Dictionary = def.get("cost", {})
	if not world.can_afford(cost):
		rejected.emit("Materiali insufficienti")
		return -1

	var b := Building.new()
	b.type_id = type_id
	b.origin = origin
	b.size = size
	b.rot = rot
	b.buf_cap = int(def.get("buffer", 20))
	if type_id == &"storage":
		b.buf_cap = int(def.get("capacity_items", 2000))
	b.recipe_id = _default_recipe(type_id, patch)
	b.index = world.buildings.size()
	world.buildings.append(b)

	for p in b.cells():
		world.building_at[world.cell_v(p)] = b.index

	for k: Variant in cost:
		world.take_material(StringName(k), float(cost[k]))

	var g := UndoGroup.new()
	g.label = String(def.get("name", String(type_id)))
	g.buildings_added.append(b.index)
	g.refund = cost
	_push_undo(g)

	_refresh_building_outputs(b)
	changed.emit()
	return b.index


func _default_recipe(type_id: StringName, patch: int) -> StringName:
	if type_id == &"drill":
		return &"drill_copper" if patch == WorldState.Terrain.ORE_COPPER else &"drill_iron"
	return &""


# ============================================================ DEMOLIZIONE ===

func demolish(p: Vector2i) -> bool:
	if not world.in_bounds_v(p):
		return false
	var c := world.cell_v(p)

	if world.belt_dir[c] != WorldState.NO_BELT:
		world.belt_dir[c] = WorldState.NO_BELT
		# Gli item che erano su quella cella spariscono con essa.
		for s in WorldState.SLOTS_PER_TILE:
			world.belt_slots[c * WorldState.SLOTS_PER_TILE + s] = 0
		var back := belt_cost(1)
		for k: Variant in back:
			world.add_material(StringName(k), float(back[k]))
		belts.mark_dirty()
		changed.emit()
		return true

	var bi := world.building_at[c]
	if bi != WorldState.NO_BUILDING:
		var b: Building = world.buildings[bi]
		for cellp in b.cells():
			world.building_at[world.cell_v(cellp)] = WorldState.NO_BUILDING
		var cost: Dictionary = Database.building(b.type_id).get("cost", {})
		for k: Variant in cost:
			world.add_material(StringName(k), float(cost[k]))
		world.buildings[bi] = null
		changed.emit()
		return true

	return false


# ================================================================= ANNULLA ===

func _push_undo(g: UndoGroup) -> void:
	_undo_stack.append(g)
	_undo_time = UNDO_WINDOW_S
	undo_available.emit(true, g.label)


func undo() -> bool:
	if _undo_stack.is_empty():
		return false
	var g: UndoGroup = _undo_stack.pop_back()

	for c in g.belts_added:
		world.belt_dir[c] = WorldState.NO_BELT
		for s in WorldState.SLOTS_PER_TILE:
			world.belt_slots[c * WorldState.SLOTS_PER_TILE + s] = 0
	for bi in g.buildings_added:
		var b: Building = world.buildings[bi]
		if b == null:
			continue
		for p in b.cells():
			world.building_at[world.cell_v(p)] = WorldState.NO_BUILDING
		world.buildings[bi] = null

	for k: Variant in g.refund:
		world.add_material(StringName(k), float(g.refund[k]))

	belts.mark_dirty()
	undo_available.emit(not _undo_stack.is_empty(),
		_undo_stack[-1].label if not _undo_stack.is_empty() else "")
	changed.emit()
	return true


# ============================================================ COLLEGAMENTI ===

## Ricalcola verso quali celle un edificio puo' espellere.
##
## SCELTA DI DESIGN MOBILE: una macchina espelle in QUALSIASI nastro adiacente
## che si allontani da lei, invece che da una porta fissa da orientare a mano.
## Ruotare con precisione una trivella su un telefono e' esattamente il tipo di
## micro-gestione che il GDD vieta.
func _refresh_building_outputs(b: Building) -> void:
	var outs := PackedInt32Array()
	var r := b.rect()
	for p in b.cells():
		for dir in 4:
			var np: Vector2i = p + WorldState.DIR_VEC[dir]
			if r.has_point(np):
				continue                       # cella interna all'edificio
			if not world.in_bounds_v(np):
				continue
			var nc := world.cell_v(np)
			if world.belt_dir[nc] == WorldState.NO_BELT:
				continue
			# Il nastro deve allontanarsi dall'edificio, non puntarci dentro.
			var target: Vector2i = np + WorldState.DIR_VEC[world.belt_dir[nc]]
			if r.has_point(target):
				continue
			if not outs.has(nc):
				outs.append(nc)
	b.out_cells = outs
	b.out_cursor = 0


func _refresh_outputs_near(_path: Array[Vector2i]) -> void:
	# Con poche centinaia di edifici un ricalcolo completo costa meno del codice
	# per farlo in modo mirato, e gira solo quando il giocatore costruisce.
	for b: Variant in world.buildings:
		if b != null:
			_refresh_building_outputs(b)


func refresh_all_outputs() -> void:
	_refresh_outputs_near([])
