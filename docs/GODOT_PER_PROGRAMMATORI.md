# Godot per chi sa già programmare

Le cose che sorprendono chi arriva da altri linguaggi o engine, con il riferimento a **dove succedono nel nostro codice**. Salta tutto quello che già sai.

---

## 1. Il modello mentale: tutto è un albero di Node

Non c'è un `main()`. C'è una **SceneTree** con un nodo radice, e tutto pende da lì. Un "livello", un bottone, il giocatore: tutti alberi di `Node`.

Una **scena** (`.tscn`) è solo un sottoalbero salvato su file, riusabile. Non è un concetto runtime: quando la istanzi, ottieni nodi normali. E `.tscn` è **testo** — leggibile e diffabile in git. Apri [`main.tscn`](../main.tscn), sono 25 righe.

L'engine chiama metodi con nomi convenzionali sui tuoi nodi:

| Metodo | Quando |
|---|---|
| `_ready()` | il nodo è entrato nell'albero (i figli sono già pronti) |
| `_process(delta)` | ogni frame renderizzato |
| `_physics_process(delta)` | passo fisso, di default 60 Hz |
| `_draw()` | quando serve ridisegnare, dopo `queue_redraw()` |
| `_unhandled_input(event)` | input non consumato dalla UI |

**Nel nostro codice:** `SimCore._physics_process()` è l'unico punto in cui il tempo avanza. `GridRenderer._draw()` disegna. `CameraController._unhandled_input()` gestisce le dita.

## 2. Autoload = singleton globale

Registrati in `project.godot`, sono nodi istanziati prima della scena principale e accessibili ovunque per nome:

```gdscript
Database.vi(&"ingot_iron")     # nessun import, nessuna get_instance()
```

**L'ordine di dichiarazione conta**: `Database` è primo perché `SimCore._ready()` lo usa per costruire il mondo.

> ⚠️ Non mettere `class_name` su uno script autoload: crea un conflitto fra il tipo globale e il singleton. È il motivo per cui `database.gd` non ha `class_name` mentre `world_state.gd` sì.

## 3. GDScript: sembra Python, non è Python

```gdscript
var a := 5                  # tipo INFERITO (int). Non è il walrus di Python.
var b: float = 5.0          # tipo esplicito
var c = 5                    # UNTYPED — evitalo, è più lento e non lo controlla nessuno
```

Il tipaggio statico non è cosmetico: **il codice tipizzato è sensibilmente più veloce**, perché l'interprete salta la risoluzione dinamica. In una simulazione che fa centinaia di migliaia di operazioni al secondo è la differenza fra 60 e 30 fps. Il progetto ha `untyped_declaration=1` fra i warning apposta.

Altre differenze che fanno perdere tempo:

- **Indentazione a TAB** per default. Mischiare tab e spazi rompe il parsing.
- Niente `self.` per i membri della classe.
- `func` invece di `def`. `elif`, `match` invece di `switch`.
- Gli operatori sono `and` / `or` / `not`, ma anche `&&` / `||` funzionano.
- L'operatore ternario è `a if cond else b`, come Python.
- `^` è XOR bit a bit, **non** l'elevamento a potenza. Per le potenze: `pow(x, y)`.

## 4. ⚠️ Le Callable catturano PER VALORE

Questo mi ha già morso in questo progetto, e vale la pena vederlo:

```gdscript
var failed := 0
var add := func(ok: bool) -> void:
    if not ok:
        failed += 1        # incrementa una COPIA. failed resta 0.
add.call(false)
print(failed)              # 0
```

Il self test stampava `FAIL` su due righe e usciva comunque con codice 0. In GDScript le lambda catturano le variabili locali per valore, non per riferimento.

**Soluzioni:** usa un membro della classe, un array (i tipi per riferimento funzionano), oppure — come ho fatto in `Database.self_test()` — accumula in una struttura e conta alla fine.

## 5. StringName: il `&"..."` che vedi ovunque

```gdscript
Database.vi(&"ingot_iron")     # StringName, non String
```

Le `StringName` sono stringhe **internate**: il confronto è un confronto di puntatori invece di una scansione carattere per carattere. Per le chiavi di dizionario nei percorsi caldi (id di materiali, di ricette, nomi di segnali) sono molto più veloci.

Regola pratica del progetto: **ogni identificatore che finisce in un dizionario o in un confronto dentro il tick loop è una `StringName`**. Il testo mostrato all'utente resta `String`.

## 6. Packed arrays: perché il codice non usa `Array`

```gdscript
var terrain: PackedByteArray       # contiguo, 1 byte per cella
var building_at: PackedInt32Array  # contiguo, 4 byte per cella
```

Un `Array` di GDScript è un array di `Variant` (16-24 byte ciascuno, con controllo di tipo a runtime). Un `PackedInt32Array` è memoria contigua di interi veri. Su 9 216 celle la differenza è di un ordine di grandezza in memoria e in velocità di scansione.

**Nel nostro codice:** `WorldState` usa array paralleli indicizzati linearmente (`idx = y * w + x`) invece di un `Dictionary[Vector2i]`. Un lookup su `Dictionary` costa 5-10× un accesso ad array, e la simulazione ne fa centinaia di migliaia al secondo. È la singola decisione che più inciderà sul frame rate su un Android di fascia media.

## 7. Segnali = observer pattern integrato

```gdscript
signal wave_started(wave_index: int, hp_budget: float)   # dichiarazione
EventBus.wave_started.emit(12, 4470.0)                   # emissione
EventBus.wave_started.connect(_on_wave_started)          # ascolto
```

**Nel nostro codice:** [`autoload/event_bus.gd`](../autoload/event_bus.gd) dichiara già tutti i segnali dell'MVP. Serve alla regola architetturale del TDD: la UI **legge** la simulazione direttamente per disegnare, ma non la modifica mai — le manda comandi via segnale. È ciò che permette alla simulazione di girare senza UI, condizione necessaria per il calcolo offline.

## 8. Memoria: due regimi diversi

- **`RefCounted`** (e i suoi derivati): conteggio dei riferimenti, si liberano da soli. `WorldState` estende `RefCounted` apposta — è dato puro, non deve stare nell'albero.
- **`Node`**: **non** sono a conteggio di riferimenti. Vivono finché non chiami `queue_free()` o finché il padre non muore. Dimenticarsene è il memory leak classico di Godot.

Non c'è un garbage collector che passa a raccogliere: se un `Node` resta orfano senza `queue_free()`, resta lì.

## 9. `res://` e `user://`

- **`res://`** — la cartella del progetto. In una build esportata è **dentro il pacchetto e in sola lettura**.
- **`user://`** — la cartella scrivibile per utente. Su Windows: `%APPDATA%\Godot\app_userdata\<nome progetto>\`. È dove andranno i salvataggi.

> ⚠️ Non provare mai a scrivere in `res://` a runtime: funziona nell'editor e fallisce silenziosamente sul telefono. È un classico che costa una serata.

## 10. `@onready` e l'ordine di inizializzazione

```gdscript
@onready var label: Label = $UI/Score    # assegnato in _ready(), non alla dichiarazione
```

`$Percorso` è zucchero per `get_node("Percorso")`. Senza `@onready` il nodo non esiste ancora quando la variabile viene inizializzata, e ottieni `null`.

## 11. Scorciatoie dell'editor che userai ogni giorno

| Tasto | Azione |
|---|---|
| **F5** | esegui il progetto |
| **F6** | esegui **la scena corrente** (utile per testare un pezzo isolato) |
| **F8** | ferma |
| **F9** | breakpoint |
| **Ctrl+Shift+O** | apri un file per nome (come il Ctrl+P di VS Code) |
| **Ctrl+clic** | vai alla definizione |

Le schede **Debugger → Profiler** e **Monitor** durante l'esecuzione ti danno tempo per frame, draw call e memoria. Sono lo strumento con cui misurerai i tre KPI del TDD 00 §14 — e vanno guardate dallo Sprint 2, non alla fine.

## 12. `.uid`: i file che sembrano spazzatura ma vanno committati

Da Godot 4.4 ogni script ha un `.uid` accanto: è un identificatore stabile che permette di rinominare e spostare i file senza rompere i riferimenti nelle scene. **Vanno versionati.** `.godot/` invece no, è cache rigenerabile — infatti è nel `.gitignore`.

---

## 13. Da dove leggere il nostro codice

In quest'ordine, sono ~600 righe in tutto:

1. **[`autoload/database.gd`](../autoload/database.gd)** — come i JSON diventano lookup tipizzati, e perché il Valore Industriale viene *derivato* invece che letto.
2. **[`sim/world_state.gd`](../sim/world_state.gd)** — la struttura dati della griglia. Nota gli array paralleli.
3. **[`autoload/sim_core.gd`](../autoload/sim_core.gd)** — il tick loop. È l'unico punto in cui il tempo avanza in tutto il progetto.
4. **[`view/camera_controller.gd`](../view/camera_controller.gd)** — gestione touch, e il pinch-zoom ancorato al punto.
5. **[`ui/debug_hud.gd`](../ui/debug_hud.gd)** — safe area e self test a schermo.

Poi [`docs/TDD_00_Architettura.md`](TDD_00_Architettura.md) §5 sui nastri, che è il sistema dello Sprint 1 e quello a rischio più alto.

---

## 14. Le tre cose che ti faranno perdere più tempo

1. **Il tipaggio.** Scrivi `var x := ...` sempre. Il codice untyped è più lento e nessuno ti avvisa quando sbagli un tipo.
2. **Le Callable per valore** (§4). Ti morderà almeno una volta.
3. **Scrivere in `res://`** (§9). Funziona sul PC, fallisce sul telefono.
