# Factory-Defense Incrementale a Nodi — istruzioni di progetto

Gioco mobile (Godot 4.4, iOS/Android) che unisce logistica su griglia e difesa
attiva stile **Mindustry**, raffinazione a stadi multipli stile **Minecraft
moddato tech**, e progressione a nodi/idle stile **Upload Lab**.

La radice del repo **è** la radice del progetto Godot: `res://data/` è la stessa
cartella `data/` versionata.

---

## La regola d'oro

> **Nessun numero di bilanciamento viene scritto a mano in GDScript.**

Tutto si carica da `res://data/*.json` tramite l'autoload `Database`. Se ti serve
un valore e non è nei JSON, va aggiunto **lì**, non al codice. Il Valore
Industriale in particolare non è mai salvato: si *deriva* da `base_value` e
`refinement_tier`, perché duplicarlo significherebbe poterlo desincronizzare.

## Prima di ogni commit

```bash
export GODOT=/percorso/al/binario/godot      # su Windows: $env:GODOT = "C:\Godot\godot.exe"
./tools/check_all.sh
```

Tre passaggi, exit 1 se uno fallisce:
1. **17 invarianti di design** sul bilanciamento (`tools/balance_sim.py --check`)
2. Validità dei JSON
3. **Self test dell'engine**: i dati caricati da Godot producono gli stessi
   numeri del simulatore Python, e il tick loop gira davvero a 20 Hz

Altri strumenti:

```bash
godot --headless --path . -- --selftest      # dati + mondo + tick loop + catena produttiva
godot --headless --path . -- --stress        # 2 000 item, costo per tick
godot --headless --path . --script res://tools/test_packed.gd   # semantica dei Packed array
xvfb-run -a godot --path . -- --screenshot   # verifica i RENDERER (salva un PNG)
```

> Il test `--screenshot` esiste perché in headless `_draw()` non viene mai
> chiamato. Alla prima esecuzione ha trovato due bug di layout che nessun test
> testuale avrebbe rivelato. **Usalo ogni volta che tocchi qualcosa in `view/` o
> `ui/`.**

---

## Architettura

Quattro strati, con una regola di dipendenza rigida: **ogni strato conosce solo
quello sotto di sé.**

| Strato | Cartella | Frequenza |
|---|---|---|
| 4 · Presentazione | `view/`, `ui/` | 60 Hz |
| 3 · Simulazione | `sim/` | 20 Hz |
| 2 · Stato | `sim/world_state.gd` | — |
| 1 · Dati statici | `data/`, `autoload/database.gd` | — |

**Lo Strato 3 deve poter girare senza lo Strato 4.** È ciò che rende possibili il
calcolo offline, i test headless e il tuning automatico. Se un sistema di
simulazione tocca un `Node2D`, hai introdotto un bug che pagherai tre sprint dopo.

La UI **legge** la simulazione direttamente per disegnare, ma non la modifica mai:
manda comandi tramite i segnali di `autoload/event_bus.gd`.

`autoload/sim_core.gd` è **l'unico punto della codebase in cui il tempo avanza**.
Nessuna entità di gioco ha un proprio `_process`: edifici, item e nemici sono
dati, non nodi.

---

## Convenzioni di codice

- **Tipizza sempre**: `var x := ...` o `var x: T = ...`. Il codice untyped è
  sensibilmente più lento e il progetto ha `untyped_declaration=1` fra i warning.
- **`StringName` (`&"..."`) per ogni identificatore** che finisca in un dizionario
  o in un confronto dentro il tick loop. Le `String` restano per il testo mostrato
  all'utente.
- **`Packed*Array` invece di `Array`** per i dati spaziali, e array paralleli
  indicizzati linearmente (`idx = y * w + x`) invece di `Dictionary[Vector2i]`:
  un lookup su `Dictionary` costa 5-10× un accesso ad array.
- **Commenti in italiano**, e solo dove spiegano un *perché* non ovvio. Niente
  commenti che ripetono il codice.
- Niente `class_name` sugli script autoload: va in conflitto con il singleton.

## Tre trappole che mordono davvero

1. **Le `Callable` catturano per valore.** Un `contatore += 1` dentro una lambda
   incrementa una copia. Ha già fatto uscire il self test con codice 0 mentre
   stampava `FAIL`.
2. **`res://` è in sola lettura nelle build esportate.** Scrivere lì funziona sul
   PC e fallisce silenziosamente sul telefono. I salvataggi vanno in `user://`.
3. **Godot non importa i `.json` come risorse.** Nel preset di esportazione serve
   `data/*.json` fra i filtri per file non-risorsa, altrimenti la build parte
   senza dati. C'è una rete di sicurezza a schermo, ma meglio non arrivarci.

Dopo aver aggiunto uno script con `class_name`, serve una scansione del progetto
(`godot --headless --path . --import`) prima che il tipo sia risolvibile.

---

## Le costanti che non si toccano

Sono in `data/tuning.json` e sono protette dalle invarianti del simulatore:

| Costante | Valore | Se la tocchi |
|---|--:|---|
| `threat_industrial_exponent` | 0,80 | ☠️ A ≥ 1,0 espandere la produzione diventa net-negativo e il gioco diventa un tower defense statico. È il numero che può distruggere il concept con una cifra. |
| `offline_threat_uses_online_theta` | `true` | ☠️ A `false` l'idle avanza oltre il tuo tetto difensivo e si rientra in una partita già persa. |
| `lambda_vi` | 2,5 | ⚠️ Cambia l'intera scala economica. |
| `beta_ammo` | 1,585 | ⚠️ Sposta il punto di pareggio difensivo. |
| `hp_base_b0` | 150 | 🟢 Difficoltà globale. La prima manopola da usare dopo un playtest. |

---

## Stato

| Sprint | Stato |
|---|---|
| 0 · Fondamenta | ✅ codice verificato — manca la build su device fisico |
| 1 · Logistica | ✅ 2 000 item a 0,24 ms/tick — manca la prova di *feeling* su telefono |
| 2 · Produzione a stadi multipli | ⬜ prossimo |
| 3-6 | ⬜ vedi `docs/TDD_02_Roadmap_MVP.md` |

**Traguardo dello Sprint 2, già scritto e verificabile:** la linea
`4 Trivelle : 4 Trituratori : 4 Purificatori : 12 Fornaci : 2 Pompe` deve produrre
**4,00 lingotti/s misurati** — lo stesso numero della Tabella 3 di
`docs/BALANCE_REPORT.txt`. Se non coincide è un bug, non una scelta di design.

## Documenti

| File | Contenuto |
|---|---|
| `docs/TDD_00_Architettura.md` | come è fatto il software |
| `docs/TDD_01_Economia_Bilanciamento.md` | derivazione di ogni costante |
| `docs/TDD_02_Roadmap_MVP.md` | i 7 sprint, con criteri verificabili |
| `docs/SAVE_SCHEMA.md` | schema versionato + migrazioni |
| `docs/SETUP_EXPORT.md` | setup Windows/Android |
| `docs/GODOT_PER_PROGRAMMATORI.md` | differenze dell'engine per chi già programma |
| `docs/BALANCE_REPORT.txt` | 13 tabelle generate dal simulatore |
