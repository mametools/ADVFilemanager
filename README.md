📁 Advanced FileManager

Versione: 1.0.0

Autore: Marco Mella
## Why Powershell?
The core idea is to use a script that requires no additional tools or applications to be installed on Windows. The next version will be written in Python to ensure compatibility with other operating systems as well.

### Next version will be write with Python so you can use the script on other Operating System


  ## Why bat file?
 The .bat file acts as a launcher for the ADVFileManager script, starting it directly with PowerShell. Of course, it's always possible to run the main script (ADVFileManager.ps1) by calling it directly from a PowerShell console.
  
### Roadmap
Rethink the script's configuration for easier path management.
Translate the description, comments, and script messages into English.
Develop the next version in Python to extend compatibility to other operating systems.

## Feature description

**ADVFileManager** è uno script PowerShell avanzato per l'organizzazione automatica di file da una sorgente a una destinazione, con supporto per:

- regole personalizzate
- gestione duplicati
- shortcut
- logging dettagliato
- generazione di report HTML dinamico (`search file`, `ordinamento`)

## Funzionalità principali

### 🔄 Importazione file

- Modalità: `DryRun`, `Copy`, `Move`
- Analisi e classificazione file tramite regole
- Rinomina automatica secondo pattern configurabili
- Gestione duplicati:
  - Ignora
  - Crea collegamento (`.lnk`)
  - Cancella file sorgente (solo in `Move`)
- Preservazione struttura cartelle selezionate
- Verifica spazio su disco prima dell'importazione (con nome specifico o base rules)
- Logging dettagliato per ogni file elaborato


### 🧹 Riorganizzazione archivio
- Lo script può analizza la struttura del Folder di destinazione e riorganizzarlo con nuove Rules
- Applica regole di classificazione per spostare file
- Risolve duplicati e crea shortcut
- Rimuove shortcut duplicati e obsoleti
- Cancella cartelle vuote
- Gestisce conflitti (file con stesso nome ma contenuto diverso)
- Possibilità di simulazione della riorganizzazione (`DryRun`)

### 📥 Gestione cartella Download
- Analizza contenuto della cartella `Downloads`
- Applica regole di classificazione
- Sposta file nella destinazione in un Folder dedicato
- Cancella file duplicati già presenti
- Supporta modalità `DryRun`

📊 Logging e Reporting
Log dettagliati in formato `.txt` e `.csv`:
- File ignorati
- Errori
- Duplicati cancellati
- Shortcut creati
- File rinominati
- File spostati
- File solo online (example cloud OneDrve, GDrive)
- Conflitti

Report HTML con:
- Statistiche
- File recenti (last 30 days)
- Struttura virtuale dell’archivio

Dettagli operazione
🧠 Motore Regole (Rules.json)
- Supporta condizioni logiche complesse: `AND`, `OR`, `NOT`
- Supporto Regex
- Regole annidate e con priorità
- Cartelle dinamiche: anno, mese, estensione
- Commenti per cartelle che saranno inclusi nei report

## 📦 Struttura del progetto

```plaintext
FileManager/
├── FileManager.ps1
├── Config.json
├── _organizer_settings.json
├── Rules/
│   └── rules.json
├── modules/
│   ├── HtmlReportGenerator.psm1
│   └── JsonValidator.psm1
└── Log/
