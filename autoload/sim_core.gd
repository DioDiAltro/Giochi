extends Node
## Il tick loop. UNICO punto della codebase in cui il tempo avanza.
##
## Nessuna entita' di gioco ha un proprio _process o _physics_process: edifici,
## item e nemici sono dati, non nodi. Questa e' la decisione che piu' incide sul
## frame rate su un Android di fascia media (TDD 00 §14).
##
## Gira in _physics_process, quindi a passo fisso indipendente dal frame rate di
## rendering: la simulazione resta deterministica anche se il device cala a 30 fps.

const TICK_HZ := 20
const TICK_S := 1.0 / float(TICK_HZ)

## Se il device fa uno stutter lungo non recuperiamo 300 tick in un frame: cosi'
## facendo perderemmo anche il frame successivo, e a cascata. Meglio perdere un
## po' di tempo simulato che entrare in spirale.
const MAX_CATCHUP_TICKS := 4

var world: WorldState
var running := true

# I sistemi sono referenze tipizzate, non un array generico: `s.call(&"tick")`
# passa dal dispatch dinamico ed e' misurabilmente piu' lento in un loop caldo.
var belts: BeltSystem
var machines: MachineSystem
var build: BuildSystem

var tick_index := 0
var _accum := 0.0

# --- telemetria: e' un KPI di uscita dello Sprint 6, si misura da subito ---
var last_tick_usec := 0
var avg_tick_usec := 0.0
var peak_tick_usec := 0
var ticks_this_frame := 0


func _ready() -> void:
	world = WorldState.new(Database.grid_w, Database.grid_h)
	world.generate(918273)
	for k: Variant in Database.tuning.get("starting_stock", {}):
		world.add_material(StringName(k), float(Database.tuning["starting_stock"][k]))

	# Ordine del TDD 00 §3: Energia -> Fluidi -> Macchine -> Nastri -> Dati ->
	# Combattimento. Non e' arbitrario: le macchine devono avanzare prima dei
	# nastri, cosi' un output prodotto in questo tick puo' partire subito.
	# Sprint 1 ne ha due; gli altri si inseriscono qui senza toccare il loop.
	belts = BeltSystem.new(world)
	machines = MachineSystem.new(world, belts)
	build = BuildSystem.new(world, belts)


func _process(delta: float) -> void:
	build.process_ui(delta)


func _physics_process(delta: float) -> void:
	if not running:
		return
	_accum += delta * world.time_scale
	ticks_this_frame = 0
	var budget := MAX_CATCHUP_TICKS
	while _accum >= TICK_S and budget > 0:
		_accum -= TICK_S
		budget -= 1
		ticks_this_frame += 1
		_tick()
	if budget == 0 and _accum >= TICK_S:
		# Abbiamo saturato il budget: scartiamo l'arretrato invece di accumularlo.
		_accum = 0.0


func _tick() -> void:
	var t0 := Time.get_ticks_usec()
	tick_index += 1

	machines.tick(tick_index)
	belts.tick(tick_index)

	# Attivita' a bassa frequenza, sfalsate su tick diversi per non sommarle
	# tutte nello stesso frame.
	if tick_index % 40 == 3:
		pass   # Sprint 5: world.production_graph.resolve()
	if tick_index % 600 == 7:
		pass   # Sprint 5: SaveManager.request_autosave()

	last_tick_usec = Time.get_ticks_usec() - t0
	peak_tick_usec = maxi(peak_tick_usec, last_tick_usec)
	avg_tick_usec = lerpf(avg_tick_usec, float(last_tick_usec), 0.05)
	EventBus.sim_tick.emit(tick_index)


## Frazione di tick trascorsa, 0..1. I renderer la usano per interpolare fra la
## posizione del tick precedente e quella corrente: la logica gira a 20 Hz ma il
## movimento sullo schermo resta fluido a 60 fps.
func tick_alpha() -> float:
	return clampf(_accum / TICK_S, 0.0, 1.0)


func sim_seconds() -> float:
	return float(tick_index) * TICK_S


func reset_telemetry() -> void:
	peak_tick_usec = 0
	avg_tick_usec = 0.0
