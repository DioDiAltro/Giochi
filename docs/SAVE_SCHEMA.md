# Schema di Salvataggio — versione 1

Formato di produzione: **binario** (`FileAccess.store_var()` con `full_objects = false`), scritto su `WorkerThreadPool`.
Formato di debug: lo stesso albero esportato in JSON con `--debug-save`.

Percorso: `user://save_slot_0.dat` · Backup rotativo: `user://save_slot_0.bak` (scritto prima di ogni sovrascrittura).

---

## Albero

```jsonc
{
  "version": 1,                    // OBBLIGATORIO, sempre il primo campo
  "created_unix": 1785000000,
  "last_exit_unix": 1785012345,    // usato dall'OfflineSolver
  "total_played_seconds": 8412.5,  // monotono, cresce solo a gioco aperto
  "clock_anomalies": 0,            // incrementato se now < last_exit_unix

  "world": {
    "seed": 918273,
    "size": [96, 96],
    "terrain": "<PackedByteArray, 9216 byte>",   // rigenerabile dal seed, salvato per sicurezza

    "buildings": [
      {
        "id": 41,                  // stabile per tutta la partita, mai riusato dopo la demolizione
        "type": "washer",
        "cell": [22, 37],          // angolo alto-sinistro del footprint
        "rot": 1,                  // 0..3
        "recipe": "wash_iron",
        "ticks_left": 12,
        "progress_fp": 128,
        "state": 1,                // 0=IDLE 1=WORKING 2=BLOCKED
        "buf_in":  { "dust_iron": 4, "water_mb": 240 },
        "buf_out": { "pdust_iron": 0, "slag": 1 },
        "hp": 400                  // solo per edifici danneggiabili
      }
    ],

    "lanes": [
      {
        "tiles": "<PackedInt32Array>",   // indici lineari, dalla coda alla testa
        "slots": "<PackedByteArray>",    // material_id + 1, 0 = vuoto
        "accum": 96,
        "speed_fp": 77,
        "out_target": 41
      }
    ],

    "fluid_networks": [
      { "pipes": "<PackedInt32Array>", "fluid": "water", "volume_mb": 3200 }
    ],

    "inventory": { "ingot_iron": 217, "ingot_copper": 64, "alloy_cond": 3 }
  },

  "progress": {
    "data": 48213.7,
    "data_lifetime": 190442.1,
    "theta_rolling": 62.5,              // media mobile 60 s, riseminata al caricamento
    "wave_index": 23,
    "wave_timer_s": 41.2,               // il timer AVANZA anche a gioco chiuso

    // Snapshot difensivo: serve all'OfflineSolver per risolvere le ondate
    // mentre l'app è chiusa. Salvato all'uscita, mai ricalcolato dall'offline.
    "defense_snapshot": {
      "dps_vs_swarm": 1360.0,
      "dps_vs_flyer": 1272.0,
      "dps_vs_armored": 832.0,
      "damage_per_ammo": 450.0,
      "ammo_material": "ingot_iron",
      "ammo_in_turrets": 148.0,
      "ammo_supply_rate": 1.6
    },
    "research_unlocked": ["log_belts_1", "mine_drills_1", "proc_washing"],
    "research_levels": { "def_ballistics": 7 },
    "ability_cooldowns": { "overclock": 312.0 }
  },

  "stats": {
    "waves_cleared": 22,
    "materials_uploaded": { "ingot_iron": 88214 },
    "buildings_placed": 341,
    "cores_lost": 0
  }
}
```

---

## Regole non negoziabili

**1. `version` è il primo campo e si legge da solo.**
`SaveManager` deserializza solo `version`, poi decide come leggere il resto. Un salvataggio di una versione **futura** (utente che torna da una beta più recente) va rifiutato con un messaggio, mai letto a metà.

```gdscript
func load_save(path: String) -> Dictionary:
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null: return {}
    var raw: Dictionary = f.get_var(false)
    var v: int = raw.get("version", 0)
    if v > CURRENT_VERSION:
        return { "error": "save_from_future" }
    while v < CURRENT_VERSION:
        raw = _MIGRATIONS[v].call(raw)
        v += 1
        raw["version"] = v
    return raw
```

**2. La catena di migrazioni esiste dallo Sprint 5, non da quando serve.**
`_MIGRATIONS = { 1: _migrate_1_to_2, 2: _migrate_2_to_3, ... }`. Ogni funzione trasforma lo schema `v` in `v+1` e **non ne salta nessuno**. Il giorno in cui pubblichi la prima build su TestFlight, questo smette di essere facoltativo: senza, ogni modifica al modello dati azzera le partite dei tuoi tester.

**3. Ciò che è derivabile non si salva.**
Reti elettriche, flow field, grafo di produzione e indice spaziale dei nemici vengono **ricostruiti** al caricamento. Salvarli significa avere due fonti di verità che prima o poi divergono. Costo di ricostruzione misurato: < 60 ms su un mid-range.

**4. I nemici vivi non si salvano.**
A gioco chiuso i nemici non esistono come entità: le ondate offline sono **risolte analiticamente** dall'`OfflineSolver` a partire da `defense_snapshot`, non simulate unità per unità. Al caricamento il campo di battaglia è vuoto e il timer riparte dal valore aggiornato dal solver.

Questo è anche il motivo per cui `defense_snapshot` **deve** essere salvato invece di essere ricalcolato al caricamento: al rientro la fabbrica potrebbe essere cambiata (silo pieni, energia diversa), e useresti una difesa che non era quella in campo durante l'assenza.

Conseguenza pratica: è impossibile salvare in uno stato di battaglia incoerente, e l'intero calcolo offline costa meno di un millisecondo (un ciclo `while` su qualche decina di iterazioni).

**5. Backup prima della sovrascrittura.**
`save_slot_0.dat` → `save_slot_0.bak` → scrittura. Se il caricamento del principale fallisce, si tenta il backup e si avvisa l'utente. Un crash durante una scrittura di 8 ms è raro ma su mobile succede (l'OS può terminare il processo in qualsiasi momento).

**6. Salvataggio sul ciclo di vita dell'app.**
`NOTIFICATION_APPLICATION_PAUSED` e `NOTIFICATION_WM_CLOSE_REQUEST` forzano un salvataggio **sincrono**. Su Android l'app può essere uccisa subito dopo il pause: un salvataggio su thread non fa in tempo.

```gdscript
func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
        SaveManager.save_now_blocking()      # sincrono, di proposito
```

---

## Dimensione attesa

| Componente | Stima |
|---|--:|
| Terreno (9 216 celle) | 9 KB |
| 800 edifici | ~120 KB |
| 400 corsie × 30 slot | ~35 KB |
| Progressione e statistiche | ~4 KB |
| **Totale (binario)** | **~170 KB** |

Sotto il megabyte anche con una fabbrica molto grande. Nessuna compressione necessaria per l'MVP; se un giorno servisse, `FileAccess.open_compressed()` con `COMPRESSION_ZSTD` è una modifica di due righe.
