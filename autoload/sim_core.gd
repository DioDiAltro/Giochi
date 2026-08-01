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

var tick_index := 0
var _accum := 0.0
var _systems: Array = []

# --- telemetria: e' un KPI di uscita dello Sprint 6, si misura da subito ---
var last_tick_usec := 0
var avg_tick_usec := 0.0
var peak_tick_usec := 0
var ticks_this_frame := 0


func _ready() -> void:
	world = WorldState.new(Database.grid_w, Database.grid_h)
	world.generate(918273)
	# Sprint 1+: qui verranno registrati i sistemi, nell'ordine del TDD 00 §3
	# (Power -> Fluid -> Machine -> Belt -> Data -> Combat). L'ordine non e'
	# arbitrario: sigma va calcolato prima che le macchine avanzino.
	_systems = []


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

	for s: Object in _systems:
		s.call(&"tick", tick_index)

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
