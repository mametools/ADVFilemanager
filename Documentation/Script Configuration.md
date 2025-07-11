
Configurazione
_organizer_settings.json
Specifica il percorso personalizzato della configurazione:

### Config.json
Contiene tutte le impostazioni operative:

### Percorsi:
- source: cartella sorgente
- destination: cartella di destinazione
- logPath, reorgLogPath: log operativi
- downloadSource: cartella dei download

### Filtri file:
- extensions: estensioni supportate (es. pdf, docx, xlsx, jpg, zip, ecc.)
- minSizeKB, maxSizeMB: dimensioni minime e massime dei file da gestire

### Regole:
- rules_file: percorso del file rules.json

### Debug:
- enableDebugLog: attiva log di debug
- debugLogPath: percorso log debug

### Gestione duplicati:
- CreateShortcut, Ignore, DeleteSource
### Rinomina automatica:
- Regole find / replace per modificare nomi file

### Cartelle speciali:
- ignoredSourceFolders: cartelle da ignorare
- preserveStructureFolders: cartelle da mantenere con struttura originale
- reorgIgnoredFolders, reorgIgnoredFilePatterns: esclusioni per riorganizzazione

📘 Esempio di rules.json

✅ Requisiti
PowerShell 5.1 o superiore
Sistema Windows (per supporto COM oggetti e shortcut .lnk)

📜 Licenza
Questo progetto è distribuito sotto licenza MIT.