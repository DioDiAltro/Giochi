# Setup e Esportazione

Guida operativa per **Windows + Android**, che è il percorso più rapido per avere il prototipo su un telefono. iOS in appendice (§7).

> La parte di firma richiede le **tue** credenziali e non può stare nel repo. `export_presets.cfg` è nel `.gitignore` apposta: contiene la password del keystore.

---

## 1. Godot

Scarica **Godot 4.4.x** da [godotengine.org/download/windows](https://godotengine.org/download/windows/) — versione **standard**, *non* .NET (quella serve per C#).

Non c'è installer: è un singolo `.exe` dentro uno zip. Scompatta dove vuoi (es. `C:\Godot\`) e fai doppio clic.

> **Consiglio:** tieni l'eseguibile in una cartella stabile e crea un collegamento. Ti servirà anche da riga di comando per `check_all.sh`.

## 2. Aprire il progetto

La radice del repo **è** la radice del progetto Godot. Nel gestore progetti: **Importa** → seleziona `project.godot` → **Importa e modifica**.

Premi **F5**. Devi vedere la griglia, e nel pannello in alto `16/16 — i dati coincidono con balance_sim.py`. In console:

```
tier(ingot_iron) = 3, vi = 15.625
```

Se leggi quella riga, le fondamenta reggono.

## 3. ⚠️ Il filtro di esportazione — leggilo prima di esportare

**Godot non importa i file `.json` come risorse.** Sono "file non-risorsa": per finire nel pacchetto esportato devono essere elencati in un filtro. Se lo dimentichi, la build sul telefono parte **senza nessun dato di bilanciamento** — niente materiali, niente ricette, niente edifici — e su un telefono non hai una console per capire perché.

In **Progetto → Esporta → (preset Android) → Risorse**, campo **"Filtri per esportare file non-risorsa"**:

```
data/*.json
```

Il progetto ha una rete di sicurezza: se i dati non si caricano, il pannello diagnostico mostra un banner rosso a tutto schermo con questa istruzione. Ma è molto meglio non arrivarci.

---

## 4. Android su Windows — setup una tantum

### 4.1 JDK 17

Godot 4.4 richiede **esattamente il JDK 17** per l'export Android (né 11 né 21).

```powershell
winget install Microsoft.OpenJDK.17
```

Verifica (riapri il terminale dopo l'installazione):

```powershell
java -version      # deve dire 17.x
keytool -help      # deve rispondere: serve al passo 4.3
```

### 4.2 Android SDK

Il modo meno doloroso è installare **Android Studio**, che si porta dietro l'SDK:

```powershell
winget install Google.AndroidStudio
```

Al primo avvio completa il wizard (accetta le licenze). Poi **More Actions → SDK Manager** e annota il percorso in alto, tipicamente:

```
C:\Users\<tuonome>\AppData\Local\Android\Sdk
```

Nella scheda **SDK Tools** assicurati che siano spuntati **Android SDK Build-Tools**, **Android SDK Platform-Tools** e **Android SDK Command-line Tools**.

> Android Studio serve solo per l'SDK. Non lo aprirai più: scriverai tutto in Godot.

### 4.3 Keystore di debug

Serve a firmare le build di test. Crealo una volta e riusalo sempre:

```powershell
cd $env:USERPROFILE\.android
keytool -keyalg RSA -genkeypair -alias androiddebugkey `
  -keypass android -keystore debug.keystore -storepass android `
  -dname "CN=Android Debug,O=Android,C=US" -validity 9999 `
  -deststoretype pkcs12
```

Se la cartella `.android` non esiste, creala con `mkdir $env:USERPROFILE\.android`.

### 4.4 Dire a Godot dove sono le cose

**Editor → Impostazioni Editor → Esporta → Android**:

| Campo | Valore |
|---|---|
| Android SDK Path | `C:\Users\<tuonome>\AppData\Local\Android\Sdk` |
| Java SDK Path | `C:\Program Files\Microsoft\jdk-17.x.x-hotspot` |
| Debug Keystore | `C:\Users\<tuonome>\.android\debug.keystore` |
| Debug Keystore User | `androiddebugkey` |
| Debug Keystore Pass | `android` |

### 4.5 Template di esportazione

**Editor → Gestisci modelli di esportazione → Scarica ed installa**. Circa 1 GB, una volta sola per ogni versione di Godot. Devono corrispondere **esattamente** alla tua versione (4.4.1 con 4.4.1).

### 4.6 Il preset

**Progetto → Esporta → Aggiungi → Android**:

| Impostazione | Valore | Perché |
|---|---|---|
| Filtri file non-risorsa | `data/*.json` | **obbligatorio**, §3 |
| Architetture → `arm64-v8a` | attivo | l'unica che il Play Store accetta |
| Architetture → altre | disattive | dimezzano il peso dell'APK |

Il resto lascialo ai default di Godot 4.4.

---

## 5. Mettere l'app sul telefono

### Sul telefono, una volta sola

**Impostazioni → Info sul telefono → Numero build**, toccalo **7 volte**. Poi **Impostazioni → Opzioni sviluppatore → Debug USB: attivo**.

### Collega e verifica

Collega via USB (con un cavo dati — non tutti i cavi lo sono). Sul telefono comparirà "Consentire il debug USB?": accetta e spunta "Consenti sempre".

```powershell
cd "C:\Users\<tuonome>\AppData\Local\Android\Sdk\platform-tools"
.\adb devices
```

Devi vedere il seriale del telefono seguito da `device`. Se dice `unauthorized`, guarda il popup sul telefono. Se non compare niente, prova un altro cavo — è la causa più frequente.

### Deploy in un clic

In Godot, in alto a destra compare un'**icona a forma di telefono**. Cliccala: compila, installa e avvia sul dispositivo. È il modo giusto di iterare — non esportare l'APK a mano ogni volta.

---

## 6. Verifica da riga di comando

Prima di ogni commit:

```powershell
$env:GODOT = "C:\Godot\Godot_v4.4.1-stable_win64.exe"
bash tools/check_all.sh          # con Git Bash o WSL
```

Oppure solo l'engine, senza bash:

```powershell
& $env:GODOT --headless --path . -- --selftest
```

Esegue le 17 invarianti di design, valida i JSON e verifica che l'engine calcoli gli stessi numeri del simulatore Python. Exit code 1 se qualcosa si rompe: perfetto per un hook di pre-commit.

---

## 7. Appendice: iOS

**Serve un Mac con Xcode.** Non ci sono alternative supportate — nemmeno macchine virtuali, che violano i termini Apple.

Quando avrai accesso a un Mac:

1. Template di esportazione per la tua versione di Godot.
2. **Progetto → Esporta → Aggiungi → iOS**: `Bundle Identifier` (es. `com.tuonome.factorydefense`), `Team ID`, profilo di provisioning.
3. Filtro `data/*.json` (§3).
4. L'export produce un **progetto Xcode**, non un `.ipa`. Aprilo, imposta il team in *Signing & Capabilities*, premi Run col telefono collegato.

Un **Apple ID gratuito** basta per installare sul tuo dispositivo (l'app scade dopo 7 giorni). Per TestFlight serve l'**Apple Developer Program**, 99 $/anno.

Non è bloccante: puoi sviluppare tutto l'MVP su Android e affrontare iOS quando avrai qualcosa da mostrare.

### Safe area

`project.godot` imposta già l'orientamento verticale, e il codice legge `DisplayServer.get_display_safe_area()`. Sul primo iPhone col notch, verifica che il pannello diagnostico non finisca sotto la barra di stato: se succede, il bug è nella conversione fra pixel schermo e pixel viewport in `ui/debug_hud.gd`, non nel valore della safe area.

---

## 8. `export_presets.cfg`

È nel `.gitignore` perché contiene percorsi locali e la password del keystore. **Non committarlo mai.**

Quando avrai un preset funzionante, salvane una copia ripulita dai segreti come `export_presets.cfg.template` e committa quella.

---

## 9. Checklist Sprint 0

- [ ] Godot 4.4 scaricato, progetto importato
- [ ] F5 mostra la griglia e il pannello dice **16/16**
- [ ] JDK 17 + Android SDK installati, percorsi impostati in Godot
- [ ] Keystore di debug creato
- [ ] Filtro `data/*.json` nel preset di esportazione
- [ ] `adb devices` vede il telefono
- [ ] **Una build gira sul tuo telefono** — entro il giorno 2, non alla fine
- [ ] Pan e pinch-zoom funzionano e sono piacevoli al tatto
- [ ] Il pannello rispetta la safe area

L'unica voce che non puoi rimandare è la build su device fisico. Rimandarla allo Sprint 6 significa scoprire i problemi di touch, safe area e firma quando costano dieci volte tanto.
