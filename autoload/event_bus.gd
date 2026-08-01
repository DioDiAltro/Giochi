extends Node
## Hub dei segnali. La UI (Strato 4) parla alla simulazione (Strato 3) SOLO da qui.
##
## Regola architetturale del TDD 00 §2: lo Strato 4 legge lo Strato 3 direttamente
## (per disegnare), ma non lo modifica mai: manda comandi attraverso questi segnali.
## Cosi' la simulazione resta eseguibile senza UI — condizione necessaria per il
## calcolo offline e per i test automatici del bilanciamento.

# --- Comandi: UI -> simulazione ---
signal build_requested(building_id: StringName, cell: Vector2i, rot: int)
signal demolish_requested(cell: Vector2i)
signal recipe_change_requested(building_index: int, recipe_id: StringName)
signal research_purchase_requested(node_id: StringName)
signal overclock_requested()

# --- Notifiche: simulazione -> UI ---
signal building_placed(building_index: int, cell: Vector2i)
signal building_removed(building_index: int, cell: Vector2i)
signal build_rejected(reason: String)
signal wave_started(wave_index: int, hp_budget: float)
signal wave_cleared(wave_index: int, data_reward: float)
signal core_damaged(hp_left: float)
signal research_unlocked(node_id: StringName)
signal power_satisfaction_changed(sigma: float)
signal offline_report_ready(report: Dictionary)

# --- Diagnostica ---
signal sim_tick(tick_index: int)
