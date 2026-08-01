# Factory-Defense Incrementale a Nodi
### Specifiche tecniche per il prototipo MVP — Godot 4.x / iOS + Android

Un gioco che unisce la logistica su griglia e la difesa attiva di **Mindustry**, la profondità di raffinazione di **Minecraft moddato tech**, e la progressione a nodi/idle di **Upload Lab**.

---

## Da dove partire

| Se vuoi… | Apri |
|---|---|
| **Scrivere codice adesso** | [`docs/TDD_02_Roadmap_MVP.md`](docs/TDD_02_Roadmap_MVP.md) → "Ordine dei primi tre giorni" |
| Capire come è fatto il software | [`docs/TDD_00_Architettura.md`](docs/TDD_00_Architettura.md) |
| Capire perché i numeri sono quelli | [`docs/TDD_01_Economia_Bilanciamento.md`](docs/TDD_01_Economia_Bilanciamento.md) |
| Rileggere la visione originale | [`Game_Design_Document_Ibrido.md`](Game_Design_Document_Ibrido.md) |
| Lo schema dei salvataggi | [`docs/SAVE_SCHEMA.md`](docs/SAVE_SCHEMA.md) |
| Il foglio di calcolo | [`data/balance_reference.csv`](data/balance_reference.csv) |

---

## L'idea in un paragrafo

Estrai minerale, lo raffini attraverso **quattro stadi** (triturazione → lavaggio con acqua → fusione → lega in multi-blocco), e poi affronti **una sola scelta, continuamente**: mandare il materiale raffinato al Core, che lo converte in **Dati** per l'albero della ricerca, oppure bruciarlo come **munizione** nelle torrette per sopravvivere all'ondata in arrivo.

Le ondate scorrono di continuo, **anche a gioco chiuso**. La base però non può essere distrutta: quando la difesa non ce la fa più il fronte si **blocca** su quell'ondata invece di cedere. Ne segue la regola che tiene insieme l'idle e la difesa: *l'idle ti porta esattamente al limite della tua difesa attuale, e non un'ondata oltre.*

## Come le tre meccaniche si incastrano matematicamente

Ogni materiale ha un **tier di raffinazione** `R` da cui si deriva il **Valore Industriale**: `VI = base · 2,5^R`. Le tre meccaniche leggono lo stesso VI con **tre esponenti diversi**, e la differenza fra questi esponenti *è* il gameplay:

| Tier | Dati × | Minaccia × | Danno × | Danno/Minaccia | Dati/Minaccia |
|:-:|--:|--:|--:|--:|--:|
| 1 | 2,50 | 2,08 | 3,00 | **1,44** ✅ | 1,20 |
| 2 | 6,25 | 4,33 | 5,70 | **1,32** ✅ | 1,44 |
| 3 | 15,63 | 9,01 | 9,00 | **1,00** ⚠️ | 1,73 |
| 4 | 39,06 | 18,76 | 12,82 | **0,68** ❌ | 2,08 |

Raffinare ti premia all'inizio, va in pareggio al Lingotto e ti manda in **deficit difensivo** alla Lega — ma ti dà sempre più Ricerca di quanta Minaccia generi. Il giocatore è costretto a muovere **tutti e tre** gli assi: salire di tier, ampliare la fabbrica, spendere in ricerca. Nessuno basta da solo.

La minaccia è ancorata al VI/s che **arriva al Core**, con esponente `0,80 < 1`. Due conseguenze:
- espandere la produzione è sempre net-positivo (`+14,9%` a ogni raddoppio);
- bruciare materiale come munizione **abbassa** le ondate future — il sistema ha una retroazione negativa e non può entrare in spirale di morte.

E la difesa non è solo un costo: le ondate avanzano anche offline, fino a bloccarsi al limite di ciò che le tue torrette reggono. Investire in difesa **compra avanzamento idle**.

| Schieramento | Ondate guadagnate in 8 h offline |
|---|--:|
| 8 Cinetiche, munizione R3, balistica 5 | **15** → ondata 35 |
| 8 Cin + 4 Frag, munizione R4, balistica 10 | **47** → ondata 67 |
| 16 Cin + 8 Frag, munizione R4, balistica 20 | **116** → ondata 136 |

Derivazione completa: [`docs/TDD_01_Economia_Bilanciamento.md`](docs/TDD_01_Economia_Bilanciamento.md) §3 e §9.

---

## Il simulatore di bilanciamento

Nessun numero di questo progetto è stato inventato. Sono tutti verificati da:

```bash
python3 tools/balance_sim.py            # 13 tabelle di bilanciamento
python3 tools/balance_sim.py --check    # 17 invarianti di design (exit 1 se rotte)
python3 tools/balance_sim.py --csv data/balance_reference.csv
```

Le **invarianti di design** sono il pezzo che protegge il progetto nel tempo. Esempi:

```
[OK]   La catena lunga rende almeno 1.8x la scorciatoia (attuale: 2.06x)
[OK]   Raffinare batte il minerale grezzo di >=20x (attuale: 32.1x)
[OK]   Esponente industriale della minaccia < 1 -> espandere conviene (0.80)
[OK]   Almeno un tier alto va in deficit difensivo -> obbliga a espandere (R4: 0.68)
[OK]   Il ciclo scorie->energia si autoalimenta (1.00 prodotte vs 1.00 richieste)
[OK]   Margine energetico <= 30% -> l'energia resta un problema da ingegnerizzare (0%)
[OK]   Contro i corazzati la classifica si ribalta (R3 3.360 > R1 2.250)
[OK]   I Dati da combattimento restano <=25% del totale a ogni ondata (max 16.7%)
[OK]   Dopo 24h offline il fronte si blocca invece di correre (ondata 35, causa: dps)
[OK]   Lo stallo offline non supera il tetto difensivo online (offline 35 <= online 35)
```

Stato attuale: **17/17**. Se cambi un numero in `data/tuning.json` e un'invariante fallisce, hai rotto il concept — non un dettaglio.

---

## Contenuto dell'MVP

**2 minerali** (ferro, rame) + **1 fluido** (acqua) · **catena a 4 stadi** con sottoprodotto e ciclo energetico chiuso · **1 multi-blocco 2×2** con 3 input eterogenei · **2 torrette** con munizione a tier variabile · **3 archetipi nemici** · **12 nodi di ricerca** + 1 upgrade ripetibile · **idle offline** a 8 h con ondate risolte e base invulnerabile · **abilità Overclock**.

La linea di riferimento — `4 Trivelle : 4 Trituratori : 4 Purificatori : 12 Fornaci : 2 Pompe` — produce **4,00 lingotti/s**, consuma **418 kW** su **420** disponibili, e genera **62,5 Dati/s**: ×31 rispetto a conferire minerale grezzo con le stesse trivelle.

Curva di sopravvivenza verificata: 4 torrette con polvere reggono fino all'**ondata 5**; con lingotti fino alla **16**; 8 torrette + ricerca fino alla **35**; l'assetto completo di fine MVP fino alla **67**.

---

## Struttura

```
├── docs/          TDD architettura · economia · roadmap · schema salvataggi · report
├── data/          JSON pronti da copiare in res://data/ + foglio di calcolo CSV
└── tools/         simulatore di bilanciamento e invarianti di design
```

**Regola operativa:** nessun numero di bilanciamento viene scritto a mano in GDScript. Tutto si carica da `res://data/*.json`.
