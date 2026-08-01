# TDD 01 — Economia e Bilanciamento
### La spina dorsale matematica che tiene insieme difesa, industria e progressione incrementale

> **Documento 2 di 3.** Ogni numero qui è verificato da `tools/balance_sim.py`.
> Output completo: [`BALANCE_REPORT.txt`](BALANCE_REPORT.txt) · Foglio di calcolo: [`balance_reference.csv`](balance_reference.csv)

---

## 1. Il problema da risolvere

Tre generi con tre economie incompatibili:

| Genere | Vuole | Se lo lasci fare |
|---|---|---|
| Tower defense | Difficoltà che cresce nel tempo | Il giocatore ottimizza le torrette e ignora la fabbrica |
| Factory game | Crescita illimitata del throughput | La difficoltà resta indietro e il gioco diventa banale |
| Incrementale | Crescita esponenziale dei numeri | Tutto il resto viene schiacciato dagli ordini di grandezza |

La soluzione non è mediare. È **far dipendere tutte e tre da un'unica grandezza** e poi scegliere *deliberatamente* con quale esponente ciascuna la legge.

---

## 2. Il Valore Industriale (VI)

Ogni materiale ha un **tier di raffinazione** `R` e un `base_value`. Da questi si deriva tutto:

$$\mathrm{VI}(m) = \text{base\_value}(m) \cdot \lambda^{R(m)} \qquad \lambda = 2{,}5$$

| Materiale | R | base | **VI** |
|---|:-:|--:|--:|
| Minerale di Ferro Grezzo | 0 | 1,00 | **1,000** |
| Polvere di Ferro | 1 | 1,00 | **2,500** |
| Polvere di Ferro Purificata | 2 | 1,00 | **6,250** |
| Lingotto di Ferro | 3 | 1,00 | **15,625** |
| Lingotto di Lega Conduttiva | 4 | 1,50 | **58,594** |
| Fanghiglia (sottoprodotto) | 1 | 0,35 | 0,875 |
| Bricchetta di Scoria | 2 | 0,35 | 2,188 |

Il `base_value` è la manopola per differenziare materiali dello stesso tier: il rame vale 1,20 (è il materiale "da dati", più conduttivo), il ferro 1,00 (è il materiale "da struttura"), gli scarti 0,35.

### Perché λ = 2,5 e non 2 o 3

| λ | Vantaggio della catena completa | Effetto |
|---|---|---|
| 2,0 | ×16 | Troppo piatto: la catena a 4 stadi non ripaga le 4 macchine e i 46 kW. Il giocatore usa la scorciatoia. |
| **2,5** | **×32** | **Il salto è evidente al primo sguardo del pannello di analisi, ma il tier 0 resta utilizzabile come munizione d'emergenza.** |
| 3,0 | ×54 | Il tier 0 diventa letteralmente spazzatura, l'esponenziale scappa via e a R=6 servono già i big number. |

---

## 3. Le tre conversioni e la loro asimmetria deliberata

Questa sezione è il cuore del design. Le tre meccaniche leggono lo stesso VI con **tre esponenti diversi**, e la differenza fra questi esponenti *è* il gameplay.

### 3.1 VI → Dati (esponenziale pieno)

$$\dot{D} = \eta_{\text{server}} \cdot \sum_i \left( \text{rate}_i \cdot \mathrm{VI}_i \right)$$

Guadagno del salire di un tier: **`λ^R`**, cioè esponenziale puro. È il motore incrementale.

### 3.2 VI → Danno (polinomiale, sub-esponenziale)

$$M(R) = (R+1)^{\beta} \qquad \beta = \log_2 3 = 1{,}585$$

$$\text{danno inflitto} = \max\left(0{,}15 \cdot d,\ d - A\right), \quad d = d_{\text{base}} \cdot M(R) \cdot (1 + 0{,}06 L_{\text{bal}})$$

Guadagno del salire di un tier: **`(R+1)^1.585`**, polinomiale. **Deliberatamente più debole dei Dati.**

### 3.3 VI → Minaccia (esponenziale attenuato)

$$\mathrm{HP}(n, \Theta) = 150 \cdot (1 + 0{,}22\,n)^{1{,}55} \cdot \left(1 + \frac{\Theta}{20}\right)^{0{,}80}$$

dove `Θ` = VI/s che **arriva effettivamente al Core** (media mobile a 60 s).

Guadagno della minaccia salendo di un tier: **`λ^(0.8R)`**.

### 3.4 Il confronto — la tabella più importante del progetto

| Tier R | Dati ×| Minaccia × | Danno × | **Danno / Minaccia** | **Dati / Minaccia** |
|:-:|--:|--:|--:|--:|--:|
| 1 | 2,50 | 2,08 | 3,00 | **1,44** ✅ | 1,20 |
| 2 | 6,25 | 4,33 | 5,70 | **1,32** ✅ | 1,44 |
| 3 | 15,63 | 9,01 | 9,00 | **1,00** ⚠️ | 1,73 |
| 4 | 39,06 | 18,76 | 12,82 | **0,68** ❌ | 2,08 |

Come si legge, riga per riga:

- **Tier 1–2:** raffinare ti rende *più forte* di quanto ti renda minacciato. Il gioco ti premia mentre ti insegna la meccanica. È il tutorial nascosto nella matematica.
- **Tier 3:** parità esatta. `β = log₂3` è stato scelto proprio per mettere il punto di pareggio sul **Lingotto**, che è il materiale centrale dell'MVP.
- **Tier 4:** raffinare da solo ti manda in **deficit difensivo del 32%**. Non puoi più cavartela salendo di tecnologia.
- **Ultima colonna:** ma i Dati crescono *sempre* più in fretta della minaccia (`λ^0.2R`, +108% a R4). Quel surplus di ricerca è esattamente la risorsa con cui colmi il deficit.

> **Il ciclo virtuoso è questo:** raffini → guadagni Dati più in fretta di quanto guadagni minaccia → spendi i Dati in ricerca → la ricerca copre il deficit difensivo → puoi permetterti il tier successivo.
> Il giocatore non può saltare nessuno dei tre anelli. **È così che "la logistica resta il motore trainante" invece di essere un'affermazione di intenti.**

### 3.5 Il terzo asse: espandere

Se il giocatore **raddoppia la produzione** allo stesso tier:

$$\frac{\text{DPS sostenibile}}{\text{Minaccia}} = \frac{2}{2^{0{,}80}} = 2^{0{,}20} = 1{,}149$$

**+14,9% netto.** Espandere conviene sempre — ma poco. Nessuno dei tre assi (tier, scala, ricerca) basta da solo. È il vincolo che impedisce sia il tower defense statico sia la fabbrica senza rischio.

### 3.6 La costante da non toccare mai

> `threat_industrial_exponent = 0.80`
> Se lo porti a **1,0 o oltre**, espandere la produzione diventa net-negativo: il giocatore impara che costruire fabbrica è un errore, smette di farlo, e il tuo gioco è diventato un tower defense statico. È l'unico numero di `tuning.json` che può distruggere il concept con una modifica di una cifra.
> L'invariante #3 del simulatore esiste solo per proteggere questo valore.

---

## 4. Le catene di raffinazione

### 4.1 Catena completa vs scorciatoia

```
CATENA LUNGA   1 Minerale ─[Trituratore]→ 2 Polvere ─[Purificatore+H₂O]→ 2 Polvere Pura ─[Fornace]→ 2 LINGOTTI
                                                              └────────→ 1 Fanghiglia ─[Compattatore]→ Bricchetta → ENERGIA

SCORCIATOIA    1 Minerale ──────────────[Fornace diretta, ciclo +50%]──────────────────→ 1 LINGOTTO
```

| | Catena lunga | Scorciatoia |
|---|--:|--:|
| Resa per minerale | 2 Lingotti + 1 Fanghiglia | 1 Lingotto |
| VI ottenuto | **32,13** | 15,63 |
| Tipi di macchina | 4 | 2 |
| Fluidi | sì (acqua) | no |
| kW per linea | 46 | 16 |
| **Vantaggio** | **×2,06** | — |

E rispetto al conferire il minerale grezzo direttamente al Core: **×32,1**.

La scorciatoia **deve esistere**: è ciò che permette al giocatore di partire subito, e soprattutto è il metro di paragone che gli fa *vedere* quanto guadagna raffinando. Un vantaggio che non hai misurato non lo percepisci.

### 4.2 Rapporti di linea

I tempi di ciclo non sono stati scelti per "sembrare giusti": sono stati scelti perché producessero **rapporti interi** (invariante #10 del simulatore). Un giocatore su un telefono non deve fare divisioni con la virgola.

| Macchina | Ciclo | Consuma | Produce |
|---|--:|---|---|
| Trivella | 2,0 s | — | 0,500 minerale/s |
| Trituratore | 2,0 s | 0,500 minerale/s | 1,000 polvere/s |
| Purificatore | 2,0 s | 1,000 polvere/s + 60 mB H₂O/s | 1,000 pura/s + 0,50 fanghiglia/s |
| Fornace | 3,0 s | 0,333 pura/s | 0,333 lingotti/s |
| Pompa Idrica | 2,0 s | — | 120 mB/s |

$$\boxed{\;4\ \text{Trivelle} : 4\ \text{Trituratori} : 4\ \text{Purificatori} : 12\ \text{Fornaci} : 2\ \text{Pompe}\;}$$
$$\text{ratio} = 1 : 1 : 1 : 3 : 0{,}5 \qquad \Rightarrow \qquad \textbf{4,00 lingotti/s}$$

Il rapporto **1 : 1 : 1** dei primi tre stadi è pedagogico: il giocatore lo scopre da solo in due minuti e si sente intelligente. Il salto a **3 Fornaci** è la prima vera lezione di ingegneria del gioco — e il momento in cui capisce che deve *contare*, non tirare a indovinare.

### 4.3 Il ciclo chiuso scorie → energia

Non è decorazione: è il pezzo che rende la fabbrica un *sistema* invece di una catena.

```
4 Purificatori → 2,00 fanghiglia/s → 2 Compattatori → 1,00 bricchette/s → 5 Generatori Termici → 300 kW
```

Il tempo di combustione di **5,00 s** per bricchetta non è arbitrario: è l'unico valore che chiude il ciclo **esattamente**, senza sprechi e senza deficit (invarianti #6 e #7). Se lo cambi, il simulatore te lo dice.

### 4.4 Bilancio energetico della base di riferimento

| Edificio | n | kW cad. | kW tot |
|---|--:|--:|--:|
| Trivella | 4 | 6 | 24 |
| Trituratore | 4 | 12 | 48 |
| Purificatore | 4 | 18 | 72 |
| Pompa Idrica | 2 | 8 | 16 |
| Fornace | 12 | 10 | 120 |
| Compattatore | 2 | 14 | 28 |
| Server | 2 | 25 | 50 |
| Torretta Cinetica | 4 | 15 | 60 |
| **DOMANDA** | | | **418** |
| Generatore d'Avvio | 1 | 120 | 120 |
| Generatore Termico | 5 | 60 | 300 |
| **OFFERTA** | | | **420** |

$$\sigma = \min\left(1,\ \tfrac{420}{418}\right) = 1{,}000 \qquad \text{margine: } \mathbf{+0{,}5\%}$$

Margine dello 0,5% **per scelta**. La base di riferimento è al 99,5% di utilizzo: aggiungere una sola macchina manda in brownout. È il momento in cui il giocatore scopre che l'energia è un sistema da progettare, non una casella da spuntare — e lo scopre gradualmente (tutto rallenta un po') invece che brutalmente (tutto si ferma).

---

## 5. La generazione di Dati

| Scenario | item/s | VI/s | **Dati/s** |
|---|--:|--:|--:|
| Minerale grezzo al Core | 2,00 | 2,00 | **2,00** |
| Polvere R1 al Core | 4,00 | 10,00 | **10,00** |
| Polvere pura R2 al Core | 4,00 | 25,00 | **25,00** |
| **Lingotti R3 (base di riferimento)** | **4,00** | **62,50** | **62,50** |
| Lega Conduttiva R4 al Core | 0,67 | 39,08 | **39,08** |

La base di riferimento produce **Θ = 62,5 VI/s**, cioè **×31,2** rispetto al conferire minerale grezzo con le stesse 4 trivelle.

> **Requisito di UI derivato da qui.** Il pannello di analisi deve mostrare in permanenza il confronto *"stai conferendo X → tot Dati/s; con la catena completa → tot Dati/s (×N)"*. Il moltiplicatore ×31 è la lezione centrale del gioco e non può essere lasciato all'intuizione del giocatore.

---

## 6. La difesa

### 6.1 Efficienza delle munizioni — la decisione centrale

Lo stesso lingotto può diventare Dati o proiettili. Quale conviene?

| Tier | Esempio | VI | Molt. danno | **Danno / VI** | **vs corazzato (A=60)** |
|:-:|---|--:|--:|--:|--:|
| 0 | Minerale Grezzo | 1,00 | 1,00 | 1,000 | 1,875 |
| 1 | **Polvere di Ferro** | 2,50 | 3,00 | **1,200** 🥇 | 2,250 |
| 2 | Polvere Purificata | 6,25 | 5,70 | 0,913 | 1,810 |
| 3 | **Lingotto di Ferro** | 15,63 | 9,00 | 0,576 | **3,360** 🥇 |
| 4 | Lega Conduttiva | 58,59 | 12,82 | 0,219 | 1,711 |

Due classifiche opposte, ed è voluto:

- **Contro i bersagli nudi** (Sciami, la maggioranza fino all'ondata 13) la **Polvere R1** è la munizione più efficiente per VI speso. La strategia ottimale è: *spara polvere, manda i lingotti al Core.*
- **Contro i Corazzati** (armatura piatta 60) la classifica si ribalta: il **Lingotto R3** rende quasi 1,5× la polvere. La polvere infligge 5,6 danni a colpo contro 59 del lingotto.

Il giocatore è quindi costretto a mantenere **due catene di raffinazione attive contemporaneamente**, con uno smistamento che manda la polvere alle torrette anti-sciame e i lingotti a quelle anti-corazzato. Questa è la complessità ingegneristica richiesta, ottenuta con **una sola regola** (armatura piatta) invece che con venti sistemi.

Nota emergente: la Lega Conduttiva R4 è **pessima** come munizione (0,219 danno/VI). È un materiale *da Dati*, non da guerra. Non è un bug: è una specializzazione che nasce dalle formule senza che sia stata scritta a mano da nessuna parte.

### 6.2 Curva di sopravvivenza

Verificata dal simulatore su una finestra di ingaggio di 20 celle di corridoio, `Θ = 62,5`:

| Schieramento | DPS ond. 10 | DPS ond. 20 | DPS ond. 40 | mun/s | **Regge fino a** |
|---|--:|--:|--:|--:|:-:|
| L1 · 4 Cinetiche, mun. R1, balistica 0 | 156 | 126 | 105 | 0,80 | **ondata 5** |
| L2 · 4 Cinetiche, mun. R3, balistica 0 | 486 | 431 | 392 | 0,80 | **ondata 16** |
| L3 · 8 Cinetiche, mun. R3, balistica 5 | 1 269 | 1 159 | 1 080 | 1,60 | **ondata 35** |
| L4 · 8 Cin + 4 Frag, mun. R4, balistica 10 | 3 033 | 2 847 | 2 748 | 2,40 | **ondata 67** |
| L5 · 16 Cin + 8 Frag, mun. R4, balistica 20 | 8 353 | 7 944 | 7 746 | 4,80 | **ondata 120** |

E con una fabbrica 5× più grande (`Θ = 312,5`), le stesse ondate richiedono ~3× il DPS — L1 e L2 non bastano nemmeno all'ondata 1.

**I quattro momenti di crisi dell'MVP** (da `waves.json → milestones`):

| Ondata | Cosa si rompe | Cosa deve fare il giocatore |
|:-:|---|---|
| **5** | La munizione R1 smette di bastare | Costruire la Fornace e passare al Lingotto |
| **16** | 4 torrette non bastano più | Raddoppiare la difesa + primi livelli di Balistica |
| **35** | L3 collassa contro i Corazzati | Sbloccare la Fonderia 2×2 e la Frammentazione |
| **50** | Fine dell'arco MVP | Se ci arriva, il prototipo ha dimostrato il suo loop |

Se durante i playtest un giocatore supera l'ondata 20 **senza aver mai costruito un Purificatore**, il bilanciamento è rotto e va corretto prima di qualunque altra cosa.

### 6.3 Il loop di retroazione negativa

Poiché `Θ` misura ciò che **arriva al Core**, bruciare materiale in torretta lo abbassa:

| Munizione usata | VI sottratto/s | Θ residuo | HP ondata 20 | Δ |
|---|--:|--:|--:|--:|
| Polvere di Ferro | 2,00 | 60,50 | 6 239 | −1,9% |
| Polvere Purificata | 5,00 | 57,50 | 6 052 | −4,9% |
| Lingotto di Ferro | 12,50 | 50,00 | 5 579 | **−12,3%** |

Conseguenza sistemica: **il gioco non può entrare in spirale di morte.** Se il giocatore è in difficoltà, brucia materiale più pregiato; questo abbassa automaticamente le ondate successive e gli dà il tempo di riorganizzarsi. Nessun codice di "difficoltà dinamica" — la proprietà emerge dalla scelta di ancorare la minaccia al Core invece che alla produzione lorda.

---

## 7. Ricerca

12 nodi, costo totale **27 120 Dati**.

| # | Nodo | Costo | Prereq | ~tempo |
|--:|---|--:|---|--:|
| 1 | Nastri Rinforzati | 120 | — | 24 s |
| 2 | Punte al Tungsteno | 150 | — | 30 s |
| 3 | **Purificazione a Umido** | 400 | 2 | 80 s |
| 4 | Recupero Scorie | 550 | 3 | 22 s |
| 5 | Calibratura Balistica | 300 | — | 12 s |
| 6 | Bus Dati Parallelo | 900 | 3 | 36 s |
| 7 | Metallurgia Induttiva | 2 400 | 4, 6 | 96 s |
| 8 | Testate a Frammentazione | 1 800 | 5 | 29 s |
| 9 | Uplink Autonomo | 3 000 | 6 | 48 s |
| 10 | Isolamento Criogenico | 3 500 | 4 | 56 s |
| 11 | Protocollo Overclock | 5 000 | 7 | 80 s |
| 12 | Compressione Entropica | 9 000 | 9, 7 | 2,4 min |

Il nodo **3 (Purificazione a Umido)** è il cardine: è dove il gioco smette di essere una fabbrica banale e diventa il gioco che vuoi fare. Va reso impossibile da mancare (tutorial contestuale al primo Trituratore saturo).

**Upgrade ripetibile — Calibratura Balistica:** `C(L) = 300 · 1,35^L`, `+6%` danno additivo per livello.

| Livello | Costo del livello | Cumulato | Bonus |
|--:|--:|--:|--:|
| 5 | 1 345 | 2 986 | +30% |
| 10 | 6 032 | 16 377 | +60% |
| 20 | 121 282 | 345 663 | +120% |
| 30 | 2 438 565 | 6 966 471 | +180% |

Crescita 1,35 con bonus additivo: il classico incrementale sano. Il costo esplode più in fretta del beneficio, quindi c'è sempre un punto in cui conviene smettere di potenziare e ricominciare a **costruire fabbrica**. Che è, di nuovo, il messaggio centrale del gioco.

**Nessun timer di ricerca.** Il collo di bottiglia deve essere la fabbrica.

---

## 8. La ricompensa da combattimento

Poiché il timer delle ondate **avanza anche a gioco chiuso** (§9), respingere un'ondata deve dare qualcosa. Altrimenti l'avanzamento sarebbe solo una punizione per essersi assentati: torneresti a difficoltà più alta e a parità di ricchezza.

$$D_{\text{ondata}} = \kappa \cdot \Theta \cdot \text{intervallo}(n), \qquad \kappa = 0{,}20$$

La scelta cruciale è **cosa** mettere nella formula. La ricompensa **non** è funzione degli HP nemici, ma una frazione di ciò che l'industria produce nel tempo di un'ondata. Ne segue che il combattimento vale una quota **fissa** dei Dati totali:

$$\frac{\kappa}{1+\kappa} = 16{,}7\%$$

a qualunque scala, a qualunque ondata, con qualunque `Θ`. La logistica resta il motore trainante **per costruzione**, non per taratura fortunata — e nessuna modifica futura al bilanciamento può romperlo per sbaglio. (Invariante 14.)

| Ondata | Interv. | D industria | D combatt. | Quota | Mun. VI (R1) | **Netto** |
|--:|--:|--:|--:|--:|--:|--:|
| 5 | 112 s | 7 031 | 1 406 | 16,7% | 19 | **+1 387** |
| 20 | 90 s | 5 625 | 1 125 | 16,7% | 82 | **+1 043** |
| 40 | 60 s | 3 750 | 750 | 16,7% | 205 | **+545** |
| 50 | 45 s | 2 812 | 562 | 16,7% | 281 | **+281** |
| 70 | 45 s | 2 812 | 562 | 16,7% | 456 | **+106** |

Il **netto** (Dati guadagnati meno il VI di munizioni bruciato) resta positivo per tutto l'arco MVP e si assottiglia progressivamente: oltre l'ondata ~68 difendersi diventa un **costo netto**. È una texture di late game voluta — a un certo punto la guerra smette di ripagarsi e devi decidere se vale la pena tenere il fronte così avanzato.

---

## 9. Progressione offline — il Fronte Autonomo

**Il timer delle ondate avanza a gioco chiuso.** Il vincolo "la base non deve mai essere distrutta in mia assenza" resta però intatto, perché l'esito di un'ondata offline non è vittoria-o-sconfitta ma **vittoria-o-stallo**:

| Se la difesa | Esito |
|---|---|
| regge | L'ondata è respinta. Consuma munizioni, dà Dati, il contatore avanza. |
| **non** regge | **STALLO.** Il fronte si blocca su quell'ondata e il timer si ferma lì. La linea tiene, non guadagna terreno, e nulla viene distrutto. |

### La riga che decide se l'idle è davvero sicuro

La minaccia offline va calcolata sul **`Θ` dello snapshot di uscita**, non sul `Θ` ridotto dalla produzione idle. Il perché, in numeri:

| Formula usata offline | Stallo di L3 | Tetto online di L3 | Conseguenza |
|---|:-:|:-:|---|
| `hp_budget(n, Θ × η)` | ondata **49** | ondata 35 | ❌ Rientri 14 ondate oltre ciò che puoi vincere da sveglio. Partita già persa. |
| `hp_budget(n, Θ)` | ondata **35** | ondata 35 | ✅ Coincidono. |

Con la formula corretta vale la regola, comunicabile al giocatore in una frase:

> **L'idle ti porta esattamente al limite della tua difesa attuale, e non un'ondata oltre.**

Protetta dall'invariante 15b, che confronta i due numeri a ogni esecuzione del simulatore.

### Quanto si avanza davvero

8 ore di assenza, partendo dall'ondata 20, `Θ` = 62,5:

| Schieramento | Ondate guadagnate | Arriva a | Causa stallo |
|---|--:|:-:|:-:|
| L1 · 4 Cinetiche, mun. R1 | 0 | 20 | dps |
| L2 · 4 Cinetiche, mun. R3 | 0 | 20 | dps |
| L3 · 8 Cinetiche, mun. R3, bal. 5 | **15** | 35 | dps |
| L4 · 8 Cin + 4 Frag, mun. R4, bal. 10 | **47** | 67 | dps |
| L5 · 16 Cin + 8 Frag, mun. R4, bal. 20 | **116** | 136 | dps |

Progressione monotona e verificata (invariante 16). Questo aggiunge al design **la freccia che mancava**: prima le torrette erano un puro costo, ora determinano quanto lontano arrivi mentre non giochi. Investire in difesa **compra letteralmente avanzamento idle** — ed è così che il terzo genere entra nello strato incrementale invece di restarne fuori.

Nota su L1 e L2: guadagnano zero ondate perché all'ondata 20 sono **già oltre** il proprio tetto. Non è un bug: significa che stavano già perdendo online e l'offline non regala nulla.

### Dati accumulati

| Assenza | η=0,40 cap 8 h | η=0,55 cap 12 h |
|--:|--:|--:|
| 30 min | 46 873 | 65 942 |
| 2 h | 181 873 | 251 567 |
| 8 h | **721 873** | 994 067 |
| 12 h | 721 873 *(capped)* | **1 489 067** |
| 24 h | 721 873 *(capped)* | 1 489 067 *(capped)* |

*(Industria + combattimento − munizioni consumate, scenario L3 dall'ondata 20.)*

Tre vincoli che rendono l'idle sicuro senza renderlo inutile:

1. **Vittoria-o-stallo, mai sconfitta.** La base è invulnerabile. Zero ansia da rientro.
2. **Accredito basato sul throughput risolto**, non sulla produzione teorica: colli di bottiglia, energia insufficiente e silo pieni valgono anche offline. Una fabbrica mal progettata rende poco anche di notte — la competenza del giocatore conta sempre.
3. **Tetto ai silo.** Senza questo l'offline genera risorse infinite e la parte fabbrica muore. Con questo, ampliare lo stoccaggio diventa una scelta idle sensata.

E un costo reale: **le munizioni vengono consumate offline.** Difendersi mentre dormi non è gratis, e questo tiene la scelta centrale del gioco viva anche nello strato idle.

---

## 10. Procedura di ri-bilanciamento

Da usare ogni volta che un playtest ti dice che qualcosa non va.

```bash
# 1. Modifica SOLO data/tuning.json (o le ricette). Mai numeri nel codice.
# 2. Allinea le stesse costanti in tools/balance_sim.py.
# 3. Verifica che il design non si sia rotto:
python3 tools/balance_sim.py --check     # exit 1 = hai rotto un'invariante
# 4. Rileggi le tabelle:
python3 tools/balance_sim.py | less
# 5. Rigenera il foglio di calcolo e il report:
python3 tools/balance_sim.py --csv docs/balance_reference.csv
python3 tools/balance_sim.py > docs/BALANCE_REPORT.txt
```

### Le 17 invarianti di design

| # | Invariante | Protegge |
|--:|---|---|
| 1 | La catena lunga rende ≥ 1,8× la scorciatoia | *"mai catene troppo semplici"* |
| 2 | Raffinare batte il grezzo di ≥ 20× | il senso stesso della raffinazione |
| 3 | **Esponente industriale della minaccia < 1,0** | *"mai un tower defense statico"* |
| 4 | Almeno un tier alto va in deficit difensivo | obbliga a espandere, non solo a techare |
| 5 | I Dati superano la minaccia salendo di tier | il giocatore può vincere |
| 6 | Il ciclo scorie→energia si autoalimenta | il sistema è chiuso |
| 7 | Il ciclo scorie non produce surplus sprecato | niente scarti morti |
| 8 | Offerta energetica ≥ domanda nella base rif. | la base di riferimento è giocabile |
| 9 | Margine energetico ≤ 30% | l'energia resta un problema da risolvere |
| 10 | R1 più efficiente di R3 contro bersagli nudi | la scelta munizione è reale |
| 11 | Contro i corazzati la classifica si ribalta | due catene sempre attive |
| 12 | Primo nodo di ricerca entro 60 s | l'aggancio iniziale |
| 13 | I rapporti di linea sono numeri interi | leggibilità su schermo piccolo |
| 14 | **I Dati da combattimento ≤ 25% del totale** | *"la logistica è il motore trainante"* |
| 15 | Dopo 24 h offline il fronte si blocca | *"la base non viene distrutta in mia assenza"* |
| 15b | **Lo stallo offline ≤ tetto difensivo online** | non rientri in una partita già persa |
| 16 | Offline: più difesa = più avanzamento (monotono) | la difesa entra nello strato idle |
| 17 | Difendersi resta profittevole fino all'ondata 50 | l'arco MVP non punisce chi combatte |

Stato attuale: **17/17 soddisfatte.**

---

## 11. Manopole di tuning, in ordine di pericolosità

| Costante | Valore | Se la tocchi |
|---|--:|---|
| `threat_industrial_exponent` | 0,80 | ☠️ **A ≥ 1,0 il gioco diventa un tower defense statico.** Non toccare. |
| `lambda_vi` | 2,5 | ⚠️ Cambia l'intera scala economica. Ricalcola tutti i costi di ricerca. |
| `beta_ammo` | 1,585 | ⚠️ Sposta il punto di pareggio difensivo. Più alto = gioco più permissivo. |
| `wave_growth_p` | 1,55 | 🔶 Ripidità della pressione temporale. La manopola giusta se "è troppo facile/difficile nel tempo". |
| `hp_base_b0` | 150 | 🟢 Difficoltà globale. **La prima manopola da usare** dopo un playtest. |
| `offline_threat_uses_online_theta` | `true` | ☠️ **Se lo metti a `false`, l'idle avanza oltre il tuo tetto difensivo e rientri in una partita persa.** Non toccare. |
| `kappa_combat_data` | 0,20 | 🔶 Quota dei Dati da combattimento, fissa a `κ/(1+κ)`. A 0,33 il combattimento arriva al 25%: è il tetto oltre il quale l'invariante 14 fallisce. |
| `offline_efficiency` | 0,40 | 🟢 Sicura. Ritmo del ritorno. |
| `corridor_tiles_reference` | 20 | 🟢 Sicura. Quanto premia la difesa in profondità. |

---

**Prosegui con:** [`TDD_02_Roadmap_MVP.md`](TDD_02_Roadmap_MVP.md) — l'ordine in cui costruire tutto questo.
