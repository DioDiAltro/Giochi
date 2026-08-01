# Setup e Esportazione — Sprint 0

Cosa serve per avere il progetto sul tuo telefono entro il giorno 2 dello Sprint 0.

> **Onestà preliminare:** la parte di firma (keystore Android, certificati Apple) richiede le **tue** credenziali e non può essere preconfigurata nel repo. Qui trovi la sequenza esatta di comandi e impostazioni; i segreti li metti tu, e `export_presets.cfg` è nel `.gitignore` apposta perché contiene la password del keystore.

---

## 1. Aprire il progetto

Scarica **Godot 4.4.x standard** (non .NET, non serve C#) da [godotengine.org](https://godotengine.org/download).

La radice del progetto Godot **coincide con la radice del repo**: apri direttamente `Giochi/project.godot`. Non c'è una sottocartella separata — così `res://data/` è esattamente la cartella `data/` versionata, e non esistono due copie dei numeri di bilanciamento da tenere allineate.

Al primo avvio Godot crea `.godot/` (già in `.gitignore`).

**Verifica immediata:** premi F5. Devi vedere la griglia e, in alto, il pannello diagnostico con `16/16 — i dati coincidono con balance_sim.py`. In console:

```
tier(ingot_iron) = 3, vi = 15.625
```

---

## 2. Verifica da riga di comando

Prima di ogni commit:

```bash
export GODOT=/percorso/al/binario/godot        # una volta per sessione
./tools/check_all.sh
```

Esegue le 17 invarianti di design, valida i JSON e lancia il self test dell'engine (dati + tick loop). Esce con codice 1 se qualcosa si rompe: piazzalo in un hook di pre-commit e non potrai più rompere il bilanciamento senza accorgertene.

Solo l'engine:

```bash
godot --headless --path . -- --selftest
```

---

## 3. ⚠️ Il filtro di esportazione — leggi questo prima di esportare

**Godot non importa i file `.json` come risorse.** Sono "file non-risorsa", e per finire dentro il pacchetto esportato devono essere elencati esplicitamente in un filtro. Se lo dimentichi, la build sul telefono parte **senza nessun dato di bilanciamento**: nessun materiale, nessuna ricetta, nessun edificio.

In **Progetto → Esporta → (preset) → Risorse**, nel campo **"Filtri per esportare file non-risorsa"** metti:

```
data/*.json
```

Il progetto ha una rete di sicurezza: se i dati non si caricano, il pannello diagnostico mostra un banner rosso a tutto schermo con questa istruzione. Su un telefono non hai una console, quindi l'errore deve gridare — ma è molto meglio non causarlo.

---

## 4. Android

### Una tantum

1. Installa **Android Studio** (serve solo per l'SDK) e un **JDK 17**.
2. In Android Studio → SDK Manager, installa gli SDK Platform-Tools e almeno una piattaforma recente.
3. In Godot: **Editor → Impostazioni Editor → Esporta → Android**, imposta il percorso dell'**Android SDK** e del **Java SDK**.
4. Crea il keystore di debug:

```bash
keytool -keyalg RSA -genkeypair -alias androiddebugkey \
  -keypass android -keystore debug.keystore -storepass android \
  -dname "CN=Android Debug,O=Android,C=US" -validity 9999 \
  -deststoretype pkcs12
```

   Poi in **Impostazioni Editor → Esporta → Android → Debug Keystore** indica il file appena creato (utente `androiddebugkey`, password `android`).

5. **Editor → Gestisci modelli di esportazione** → scarica i template della tua versione esatta di Godot.

### Preset

**Progetto → Esporta → Aggiungi → Android**, poi:

| Impostazione | Valore | Perché |
|---|---|---|
| Filtri file non-risorsa | `data/*.json` | **obbligatorio**, vedi §3 |
| Texture Format → ETC2 ASTC | attivo | già impostato in `project.godot` |
| Architetture | `arm64-v8a` | l'unica richiesta dal Play Store dal 2019 |

Le altre voci lasciale ai default di Godot 4.4 salvo motivi specifici.

### Installare sul device

Abilita **Opzioni sviluppatore → Debug USB** sul telefono, collegalo e usa il pulsante **"Esegui su dispositivo remoto"** (icona a forma di telefono in alto a destra nell'editor): compila, installa e avvia in un colpo solo. È il modo più rapido per iterare.

In alternativa: `Esporta progetto` → `.apk` → `adb install -r build.apk`.

---

## 5. iOS

**Serve un Mac con Xcode.** Non ci sono alternative supportate.

1. **Editor → Gestisci modelli di esportazione** → template della tua versione.
2. **Progetto → Esporta → Aggiungi → iOS**. Compila `Bundle Identifier` (es. `com.tuonome.factorydefense`), `Team ID` e il profilo di provisioning.
3. Filtri file non-risorsa: `data/*.json` (§3).
4. L'esportazione produce un **progetto Xcode**, non un `.ipa`. Aprilo, seleziona il tuo team in *Signing & Capabilities*, e premi Run col telefono collegato.

Un **Apple ID gratuito** basta per installare sul tuo dispositivo (l'app scade dopo 7 giorni). Per TestFlight serve l'**Apple Developer Program** (99 $/anno).

### Orientamento e safe area

`project.godot` imposta già l'orientamento verticale e il progetto legge `DisplayServer.get_display_safe_area()`. Sul primo iPhone col notch che provi, **verifica che il pannello diagnostico non finisca sotto la barra di stato**: se succede, il bug è nella conversione fra pixel schermo e pixel viewport in `ui/debug_hud.gd`, non nel valore della safe area.

---

## 6. `export_presets.cfg`

È in `.gitignore` perché contiene percorsi locali e la password del keystore. Non committarlo mai.

Quando avrai un preset funzionante, salva una copia ripulita dai segreti come `export_presets.cfg.template` e committa quella: al prossimo ambiente ti risparmi mezza giornata.

---

## 7. Checklist Sprint 0

- [ ] Il progetto si apre e F5 mostra la griglia
- [ ] Il pannello diagnostico dice **16/16**
- [ ] `./tools/check_all.sh` esce verde
- [ ] Filtro `data/*.json` impostato nel preset di esportazione
- [ ] **Una build gira sul tuo telefono fisico** — entro il giorno 2, non alla fine
- [ ] Pan a un dito e pinch-zoom funzionano e sono piacevoli
- [ ] Il pannello rispetta la safe area

L'unica voce che non puoi rimandare è la build su device fisico. Rimandarla allo Sprint 6 significa scoprire i problemi di touch, di safe area e di firma quando costano dieci volte tanto.
