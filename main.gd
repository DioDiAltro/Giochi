extends Node2D
## Punto di ingresso.
##
## Supporta anche l'esecuzione headless per la validazione automatica:
##
##     godot --headless --path . -- --selftest
##
## esce con codice 0 se i dati caricati producono gli stessi numeri di
## tools/balance_sim.py, con 1 altrimenti. E' il ponte fra il documento di
## bilanciamento e il codice: se qualcuno modifica un JSON e rompe un'invariante,
## lo si scopre qui e non tre sprint dopo.


func _ready() -> void:
	if "--selftest" in OS.get_cmdline_user_args():
		_run_selftest_and_quit()
		return
	_print_boot_report()


func _print_boot_report() -> void:
	var r := Database.self_test()
	print("=== Factory Defense — Sprint 0 ===")
	print("Godot %s" % Engine.get_version_info()["string"])
	print("Database: %d materiali, %d ricette, %d edifici, %d nodi ricerca"
		% [Database.materials.size(), Database.recipes.size(),
		   Database.buildings.size(), Database.research.size()])
	# Il controllo richiesto dal criterio di completamento dello Sprint 0:
	print("tier(ingot_iron) = %d, vi = %.3f"
		% [Database.tier(&"ingot_iron"), Database.vi(&"ingot_iron")])
	print("Self test: %d/%d superati" % [r["total"] - int(r["failed"]), r["total"]])
	if int(r["failed"]) > 0:
		for c: Dictionary in r["checks"]:
			if not bool(c["ok"]):
				push_warning("  FAIL %s: ottenuto %s, atteso %s"
					% [c["label"], c["got"], c["want"]])
	print("Mondo %dx%d, tick a %d Hz" % [SimCore.world.w, SimCore.world.h, SimCore.TICK_HZ])


func _run_selftest_and_quit() -> void:
	var r := Database.self_test()
	print("--- SELF TEST DATABASE ---")
	for c: Dictionary in r["checks"]:
		print("%s  %-42s %s  (atteso %s)"
			% ["OK  " if bool(c["ok"]) else "FAIL", c["label"], c["got"], c["want"]])
	var failed := int(r["failed"])
	var total := int(r["total"])
	print("--------------------------")
	print("%d/%d superati" % [total - failed, total])

	# Controlli di integrita' del mondo generato: la mappa deve essere giocabile.
	var counts := SimCore.world.terrain_counts()
	var world_ok := true
	if counts["iron"] < 40:
		printerr("FAIL  giacimenti di ferro insufficienti: %d" % counts["iron"])
		world_ok = false
	if counts["copper"] < 30:
		printerr("FAIL  giacimenti di rame insufficienti: %d" % counts["copper"])
		world_ok = false
	if counts["water"] < 60:
		printerr("FAIL  acqua insufficiente: %d" % counts["water"])
		world_ok = false
	var core := SimCore.world.core_cell
	if SimCore.world.terrain_at(core.x, core.y) != WorldState.Terrain.EMPTY:
		printerr("FAIL  il Core e' sopra un giacimento")
		world_ok = false
	if world_ok:
		print("OK    mondo generato: ferro %d, rame %d, acqua %d, roccia %d"
			% [counts["iron"], counts["copper"], counts["water"], counts["rock"]])

	var sim_ok := await _check_tick_loop()

	get_tree().quit(0 if (failed == 0 and world_ok and sim_ok) else 1)


## Verifica che il tick loop giri davvero alla frequenza dichiarata.
## Senza questo controllo il self test proverebbe solo che i dati si caricano,
## non che la simulazione avanza: e' il tipo di cosa che si scopre allo Sprint 2
## quando le macchine "non producono" e si passa un giorno a cercare il perche'.
func _check_tick_loop() -> bool:
	var frames := 60                                   # 1 s a 60 Hz di fisica
	var seconds := float(frames) / float(Engine.physics_ticks_per_second)
	var expected := int(round(seconds * float(SimCore.TICK_HZ)))
	var before := SimCore.tick_index
	for _i in frames:
		await get_tree().physics_frame
	var got := SimCore.tick_index - before
	var ok := absi(got - expected) <= 1
	print("%s  tick loop: %d tick in %.2f s (attesi %d, %d Hz)"
		% ["OK  " if ok else "FAIL", got, seconds, expected, SimCore.TICK_HZ])
	if not ok:
		printerr("      il tick loop non avanza alla frequenza dichiarata")
	var alpha := SimCore.tick_alpha()
	if alpha < 0.0 or alpha > 1.0:
		printerr("FAIL  tick_alpha fuori range: %f" % alpha)
		ok = false
	return ok
