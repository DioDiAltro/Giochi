# TDD 02 — Roadmap MVP
### 7 sprint, ordinati per rischio decrescente

> **Documento 3 di 3.** Questo è il file da tenere aperto mentre programmi.

---

## Principio di ordinamento

Gli sprint **non** sono ordinati per facilità né per "cosa si vede prima". Sono ordinati così:

> **Prima ciò che, se non funziona, uccide il progetto.**

Il rischio più grande non è "i nastri sono lenti": è **"le tre meccaniche non si incastrano e il gioco non è divertente"**. Quindi il verticale completo (una catena a 4 stadi che alimenta contemporaneamente una torretta e un server) va chiuso **entro lo Sprint 4**, quando è ancora economico buttare via tutto.

Grafica, effetti, audio, menu: tutto dopo. Un prototipo brutto che dimostra il loop vale cento volte un prototipo bello che non lo dimostra.

---

## Sprint 0 — Fondamenta ✅ CODICE SCRITTO E VERIFICATO

**Obiettivo:** un progetto Godot che si avvia su un telefono vero e legge i dati di bilanciamento.

- [x] Progetto Godot 4.4, renderer **Mobile**, 1080×1920, stretch `canvas_items` / `expand`, orientamento verticale → `project.godot`
- [x] Rispetto della safe area (`DisplayServer.get_display_safe_area()`, con conversione schermo→viewport) → `ui/debug_hud.gd`
- [x] Autoload `Database.gd`: carica `res://data/*.json`, espone `vi()`, `tier()`, `ammo_multiplier()`, `recipe()`, `building()`, con cache precalcolate
- [x] Autoload `SimCore.gd`: tick loop a 20 Hz con accumulatore, cap anti-spirale, `tick_alpha()` per l'interpolazione, telemetria `ms/tick`
- [x] Autoload `EventBus.gd`: segnali di comando e notifica già dichiarati
- [x] `WorldState` con `terrain`, `building_at`, `buildings` in array paralleli + generazione deterministica dei giacimenti
- [x] Camera 2D con pan a un dito, pinch-zoom **ancorato al punto** e clamp sulla mappa
- [x] `GridRenderer` con culling sul rettangolo visibile (nessun asset richiesto)
- [x] Pannello diagnostico a schermo: self test + i tre KPI del §14 misurati dal giorno uno
- [x] `tools/check_all.sh`: invarianti Python + validità JSON + self test dell'engine in un comando
- [ ] **Una build installata su un device fisico** entro il giorno 2 → serve il tuo Mac/keystore, vedi [`SETUP_EXPORT.md`](SETUP_EXPORT.md)

**Fatto quando:** sul tuo telefono vedi una griglia che puoi muovere e zoomare, e la console stampa `tier(ingot_iron) = 3, vi = 15.625` letto dal JSON.

Stato verificato in headless su Godot 4.4.1:

```
tier(ingot_iron) = 3, vi = 15.625
16/16 superati
OK    mondo generato: ferro 270, rame 125, acqua 201, roccia 35
OK    tick loop: 19 tick in 1.00 s (attesi 20, 20 Hz)
```

> ⚠️ **L'unica casella rimasta è anche la più importante.** Se salti la build su device fisico in questo sprint, scoprirai i problemi di touch, safe area e firma allo Sprint 6, quando costeranno dieci volte tanto.

> ⚠️ **Trappola già disinnescata:** Godot non importa i `.json` come risorse. Senza il filtro `data/*.json` nel preset di esportazione, la build sul telefono parte **senza dati**. Il pannello diagnostico mostra un banner rosso a tutto schermo se succede — ma è meglio impostare il filtro subito ([`SETUP_EXPORT.md`](SETUP_EXPORT.md) §3).

---

## Sprint 1 — Logistica (1 settimana) 🔴 RISCHIO MASSIMO

**Obiettivo:** far scorrere oggetti su nastri costruiti col dito. È il sistema che decide se il gioco è tecnicamente fattibile e se è piacevole al tatto.

- [ ] Piazzamento su griglia con validazione + ghost colorato (verde/rosso) + aptica una-tantum
- [ ] **Drag-to-build** dei nastri con auto-instradamento a L e badge del costo spostato 60 px sopra il dito
- [ ] `BeltLane` con `PackedByteArray`, accumulatore fixed-point, scansione testa→coda
- [ ] Ricostruzione delle corsie su modifica (unione/divisione a curve e innesti)
- [ ] `ItemRenderer` con `MultiMeshInstance2D`, `visible_instance_count`, interpolazione via `tick_alpha()`
- [ ] Trivella + Silo, sorgente e pozzo, per vedere gli item scorrere
- [ ] Pulsante **ANNULLA** a comparsa per 5 s dopo ogni costruzione

**Fatto quando:**
1. Costruisci 200 celle di nastro con **un solo trascinamento del pollice** e non è frustrante.
2. 2 000 item scorrono a 60 fps sul device fisico.
3. `ms/tick` del `BeltSystem` misurato e annotato.

> **Checkpoint di feeling.** Fai provare il drag-to-build a una persona che non ha mai visto un factory game. Se sbaglia il tracciato più di una volta su tre, ridisegna l'interazione prima di andare avanti. Questo è il momento di scoprirlo.

---

## Sprint 2 — Produzione a stadi multipli (1 settimana)

**Obiettivo:** la catena completa a 4 stadi che funziona davvero.

- [ ] `MachineSystem` con la macchina a stati `IDLE / WORKING / BLOCKED`
- [ ] Trituratore, Fornace (+ ricetta scorciatoia penalizzata), Purificatore
- [ ] **Output multipli con espulsione atomica** (prodotto + fanghiglia insieme o niente)
- [ ] Porte di I/O orientate e rotazione degli edifici (two-finger tap)
- [ ] `FluidSystem`: Pompa, condotti, rete a volume unico, frazione `φ`
- [ ] Ripartitore con modalità round-robin / priorità / filtro (bottom sheet, nessun drag di precisione)
- [ ] Bottom sheet ispettore su tap: ricetta, buffer, stato, throughput reale

**Fatto quando:** la linea `4 Trivelle : 4 Trituratori : 4 Purificatori : 12 Fornaci : 2 Pompe` produce **4,00 lingotti/s misurati** — lo stesso numero della Tabella 3 del simulatore. Se non coincide, hai un bug, non una scelta di design.

---

## Sprint 3 — Energia e sistemi chiusi (4-5 giorni)

**Obiettivo:** l'energia come vincolo ingegneristico, non come casella.

- [ ] `PowerSystem`: reti via flood-fill, `σ = min(1, offerta_eff / domanda)`, perdite per distanza
- [ ] Pali elettrici con raggio 6, costruibili a trascinamento
- [ ] Generatore d'Avvio (unico, indistruttibile) + Generatore Termico a bricchette
- [ ] Compattatore → **il ciclo scorie → energia si chiude**
- [ ] Barra `σ` nell'HUD + evidenziazione delle macchine in brownout

**Fatto quando:** costruisci la base di riferimento (418 kW di domanda, 420 di offerta), `σ = 1,00`, e aggiungendo **una sola** Fornace vedi tutto rallentare in modo proporzionale e leggibile — senza che niente si fermi.

---

## Sprint 4 — Il verticale completo (1 settimana) 🔴 IL MOMENTO DELLA VERITÀ

**Obiettivo:** difesa + dati + ricerca collegati. Alla fine di questo sprint sai se il gioco funziona.

- [ ] `FlowField` con Dijkstra pesato su `WorkerThreadPool`, debounce 500 ms
- [ ] Muri che **aumentano il costo del percorso** invece di bloccarlo
- [ ] Nemici: Sciame, Volante (ignora il flow field), Corazzato — `MultiMesh`, griglia spaziale 8×8
- [ ] Torretta Cinetica con **munizione a tier variabile**: `danno = base · (R+1)^1.585`
- [ ] Direttore delle ondate con budget HP calcolato e `Θ` a media mobile 60 s
- [ ] Rack Server: consuma solidi → Dati proporzionali al VI
- [ ] Laboratorio: grafo a nodi scorrevole, i 12 nodi di `research.json`, acquisto istantaneo
- [ ] Fonderia a Induzione 2×2 (primo multi-blocco, 3 input eterogenei)
- [ ] Torretta a Frammentazione
- [ ] **Pannello di analisi** con il confronto *"stai conferendo X → N Dati/s; con la catena completa → M Dati/s (×31)"*

**Fatto quando — e questi sono i criteri più importanti dell'intero progetto:**
1. Arrivi all'**ondata 5** con munizione R1 e **perdi**. Poi passi al Lingotto R3 e superi la 16. La curva del simulatore si verifica nel gioco vero.
2. Il pannello mostra ×31 fra grezzo e catena completa.
3. Un playtester che **non** costruisce il Purificatore **non** supera l'ondata 20.

> Se il criterio 3 fallisce, **fermati e ribilancia**. È l'unica prova che *"la logistica è il motore trainante"* sia vera nel gioco e non solo nel documento.

---

## Sprint 5 — Idle, persistenza, rientro (4-5 giorni)

**Obiettivo:** il gioco sopravvive alla chiusura dell'app.

- [ ] `ProductionGraph.resolve()`: Kahn + 3 passate per i cicli di retroazione
- [ ] `SaveManager`: binario su `WorkerThreadPool`, autosave 30 s, **`version` + catena di migrazioni dal giorno uno**
- [ ] `OfflineSolver`: throughput risolto × `t` × `η`, **limitato dalla capacità dei silo**
- [ ] **Fronte Autonomo**: il timer ondate avanza offline, le ondate si risolvono una per una
- [ ] `defense_snapshot()` salvato all'uscita: DPS per archetipo + danno per munizione
- [ ] **Stallo invece di sconfitta**: quando la difesa non regge, il fronte si blocca e la base resta intatta
- [ ] Minaccia offline calcolata sul **`Θ` online**, non su `Θ × η` (vedi TDD 00 §11, riquadro)
- [ ] Consumo reale delle munizioni offline
- [ ] Ricompensa per ondata respinta: `D = 0,20 · Θ · intervallo(n)`
- [ ] Controllo di integrità del tempo (`dt < 0 → 0`)
- [ ] Popup di rientro stile Upload Lab: **4 punti obbligatori** (tempo, ondate respinte, munizioni consumate, causa dello stallo)
- [ ] Abilità **Overclock** (×2,5 / 45 s / CD 10 min / +25% domanda energetica)

**Fatto quando:** chiudi l'app all'ondata 20 con lo schieramento L3 (8 Cinetiche, munizione R3, balistica 5), aspetti 30 minuti reali, riapri e trovi:
- **15 ondate respinte**, sei all'**ondata 35**, con causa dello stallo `dps`;
- **~46 900 Dati** e **~3 980 VI di munizioni consumate** — i valori della Tabella 12;
- e l'ondata 35 è **esattamente** il tetto che quello schieramento regge anche online.

L'ultimo punto è il criterio critico: se offline avanzi oltre il tuo tetto online, hai sbagliato la riga del `Θ` e il giocatore rientrerà in una partita già persa.

---

## Sprint 6 — Rifinitura e misurazione (1 settimana)

**Obiettivo:** portarlo allo stato "lo faccio provare a qualcuno".

- [ ] Onboarding contestuale: si attiva quando il Trituratore si satura, non all'avvio
- [ ] Tutorial obbligato fino al nodo **Purificazione a Umido**
- [ ] Feedback: schermo che pulsa quando il Core è colpito, numeri di danno, riepilogo di fine ondata
- [ ] Audio minimo: piazzamento, colpo, ondata in arrivo, ricerca sbloccata
- [ ] **Profilazione sul device più lento che hai** e verifica dei tre KPI
- [ ] Object pooling per proiettili ed effetti
- [ ] Schermata di sconfitta del settore che **preserva la Ricerca**

**KPI di uscita (non negoziabili):**

| Metrica | Target |
|---|---|
| `ms/tick` di `SimCore` (p90) | < 5 ms |
| Draw call per frame | < 40 |
| Frame peggiore su 60 s | < 33 ms |
| Memoria | < 250 MB |
| Sessione media in playtest | > 12 min |
| Playtester che arrivano all'ondata 20 | > 60% |
| Playtester che costruiscono il Purificatore | **100%** |

---

## Riepilogo

| Sprint | Durata | Rischio | Consegna |
|:-:|:-:|:-:|---|
| 0 | 3-4 g | 🟢 | Build su device, dati caricati |
| 1 | 1 sett | 🔴 | Nastri col dito, 2 000 item a 60 fps |
| 2 | 1 sett | 🟠 | Catena a 4 stadi, 4,00 lingotti/s |
| 3 | 4-5 g | 🟢 | Energia e ciclo chiuso |
| 4 | 1 sett | 🔴 | **Il loop completo dimostrato** |
| 5 | 4-5 g | 🟠 | Idle sicuro e persistenza |
| 6 | 1 sett | 🟢 | Giocabile da terzi |

**Totale: ~6 settimane** a tempo pieno, ~10-12 a tempo parziale.

---

## Ordine dei primi tre giorni

Se vuoi scrivere codice entro un'ora:

1. **Oggi:** progetto Godot + `Database.gd` che carica `data/tuning.json` e stampa `vi("ingot_iron") = 15.625`. Fine. Nient'altro.
2. **Domani:** `SimCore` a 20 Hz + griglia + camera con pan/pinch. Build sul telefono.
3. **Dopodomani:** prima `BeltLane` con item finti che scorrono, disegnata con `MultiMeshInstance2D`.

Dal quarto giorno sei dentro lo Sprint 1 e il progetto è vivo.

---

## Fuori scope MVP

Da tenere in un `POST_MVP.md`, **mai nel codice** finché lo Sprint 6 non è chiuso:

Voltaggi e amperaggio · gas e vapore · multi-blocchi 3×3+ · schematics e copia-incolla di aree · unità robotiche RTS · settori multipli e mappa mondo · prestige / reset · nemici con abilità speciali · meteo · multiplayer · monetizzazione.

Ognuna di queste è una buona idea. Ognuna, aggiunta prima dello Sprint 6, ti costa il prototipo.
