extends Node
## Carica e indicizza tutti i dati di bilanciamento da res://data/*.json.
##
## REGOLA OPERATIVA NUMERO UNO (TDD 00 §0):
## nessun numero di bilanciamento viene scritto a mano in GDScript.
## Se un valore ti serve e non e' qui dentro, va aggiunto ai JSON — non al codice.
##
## Il Valore Industriale NON e' salvato nei file: e' derivato da base_value e
## refinement_tier. Duplicarlo significherebbe poterlo desincronizzare.

const DATA_DIR := "res://data/"

# ------------------------------------------------------------------ tuning ---
var lambda_vi := 2.5          ## base esponenziale del VI:  VI = base * lambda^R
var beta_ammo := 1.585        ## esponente danno munizioni: M  = (R+1)^beta
var tick_hz := 20
var tick_seconds := 0.05
var slots_per_tile := 3
var grid_w := 96
var grid_h := 96
var tile_px := 32
var core_size := 3
var server_data_per_vi := 1.0
var kappa_combat_data := 0.20

# --------------------------------------------------------------- contenuti ---
var tuning: Dictionary = {}
var materials: Dictionary = {}      ## id -> Dictionary
var fluids: Dictionary = {}
var recipes: Dictionary = {}
var buildings: Dictionary = {}
var research: Dictionary = {}
var enemies: Dictionary = {}
var wave_composition: Array = []

# ------------------------------------------------------------------- cache ---
# vi() e tier() vengono chiamate centinaia di migliaia di volte al secondo dalla
# simulazione: precalcolate al caricamento, mai ricalcolate a runtime.
var _vi: Dictionary = {}
var _tier: Dictionary = {}
var _color: Dictionary = {}
var _ammo_mult: PackedFloat32Array = PackedFloat32Array()

## Sui nastri un materiale e' un singolo byte, non una StringName: servono un
## indice compatto e la sua inversa. L'ordine e' quello di materials.json ed e'
## quindi stabile fra sessioni — importante per i salvataggi.
var material_ids: Array[StringName] = []
var _material_index: Dictionary = {}
var _colors_by_index: PackedColorArray = PackedColorArray()

var loaded := false
var errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	load_all()


# =============================================================== CARICAMENTO ==

func load_all() -> bool:
	errors.clear()
	_load_tuning()
	_load_materials()
	_load_recipes()
	_load_buildings()
	_load_research()
	_load_waves()
	_build_caches()
	loaded = errors.is_empty()
	if not loaded:
		for e in errors:
			push_error("Database: " + e)
	return loaded


func _read_json(filename: String) -> Dictionary:
	var path := DATA_DIR + filename
	if not FileAccess.file_exists(path):
		errors.append("file mancante: " + path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		errors.append("file vuoto: " + path)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("JSON non valido (attesa una Dictionary) in: " + path)
		return {}
	return parsed as Dictionary


## Indicizza una lista di oggetti con campo "id" in una Dictionary id -> oggetto.
func _index_by_id(list: Variant, where: String) -> Dictionary:
	var out: Dictionary = {}
	if typeof(list) != TYPE_ARRAY:
		errors.append("attesa una lista in " + where)
		return out
	for entry: Variant in list as Array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var d := entry as Dictionary
		if not d.has("id"):
			errors.append("voce senza 'id' in " + where)
			continue
		out[StringName(d["id"])] = d
	return out


func _load_tuning() -> void:
	tuning = _read_json("tuning.json")
	if tuning.is_empty():
		return
	var eco: Dictionary = tuning.get("economy", {})
	lambda_vi = float(eco.get("lambda_vi", lambda_vi))
	beta_ammo = float(eco.get("beta_ammo", beta_ammo))
	server_data_per_vi = float(eco.get("server_data_per_vi", server_data_per_vi))

	var sim: Dictionary = tuning.get("simulation", {})
	tick_hz = int(sim.get("tick_hz", tick_hz))
	tick_seconds = float(sim.get("tick_seconds", 1.0 / float(tick_hz)))
	slots_per_tile = int(sim.get("slots_per_tile", slots_per_tile))

	var grid: Dictionary = tuning.get("grid", {})
	grid_w = int(grid.get("width", grid_w))
	grid_h = int(grid.get("height", grid_h))
	tile_px = int(grid.get("tile_pixels", tile_px))
	core_size = int(grid.get("core_size", core_size))

	var cr: Dictionary = tuning.get("combat_reward", {})
	kappa_combat_data = float(cr.get("kappa_combat_data", kappa_combat_data))


func _load_materials() -> void:
	var doc := _read_json("materials.json")
	if doc.is_empty():
		return
	materials = _index_by_id(doc.get("solids", []), "materials.json/solids")
	fluids = _index_by_id(doc.get("fluids", []), "materials.json/fluids")


func _load_recipes() -> void:
	var doc := _read_json("recipes.json")
	if doc.is_empty():
		return
	recipes = _index_by_id(doc.get("recipes", []), "recipes.json/recipes")


func _load_buildings() -> void:
	var doc := _read_json("buildings.json")
	if doc.is_empty():
		return
	buildings = _index_by_id(doc.get("buildings", []), "buildings.json/buildings")


func _load_research() -> void:
	var doc := _read_json("research.json")
	if doc.is_empty():
		return
	research = _index_by_id(doc.get("nodes", []), "research.json/nodes")


func _load_waves() -> void:
	var doc := _read_json("waves.json")
	if doc.is_empty():
		return
	enemies = _index_by_id(doc.get("enemies", []), "waves.json/enemies")
	wave_composition = doc.get("composition", []) as Array


func _build_caches() -> void:
	_vi.clear()
	_tier.clear()
	_color.clear()
	material_ids.clear()
	_material_index.clear()
	for id: StringName in materials:
		var m: Dictionary = materials[id]
		var r := int(m.get("refinement_tier", 0))
		var base := float(m.get("base_value", 1.0))
		_tier[id] = r
		_vi[id] = base * pow(lambda_vi, float(r))
		_color[id] = Color(String(m.get("color", "#FFFFFF")))
		_material_index[id] = material_ids.size()
		material_ids.append(id)

	_colors_by_index.resize(material_ids.size())
	for i in material_ids.size():
		_colors_by_index[i] = _color[material_ids[i]]
	# I tier arrivano al massimo a 8 nell'MVP; la tabella e' minuscola, tenerla
	# precalcolata evita una pow() per ogni colpo sparato.
	_ammo_mult.resize(9)
	for r in range(9):
		_ammo_mult[r] = pow(float(r) + 1.0, beta_ammo)


# ==================================================================== LOOKUP ==

## Valore Industriale di un'unita' di materiale. VI = base_value * lambda^tier.
func vi(material_id: StringName) -> float:
	return _vi.get(material_id, 0.0)


func tier(material_id: StringName) -> int:
	return _tier.get(material_id, 0)


func material_color(material_id: StringName) -> Color:
	return _color.get(material_id, Color.MAGENTA)


func material_name(material_id: StringName) -> String:
	var m: Dictionary = materials.get(material_id, {})
	return String(m.get("name", String(material_id)))


## Indice compatto del materiale, per lo storage a byte sui nastri.
func material_index(material_id: StringName) -> int:
	return int(_material_index.get(material_id, -1))


func material_from_index(i: int) -> StringName:
	if i < 0 or i >= material_ids.size():
		return &""
	return material_ids[i]


func color_from_index(i: int) -> Color:
	if i < 0 or i >= _colors_by_index.size():
		return Color.MAGENTA
	return _colors_by_index[i]


## Moltiplicatore di danno di una munizione di tier R: (R+1)^beta.
## Polinomiale per scelta: la difesa deve crescere piu' lentamente dei Dati,
## cosi' il giocatore e' sempre spinto ad ampliare la logistica (TDD 01 §3).
func ammo_multiplier(t: int) -> float:
	if t < 0 or t >= _ammo_mult.size():
		return pow(float(t) + 1.0, beta_ammo)
	return _ammo_mult[t]


func is_valid_ammo(material_id: StringName) -> bool:
	var m: Dictionary = materials.get(material_id, {})
	return bool(m.get("valid_ammo", false))


func recipe(recipe_id: StringName) -> Dictionary:
	return recipes.get(recipe_id, {})


func building(building_id: StringName) -> Dictionary:
	return buildings.get(building_id, {})


func building_size(building_id: StringName) -> Vector2i:
	var b: Dictionary = buildings.get(building_id, {})
	var s: Array = b.get("size", [1, 1])
	return Vector2i(int(s[0]), int(s[1]))


## Tempo di ciclo in tick della simulazione, arrotondato per eccesso.
func recipe_ticks(recipe_id: StringName) -> int:
	var r: Dictionary = recipes.get(recipe_id, {})
	return int(ceil(float(r.get("cycle_s", 1.0)) * float(tick_hz)))


func research_node(node_id: StringName) -> Dictionary:
	return research.get(node_id, {})


# ================================================================= SELF TEST ==

## Verifica che l'engine calcoli gli STESSI numeri di tools/balance_sim.py.
## Se questi controlli passano, i dati caricati e le formule implementate sono
## allineati al documento di bilanciamento. Chiamato all'avvio in debug e dal
## comando headless `--selftest`.
func self_test() -> Dictionary:
	# NOTA: niente lambda per accumulare il contatore dei fallimenti. In GDScript
	# le Callable catturano le variabili locali PER VALORE, quindi un `failed += 1`
	# dentro la lambda incrementerebbe una copia e il test uscirebbe sempre verde.
	# Il conteggio si fa alla fine, sull'array.
	var checks: Array[Dictionary] = []

	_check(checks, loaded, "Tutti i JSON caricati senza errori",
			"errori: %d" % errors.size(), "0")
	_check(checks, materials.size() == 11, "Materiali indicizzati",
			str(materials.size()), "11")
	_check(checks, recipes.size() == 15, "Ricette indicizzate",
			str(recipes.size()), "15")
	_check(checks, buildings.size() == 20, "Edifici indicizzati",
			str(buildings.size()), "20")
	_check(checks, research.size() == 12, "Nodi di ricerca indicizzati",
			str(research.size()), "12")
	_check(checks, enemies.size() == 3, "Archetipi nemici indicizzati",
			str(enemies.size()), "3")

	_check(checks, tier(&"ingot_iron") == 3, "tier(ingot_iron)",
			str(tier(&"ingot_iron")), "3")
	_check(checks, is_equal_approx(vi(&"ingot_iron"), 15.625), "vi(ingot_iron)",
			"%.4f" % vi(&"ingot_iron"), "15.6250")
	_check(checks, is_equal_approx(vi(&"ore_iron"), 1.0), "vi(ore_iron)",
			"%.4f" % vi(&"ore_iron"), "1.0000")
	_check(checks, absf(vi(&"alloy_cond") - 58.5938) < 0.001, "vi(alloy_cond)",
			"%.4f" % vi(&"alloy_cond"), "58.5938")

	_check(checks, absf(ammo_multiplier(3) - 9.0) < 0.01, "moltiplicatore danno R3",
			"%.4f" % ammo_multiplier(3), "~9.0000")
	_check(checks, absf(ammo_multiplier(1) - 3.0) < 0.01, "moltiplicatore danno R1",
			"%.4f" % ammo_multiplier(1), "~3.0000")

	# Invariante 1 del simulatore: la catena lunga rende >= 1.8x la scorciatoia.
	var v_long := 2.0 * vi(&"ingot_iron") + 1.0 * vi(&"slag")
	_check(checks, v_long / vi(&"ingot_iron") >= 1.8, "Catena lunga vs scorciatoia",
			"x%.2f" % (v_long / vi(&"ingot_iron")), ">= x1.80")

	# Invariante 2: raffinare batte il grezzo di almeno 20x.
	_check(checks, v_long / vi(&"ore_iron") >= 20.0, "Raffinato vs minerale grezzo",
			"x%.1f" % (v_long / vi(&"ore_iron")), ">= x20")

	# Invariante 13: la linea di riferimento produce rapporti interi.
	var r_drill := 1.0 / float(recipe(&"drill_iron").get("cycle_s", 1.0))
	var r_crush_in := 1.0 / float(recipe(&"crush_iron").get("cycle_s", 1.0))
	var n_crush := 4.0 * r_drill / r_crush_in
	_check(checks, is_equal_approx(n_crush, 4.0), "4 Trivelle -> Trituratori",
			"%.2f" % n_crush, "4.00")

	# Il ciclo macchina deve cadere su un numero intero di tick.
	_check(checks, recipe_ticks(&"crush_iron") == 40, "Ciclo Trituratore in tick",
			str(recipe_ticks(&"crush_iron")), "40")

	var failed := 0
	for c in checks:
		if not bool(c["ok"]):
			failed += 1
	return {"checks": checks, "failed": failed, "total": checks.size()}


func _check(into: Array[Dictionary], ok: bool, label: String, got: String, want: String) -> void:
	into.append({"ok": ok, "label": label, "got": got, "want": want})
