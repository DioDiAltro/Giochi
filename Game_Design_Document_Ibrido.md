# Game Design Document: Progetto Ibrido (Mindustry + Minecraft Tech + Upload Lab)

## 1. Descrizione dei Giochi Ispiratori

### Mindustry
Mindustry è un gioco sandbox che ibrida le meccaniche dei *tower defense* con quelle dell'automazione di fabbrica (simile a Factorio). Il giocatore deve estrarre risorse naturali, creare complesse reti di nastri trasportatori per la logistica e rifornire torrette difensive con munizioni e liquido refrigerante per respingere ondate crescenti di nemici. Presenta anche meccaniche RTS (Real-Time Strategy) per controllare unità robotiche, gestire schemi (schematics) per costruire rapidamente e un gameplay molto votato all'ottimizzazione degli spazi.

### Minecraft Moddato Tech (GregTech, Create, IndustrialCraft, ecc.)
Le mod "tech" di Minecraft si distinguono per la loro estrema profondità nell'elaborazione dei materiali e l'ingegneria dei sistemi. A differenza della semplice "cottura in fornace" del gioco base, i minerali devono passare attraverso processi multipli: triturazione, lavaggio, centrifugazione e fusione in altoforno per massimizzare la resa. Introducono concetti di reti elettriche complesse (voltaggio, amperaggio, perdita di energia sui cavi), macchinari multi-blocco giganti, gestione avanzata di fluidi e gas, e un senso di progressione tecnologica molto stratificato.

### Upload Lab / Upload Simulator
Upload Lab (e i vari capitoli di Upload Simulator) è un gioco di tipo incrementale (factory-idle) basato sull'ottimizzazione di nodi, gestione dati e potenziamento di hardware informatico. Il focus è sul generare "dati", accumulare crediti, ricercare tecnologie all'interno di un laboratorio, usare abilità attive (come l'hacking) per accelerare la produzione e scalare il proprio setup informatico. È caratterizzato da un'interfaccia molto pulita basata su nodi interconnessi e meccaniche studiate per una progressione costante (spesso giocabile comodamente con una mano).

---

## 2. Il Tuo Gioco: Concept e Visione

Il tuo progetto si delinea come un **Factory-Defense Incrementale a Nodi**, progettato appositamente per dispositivi mobili e cross-platform (Android e iOS).

**Obiettivo del gioco:** Difendere un Core/Server centrale da ondate di attacchi nemici costruendo una fabbrica di difesa fisica e, parallelamente, processare dati per sbloccare un immenso albero delle tecnologie incrementale.

### Regole e Meccaniche di Base (Il "Core Loop")

1. **Estrazione e Difesa Attiva (Stile Mindustry):**
   * Il gioco si svolge su una griglia 2D.
   * Il giocatore posiziona trivelle sui giacimenti.
   * Le risorse viaggiano su nastri trasportatori visibili.
   * Bisogna posizionare torrette ai confini della base; queste torrette devono essere costantemente alimentate con i materiali giusti o con energia per funzionare contro i nemici.

2. **Raffinazione e Ingegneria Complessa (Stile Minecraft Moddato):**
   * Per creare munizioni avanzate o componenti per l'upgrade del server, i materiali base non bastano.
   * **Esempio di catena di montaggio:** Il "Rame Grezzo" non va direttamente nella torretta, ma deve passare per un *Trituratore*, poi lavato in un *Purificatore* (che richiede input di acqua), e infine cotto in una *Fornace* per ottenere *Lingotti*.
   * **Macchinari Multi-blocco:** Per le tecnologie avanzate (es. un Reattore), il giocatore dovrà costruire strutture che occupano più caselle e richiedono diversi input simultanei (fluidi, energia, materiali solidi).

3. **Progressione Incrementale e Laboratorio (Stile Upload Lab):**
   * Una parte della fabbrica deve essere dedicata a "macchinari di calcolo" (Server).
   * Più risorse complesse e processate invii al Core, più "Dati" e "Potenza di Calcolo" generi.
   * I Dati vengono spesi in un menu speciale, il **Laboratorio**, per sbloccare upgrade permanenti e incrementali: nastri più veloci, torrette che fanno l'1% in più di danno ogni livello, sblocco di nuove ricette.
   * Presenza di abilità "Hack/Overclock" attivabili con un tap per velocizzare temporaneamente tutta la fabbrica.

### Meccaniche Mobile-First (Regole di Sviluppo per iOS e Android)

* **Controlli Touch Intuitivi:** La costruzione dei nastri deve avvenire trascinando il dito (swipe/drag). Evita interfacce che richiedono troppa precisione; usa uno snap-to-grid marcato.
* **Progressione Offline (Idle):** Essendo su mobile, quando il gioco è chiuso la fabbrica deve generare "Dati di background" e accumulare risorse in base al tasso di produzione calcolato al momento dell'uscita, ma *senza* che i nemici distruggano la base mentre il giocatore non c'è.
* **Ottimizzazione Prestazioni:** Su mobile troppi oggetti separati rallentano il gioco. Usa meccaniche che raggruppano le risorse visive sui nastri (object pooling).
* **Interfaccia Pulita (UI):** I menu delle costruzioni (Difesa, Logistica, Energia, Server) in basso per il pollice, albero delle ricerche in finestre pop-up scorrevoli.

---

## 3. Primi Passi per lo Sviluppo

1. **Scelta del Game Engine:** Ti consiglio fortemente **Godot Engine** (eccellente per il 2D e con esportazione semplice per iOS/Android) oppure **Unity**.
2. **Prototipazione del Loop Base:** Inizia creando un estrattore che manda rocce a un trituratore, e dal trituratore a un "server" che ti dà 1 punto ricerca al secondo.
3. **Bilanciamento a Fogli di Calcolo:** Per gestire la parte stile "Upload Lab" e i processi complessi stile "Minecraft moddato", usa un file Excel per mappare quanto tempo e quante risorse richiede ogni singolo processo, per evitare colli di bottiglia o un gioco troppo facile.
