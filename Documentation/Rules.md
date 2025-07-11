## 📄 Regole di classificazione
Le regole sono definite in rules.json e supportano:

Strutture annidate
Condizioni logiche: AND, OR, NOT
Cartelle dinamiche: per anno, mese, estensione
Commenti per cartelle (inclusi nei report)

## Rules.json grammar
### 🔍 Spiegazione
    name: Folder da creare
    priority: priorità di applicazione (più bassa = più importante)
    rules: condizioni di classificazione (supporta AND, OR, NOT)
    metadata.comment: commento visibile nei report
    dynamic_folders:
     - by_year: crea sottocartelle per anno
     - by_month: crea sottocartelle per mese (es. 07 - Luglio)
     - by_extension: crea sottocartelle per estensione file


### Rules example   

This example includes:

- ✅ OR, AND, NOT conditions
- ✅ Nested rules
- ✅ Rule priorities
- ✅ Metadata comments
- ✅ Dynamic folders by year, month, and extension
- ✅ Subfolders for hierarchical classification



---
# 📘 FileManager - Rules Configuration Guide (`rules.json`)

This document explains the structure and usage of the `rules.json` file used by the FileManager PowerShell script. The rules define how files are classified and organized based on their names, extensions, or patterns.

---

## 🛠️ Structure of `rules.json`

The file contains a top-level key `structures`, which is a list of classification rules. Each rule defines:

- `name`: Destination folder name
- `priority`: Lower values are evaluated first
- `rules`: Logical conditions (OR, AND, NOT, nested)
- `metadata.comment`: Description shown in reports
- `dynamic_folders`: Optional subfolders by year, month, extension
- `subfolders`: Optional nested rules for deeper classification

---

## 🧠 Rule Types

### 🔹 OR

```json
"rules": {
  "OR": ["invoice", "receipt", "bill"]
}
Matches if 'any' of the terms are found in the filename.
```
### 🔹 AND
```
"rules": {
  "AND": ["contract", { "OR": ["client", "supplier"] }]
}
Matches if 'all' conditions are satisfied. 'Nested logic' is supported.
```
### 🔹 NOT
```
"rules": {
  "NOT": ["draft", "old"]
}
Excludes files containing any of the specified terms.
```
### 🔀 Nested Rules
```
"rules": {
  "AND": [
    { "OR": ["report", "summary"] },
    { "NOT": ["draft", "old"] }
  ]
}
```
Combines multiple logical blocks for advanced filtering.
