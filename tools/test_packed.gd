extends SceneTree
## Verifica sperimentale di due assunzioni su cui poggia BeltSystem.
##   godot --headless --script res://tools/test_packed.gd
##
## 1. Scrivere su un PackedByteArray MEMBRO di un oggetto muta in place,
##    oppure il copy-on-write ne fa una copia? Se copiasse, ogni step di
##    nastro copierebbe 27 KB e il sistema sarebbe inutilizzabile.
## 2. Quanto costa davvero l'accesso `oggetto.array[i]` rispetto a una
##    variabile locale, sul volume di lavoro reale dello Sprint 1?

class Holder extends RefCounted:
	var data := PackedByteArray()
	func _init(n: int) -> void:
		data.resize(n)


func _initialize() -> void:
	print("=== TEST PackedByteArray ===\n")

	# --- 1. semantica ------------------------------------------------------
	var h := Holder.new(16)
	h.data[3] = 42
	print("scrittura diretta su membro:      h.data[3] = %d  %s"
		% [h.data[3], "IN PLACE" if h.data[3] == 42 else "COPIATO (rotto)"])

	var alias := h.data
	alias[5] = 99
	print("scrittura tramite variabile:      h.data[5] = %d  %s"
		% [h.data[5], "condiviso" if h.data[5] == 99 else "COW: la locale e' una COPIA"])

	# --- 2. costo ----------------------------------------------------------
	# Volume reale: 4500 slot, ~6 step/s. Qui ne facciamo 100x per misurare.
	var n := 4500
	var big := Holder.new(n)
	var iters := 100

	var t0 := Time.get_ticks_usec()
	for _k in iters:
		for i in range(n - 1, 0, -1):
			if big.data[i] == 0 and big.data[i - 1] != 0:
				big.data[i] = big.data[i - 1]
				big.data[i - 1] = 0
	var t_member := Time.get_ticks_usec() - t0

	var local := PackedByteArray()
	local.resize(n)
	t0 = Time.get_ticks_usec()
	for _k in iters:
		for i in range(n - 1, 0, -1):
			if local[i] == 0 and local[i - 1] != 0:
				local[i] = local[i - 1]
				local[i - 1] = 0
	var t_local := Time.get_ticks_usec() - t0

	print("\nscansione di %d slot, %d ripetizioni:" % [n, iters])
	print("  accesso via membro   : %6.2f ms  (%.3f ms per passata)"
		% [t_member / 1000.0, t_member / 1000.0 / iters])
	print("  variabile locale     : %6.2f ms  (%.3f ms per passata)"
		% [t_local / 1000.0, t_local / 1000.0 / iters])

	# Carico reale: un nastro base fa 6 passate al secondo, il tick gira a 20 Hz.
	# Quindi per TICK facciamo 6/20 = 0.3 passate. Il budget del TDD e' 5 ms/tick.
	var ms_pass := t_member / 1000.0 / iters
	var ms_tick := ms_pass * 6.0 / 20.0
	print("\nProiezione sul carico dello Sprint 1 (4500 slot, nastri a 6 slot/s):")
	print("  %.3f ms per tick = %.1f%% del budget di 5 ms" % [ms_tick, ms_tick / 5.0 * 100.0])
	print("  con l'alias locale: %.3f ms per tick (%.1f%%)"
		% [ms_tick * (float(t_local) / float(t_member)),
		   ms_tick * (float(t_local) / float(t_member)) / 5.0 * 100.0])
	print("  verdetto: %s" % ["DENTRO il budget" if ms_tick < 5.0 else "DA OTTIMIZZARE"])
	print("\n  NB: misurato su CPU desktop. Un Snapdragon 730 e' ~4x piu' lento,")
	print("      quindi il margine reale e' circa un quarto di questo.")

	quit(0)
