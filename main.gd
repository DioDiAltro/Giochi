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
	# La barra di costruzione deve poter comandare il ghost; sono su due rami
	# diversi dell'albero (CanvasLayer contro Node2D), quindi il collegamento
	# lo fa la scena principale invece di farli cercare a vicenda.
	var bar := get_node_or_null(^"UI/BuildBar")
	var ghost := get_node_or_null(^"BuildGhost")
	if bar != null and ghost != null:
		bar.set(&"ghost", ghost)

	if "--selftest" in OS.get_cmdline_user_args():
		_run_selftest_and_quit()
		return
	if "--stress" in OS.get_cmdline_user_args():
		_run_stress_and_quit()
		return
	if "--screenshot" in OS.get_cmdline_user_args():
		_run_screenshot_and_quit()
		return
	_print_boot_report()


## Costruisce una scena dimostrativa, la fa girare e salva un PNG.
## Serve a verificare i RENDERER, che in headless non vengono mai esercitati
## perche' _draw() non viene chiamato senza un display.
##
##     xvfb-run -a godot --path . -- --screenshot
func _run_screenshot_and_quit() -> void:
	var world := SimCore.world
	var patch := _find_patch_2x2(world, WorldState.Terrain.ORE_IRON)
	if patch != Vector2i(-1, -1):
		SimCore.build.place_building(&"drill", patch)
		# Serpentino corto: mostra curve, frecce di direzione e item in coda.
		var p := patch + Vector2i(2, 0)
		SimCore.build.build_belt_path(BuildSystem.route_l(p, p + Vector2i(9, 0)))
		SimCore.build.build_belt_path(BuildSystem.route_l(p + Vector2i(9, 0), p + Vector2i(9, 5)))
		SimCore.build.build_belt_path(BuildSystem.route_l(p + Vector2i(9, 5), p + Vector2i(1, 5)))
		SimCore.build.place_building(&"storage", p + Vector2i(-1, 5))

	var cam := get_node_or_null(^"Camera")
	if cam != null:
		cam.position = (Vector2(patch) + Vector2(5, 3)) * float(Database.tile_px)
		cam.zoom = Vector2(1.6, 1.6)

	var ghost := get_node_or_null(^"BuildGhost")
	if ghost != null:
		ghost.call(&"set_tool", 1)          # strumento Nastro, per vedere il ghost

	# Lascia girare la simulazione cosi' gli item hanno il tempo di riempire
	# il percorso: uno screenshot con i nastri vuoti non dimostrerebbe niente.
	for _i in 400:
		await get_tree().process_frame

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "user://sprint1.png"
	img.save_png(path)
	print("screenshot salvato in %s" % ProjectSettings.globalize_path(path))
	print("item sui nastri: %d · corsie: %d"
		% [SimCore.belts.count_items(), SimCore.belts.lanes.size()])
	get_tree().quit(0)


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
	var chain_ok := _check_production_chain()

	get_tree().quit(0 if (failed == 0 and world_ok and sim_ok and chain_ok) else 1)


## Verifica funzionale della catena Trivella -> nastro -> Silo.
##
## Il test di stress misura la VELOCITA' dei nastri, non la loro CORRETTEZZA:
## un sistema che non consegna niente e' velocissimo. Questo controllo esercita
## il percorso completo, compresi i due punti di consegna (macchina -> nastro e
## nastro -> macchina) che lo stress test non tocca mai.
func _check_production_chain() -> bool:
	var world := SimCore.world
	var patch := _find_patch_2x2(world, WorldState.Terrain.ORE_IRON)
	if patch == Vector2i(-1, -1):
		printerr("FAIL  nessun giacimento di ferro 2x2 libero nella mappa generata")
		return false

	var drill := SimCore.build.place_building(&"drill", patch)
	if drill < 0:
		printerr("FAIL  impossibile piazzare la Trivella su %s" % patch)
		return false

	# Nastro dal bordo destro della trivella verso est, poi il Silo in fondo.
	var start := patch + Vector2i(2, 0)
	var path := BuildSystem.route_l(start, start + Vector2i(6, 0))
	var built := SimCore.build.build_belt_path(path)
	var silo := SimCore.build.place_building(&"storage", start + Vector2i(7, 0))
	if built < 7 or silo < 0:
		printerr("FAIL  catena incompleta: %d nastri, silo=%d" % [built, silo])
		return false

	var b: Building = world.buildings[drill]
	if b.out_cells.is_empty():
		printerr("FAIL  la Trivella non ha trovato nessun nastro in uscita")
		return false

	var before := float(world.inventory.get(&"ore_iron", 0.0))
	for i in 400:
		SimCore.machines.tick(i)
		SimCore.belts.tick(i)
	var delivered := float(world.inventory.get(&"ore_iron", 0.0)) - before

	# 400 tick = 20 s. La trivella fa 1 minerale ogni 2 s, quindi ne produce ~10;
	# il primo deve percorrere 7 celle (21 slot a 6 slot/s = 3.5 s) prima di
	# arrivare. Chiediamo almeno 3 consegne: verifica il flusso, non la portata.
	var ok := delivered >= 3.0
	print("%s  catena Trivella->nastro->Silo: %d minerali consegnati in 20 s (attesi >=3)"
		% ["OK  " if ok else "FAIL", int(delivered)])
	if not ok:
		printerr("      prodotti dalla trivella: %d, item ancora sui nastri: %d"
			% [b.produced_total, SimCore.belts.count_items()])
	return ok


func _find_patch_2x2(world: WorldState, kind: int) -> Vector2i:
	for y in range(2, world.h - 12):
		for x in range(2, world.w - 12):
			var found := true
			for dy in 2:
				for dx in 2:
					if world.terrain[world.cell(x + dx, y + dy)] != kind:
						found = false
						break
				if not found:
					break
			if not found:
				continue
			# Serve anche spazio libero a destra per il nastro e il Silo.
			var clear := true
			for dx in range(2, 11):
				var c := world.cell(x + dx, y)
				if world.terrain[c] == WorldState.Terrain.ROCK \
						or world.terrain[c] == WorldState.Terrain.WATER:
					clear = false
					break
			if clear:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## Criterio di completamento n.2 dello Sprint 1: 2 000 item a 60 fps.
## Costruisce un serpentino di ~1 500 celle, lo popola, e misura il costo reale
## di BeltSystem per tick. Misura la SIMULAZIONE, non il rendering: sono i due
## budget separati del TDD 00 §14 e vanno tenuti distinti.
##
##     godot --headless --path . -- --stress
func _run_stress_and_quit() -> void:
	var world := SimCore.world
	var belts := SimCore.belts

	var laid := _lay_serpentine(world, 8, 8, 68, 30)
	SimCore.build.place_building(&"storage", Vector2i(70, 36))
	belts.mark_dirty()
	belts.rebuild_lanes()

	# Popola 2 000 slot distribuiti lungo il percorso, non ammassati: un nastro
	# pieno e' ingorgato, e l'ingorgo e' il percorso VELOCE (esce subito). La
	# misura onesta e' con gli item in movimento.
	var target := 2000
	var total_slots := belts.total_slots()
	var placed := 0
	var stride := maxi(1, total_slots / target)
	for lane in belts.lanes:
		for i in lane.slot_idx.size():
			if placed >= target:
				break
			if i % stride == 0:
				world.belt_slots[lane.slot_idx[i]] = 1 + (placed % 4)
				placed += 1

	print("=== STRESS TEST NASTRI ===")
	print("celle di nastro : %d" % laid)
	print("corsie          : %d" % belts.lanes.size())
	print("slot totali     : %d" % total_slots)
	print("item in campo   : %d" % placed)

	var ticks := 1200                       # 60 s di gioco a 20 Hz
	var t0 := Time.get_ticks_usec()
	for i in ticks:
		belts.tick(i)
	var total_us := Time.get_ticks_usec() - t0
	var per_tick_ms := float(total_us) / float(ticks) / 1000.0

	print("\n%d tick simulati in %.1f ms" % [ticks, total_us / 1000.0])
	print("costo per tick  : %.4f ms  (budget TDD: 5.000 ms)" % per_tick_ms)
	print("quota di budget : %.1f%%" % (per_tick_ms / 5.0 * 100.0))
	print("proiezione su Snapdragon 730 (~4x piu' lento): %.3f ms = %.1f%%"
		% [per_tick_ms * 4.0, per_tick_ms * 4.0 / 5.0 * 100.0])

	var still := belts.count_items()
	print("\nitem ancora sui nastri dopo 60 s: %d (%d consegnati al silo)"
		% [still, placed - still])

	var ok := per_tick_ms * 4.0 < 5.0
	print("\n%s  criterio Sprint 1 n.2: 2 000 item entro il budget di simulazione"
		% ["OK  " if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)


## Posa un serpentino di nastri direttamente in WorldState, senza passare da
## BuildSystem: e' uno strumento di misura, non un'azione di gioco.
func _lay_serpentine(world: WorldState, x0: int, y0: int, x1: int, rows: int) -> int:
	var laid := 0
	for r in rows:
		var y := y0 + r
		var last_row := r == rows - 1
		if r % 2 == 0:
			for x in range(x0, x1 + 1):
				var c := world.cell(x, y)
				world.belt_dir[c] = 1 if (x == x1 and not last_row) else 0
				laid += 1
		else:
			for x in range(x0, x1 + 1):
				var c := world.cell(x, y)
				world.belt_dir[c] = 1 if (x == x0 and not last_row) else 2
				laid += 1
	return laid


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
