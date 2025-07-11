> [!IMPORTANT]
> you must update config.json before run the ADVFilmenager.

## Update `config.json` for your Path Configuration

```json
{
  "paths": {
    "source": "C:\\Documenti_source", 
    // <- Your default source folder

    "logPath": "C:\\Users\\MYUSER\\Documenti_destinazione\\Log\\organizer_log.txt", 
    // <- Where the script writes logs

    "reorgLogPath": "C:\\Users\\MYUSER\\Documenti_destinazione\\Log\\Log_Destination_reorg.txt", 
    // <- Where the script writes reorganization logs

    "downloadSource": "C:\\Users\\MYUSER\\Downloads", 
    // <- Default download folder

    "downloadProcessedRootName": "_Download_Processati", 
    // <- Name of folder for processed downloads

    "rules_file": "C:\\Users\\MYUSER\\script\\ADVFilemanager\\Rules\\rules.json" 
    // <- Path to the rules file
  },

  "debugSettings": {
    "enableDebugLog": true, 
    // <- Enable or disable debug logging

    "debugLogPath": "C:\\Users\\MYUSER\\Documenti_destinazione\\Log\\debug_log.txt" 
    // <- Path to debug log file
  }
}
