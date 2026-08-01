class_name BeltLane extends RefCounted
## Una catena massimale di celle di nastro che si alimentano in sequenza.
##
## NON possiede gli item: e' solo un indice di ordinamento sopra
## WorldState.belt_slots. Vedi BeltSystem per il perche' di questa scelta.

var tiles: PackedInt32Array = PackedInt32Array()      ## celle, coda -> testa
var slot_idx: PackedInt32Array = PackedInt32Array()   ## posizione -> slot globale
var out_cell := -1                                    ## dove esce la testa
var accum := 0                                        ## virgola fissa, /256
var speed_fp := 77


func length_tiles() -> int:
	return tiles.size()
