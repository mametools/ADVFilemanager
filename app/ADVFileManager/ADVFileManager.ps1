<#
.SYNOPSIS
    Advanced FileManager: ADVFileManager - Script avanzato per organizzare e manutenere un archivio di file.
.DESCRIPTION
    Versione 1.0.0
.VERSION
    1.0.0
.AUTHOR
    Marco Mella (with some AI Support)
#>

# --- Import Moduli ---
try {
    Add-Type -AssemblyName System.Windows.Forms
    Import-Module (Join-Path $PSScriptRoot 'modules\HtmlReportGenerator.psm1') -Force -ErrorAction Stop
    Import-Module (Join-Path $PSScriptRoot 'modules\JsonValidator.psm1') -Force -ErrorAction Stop
}
catch {
    Write-Error "Impossibile caricare i moduli necessari. Assicurarsi che si trovino nella cartella 'modules' ($PSScriptRoot\modules). Errore: $($_.Exception.Message)"
    exit 1
}

# --- Variabili Globali e Contatori ---
$script:Version = "1.0.0"
$script:Author = "Marco Mella (with some AI Support)"
$script:Configuration = $null
$script:Rules = $null
$script:DestinationInitialHashMap = [System.Collections.Generic.Dictionary[string, string]]::new()
$script:DynamicLogPath = $null
$script:DynamicReorgLogPath = $null
$script:DynamicDebugLogPath = $null
$script:VirtualDestinationTree = @{}
$script:Counters = @{ Analyzed = 0; Copied = 0; Moved = 0; Shortcuts = 0; Ignored = 0; Errors = 0; Simulated = 0; DuplicatesDeleted = 0 }
$script:IgnoredFilesLog = [System.Collections.Generic.List[pscustomobject]]::new()
$script:ErrorFilesLog = [System.Collections.Generic.List[pscustomobject]]::new()
$script:DeletedDuplicatesLog = [System.Collections.Generic.List[pscustomobject]]::new()
$script:RecentFilesLog = [System.Collections.Generic.List[pscustomobject]]::new()
$script:OnlineOnlyFilesLog = [System.Collections.Generic.List[pscustomobject]]::new()
$script:RenamedFilesLog = [System.Collections.Generic.List[pscustomobject]]::new()
$script:MovedFilesLog = [System.Collections.Generic.List[pscustomobject]]::new()
$script:ShortcutsLog = [System.Collections.Generic.List[pscustomobject]]::new()
$script:DiskSpaceCheckLog = [System.Collections.Generic.List[pscustomobject]]::new()
$script:ConflictLog = [System.Collections.Generic.List[pscustomobject]]::new()

# --- Logging ---
function Write-Log { param([string]$Message, [ValidateSet("INFO", "VERBOSE", "ERROR")][string]$Level); $logPath = $script:DynamicLogPath; if (-not $logPath) { return }; $logLevels = @{"INFO" = 1; "VERBOSE" = 2}; $configLogLevel = $script:Configuration.settings.logVerbosity; $configuredLevelValue = if ($logLevels.ContainsKey($configLogLevel)) { $logLevels[$configLogLevel] } else { 1 }; $messageLevelValue = if ($logLevels.ContainsKey($Level)) { $logLevels[$Level] } else { 1 }; $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"; $formattedMessage = "[$timestamp] [$Level] $Message"; if ($Level -eq "ERROR") { Write-Error $formattedMessage } elseif ($messageLevelValue -le $configuredLevelValue) { Write-Host $formattedMessage }; try { $formattedMessage | Out-File -FilePath $logPath -Append -Encoding utf8 -ErrorAction Stop } catch { Write-Host "WARNING: Impossibile scrivere sul file di log: $logPath. Errore: $($_.Exception.Message)" -ForegroundColor Yellow } }
function Write-ReorgLog { param([string]$Message, [ValidateSet("INFO", "WARN", "ERROR", "DRYRUN")][string]$Level); $logPath = $script:DynamicReorgLogPath; if (-not $logPath) { Write-Warning "reorgLogPath non è specificato o è invalido. Impossibile loggare."; return }; $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"; $formattedMessage = "[$timestamp] [$Level] $Message"; Write-Host $formattedMessage -ForegroundColor Cyan; try { $formattedMessage | Out-File -FilePath $logPath -Append -Encoding utf8 -ErrorAction Stop } catch { Write-Host "WARNING: Impossibile scrivere sul file di log di riorganizzazione: $logPath." -ForegroundColor Yellow } }
function Write-DebugLog { param([string]$Message); if (-not $script:Configuration.debugSettings.enableDebugLog) { return }; $logPath = $script:DynamicDebugLogPath; if (-not $logPath) { return }; $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss:fff"; $formattedMessage = "[$timestamp] [DEBUG] $Message"; try { $formattedMessage | Out-File -FilePath $logPath -Append -Encoding utf8 -ErrorAction Stop } catch {} }

# --- Index files ---
function Generate-FolderIndexFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    Write-Log -Level 'INFO' -Message "Avvio generazione file di indice (Lista_files.txt) nelle cartelle..."
    $manifestFileName = "Lista_files.txt"
    
    $allDirectories = Get-ChildItem -Path $DestinationPath -Recurse -Directory -ErrorAction SilentlyContinue
    $rootDirectoryInfo = Get-Item -Path $DestinationPath
    $directoriesToProcess = @($rootDirectoryInfo) + @($allDirectories)

    foreach ($dir in $directoriesToProcess) {
        try {
            $filesInDir = Get-ChildItem -Path $dir.FullName -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne $manifestFileName }
            
            $manifestPath = Join-Path $dir.FullName $manifestFileName

            if (Test-Path -Path $manifestPath -PathType Leaf) {
                Remove-Item -Path $manifestPath -Force
            }

            if ($filesInDir) {
                $fileNames = $filesInDir | Sort-Object Name | Select-Object -ExpandProperty Name
                $fileNames | Out-File -FilePath $manifestPath -Encoding utf8
            }
        }
        catch {
            Write-Log -Level 'ERROR' -Message "Impossibile generare il file di indice per la cartella '$($dir.FullName)'. Errore: $($_.Exception.Message)"
        }
    }
    Write-Log -Level 'INFO' -Message "Generazione dei file di indice completata."
}

function Build-InitialVirtualTreeFromDestination {
    Write-Log -Level 'INFO' -Message "Costruzione dell'albero virtuale iniziale dalla destinazione..."
    $destPath = $script:Configuration.paths.destination
    $script:VirtualDestinationTree=@{'_totalSizeInBytes' = 0}

    if (-not (Test-Path -Path $destPath -PathType Container)) {
        Write-Log -Level 'INFO' -Message "La cartella di destinazione non esiste, l'albero virtuale iniziale è vuoto."
        return
    }

    $allItems = Get-ChildItem -Path $destPath -Recurse -File -ErrorAction SilentlyContinue
    foreach ($item in $allItems) {
        $isShortcut = $item.Extension -eq '.lnk'
        $relativePath = $item.FullName.Substring($destPath.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar)
        
        $comment = if ($isShortcut) { "Collegamento esistente in archivio" } else { "" }

        $fileObject = [pscustomobject]@{
            Name       = $item.Name
            Size       = (Format-Bytes -bytes $item.Length)
            IsShortcut = $isShortcut
            Comment    = $comment
            Length     = $item.Length
        }
        Add-ToVirtualTree -Tree $script:VirtualDestinationTree -RelativePath $relativePath.Replace($item.Name, "").TrimEnd('\/') -FileObject $fileObject
    }
    Write-Log -Level 'INFO' -Message "Costruzione albero virtuale iniziale completata. Trovati $($script:VirtualDestinationTree._totalSizeInBytes | Format-Bytes) in $($allItems.Count) elementi."
}
function Get-FileMD5Hash { param([string]$FilePath); $longFilePath = if ($FilePath.StartsWith('\\?\')) { $FilePath } else { "\\?\$FilePath" }; if (-not (Test-Path -LiteralPath $longFilePath -PathType Leaf)) { $errorMessage = "Impossibile calcolare l'hash. Il file non esiste o è inaccessibile (potenzialmente solo online): '$FilePath'."; Write-Log -Level 'INFO' -Message $errorMessage; $script:OnlineOnlyFilesLog.Add([pscustomobject]@{Timestamp=(Get-Date -Format 'dd-MM-yyyy HH:mm:ss'); FilePath=$FilePath; Reason="File non trovato o solo online"}); $script:Counters.Ignored++; return $null }; try { $hashInfo = Get-FileHash -Algorithm MD5 -LiteralPath $longFilePath -ErrorAction Stop; return $hashInfo.Hash } catch { $exceptionMessage = $_.Exception.GetBaseException().Message; if ($exceptionMessage -like '*is being used by another process*') { $fileName = Split-Path -Path $FilePath -Leaf; $message = "ATTENZIONE: File in uso da un altro programma.`n`nFile: $fileName`nPercorso: $FilePath`n`nAzione richiesta:`n1. Chiudi il programma che sta bloccando il file (es. Excel, Word).`n2. Scegli un'opzione qui sotto."; $title = "File Bloccato Rilevato"; $buttons = [System.Windows.Forms.MessageBoxButtons]::AbortRetryIgnore; $icon = [System.Windows.Forms.MessageBoxIcon]::Warning; $dialogResult = [System.Windows.Forms.MessageBox]::Show($message, $title, $buttons, $icon); switch ($dialogResult) { 'Retry' { Write-Log -Level 'INFO' -Message "L'utente ha scelto di riprovare l'accesso al file '$FilePath'."; return Get-FileMD5Hash -FilePath $FilePath }; 'Ignore' { $logMessage = "L'utente ha scelto di ignorare il file bloccato '$FilePath'."; Write-Log -Level 'INFO' -Message $logMessage; $script:IgnoredFilesLog.Add([pscustomobject]@{Timestamp=(Get-Date -Format 'dd-MM-yyyy HH:mm:ss'); FilePath=$FilePath; Reason="File bloccato e ignorato dall'utente"}); $script:Counters.Ignored++; return $null }; 'Abort' { $errorMessage = "Operazione annullata dall'utente a causa di un file bloccato."; Write-Log -Level 'ERROR' -Message $errorMessage; Write-Error $errorMessage -ErrorAction Stop } } } else { $errorMessage = "Impossibile calcolare l'hash per '$FilePath'. Errore: $exceptionMessage"; Write-Log -Level 'ERROR' -Message $errorMessage; $script:ErrorFilesLog.Add([pscustomobject]@{Timestamp=(Get-Date -Format 'dd-MM-yyyy HH:mm:ss'); FilePath=$FilePath; Reason=$errorMessage}); $script:Counters.Errors++; return $null } } }
function Add-ToVirtualTree { param([hashtable]$Tree, [string]$RelativePath, [psobject]$FileObject); $fileSize = 0; if ($FileObject.PSObject.Properties.Name -contains 'Length' -and $FileObject.Length -ge 0) { $fileSize = $FileObject.Length }; $pathParts = $RelativePath.Split([System.IO.Path]::DirectorySeparatorChar) | Where-Object { $_ }; $currentNode = $Tree; foreach ($part in $pathParts) { $currentNode['_totalSizeInBytes'] += $fileSize; if (-not $currentNode.ContainsKey($part)) { $currentNode[$part] = @{ '_files' = [System.Collections.Generic.List[pscustomobject]]::new(); '_totalSizeInBytes' = 0; '_comment' = "" } }; $currentNode = $currentNode[$part] }; $currentNode['_totalSizeInBytes'] += $fileSize; if ($FileObject.PSObject.Properties.Name -contains 'IsFolderComment' -and $FileObject.IsFolderComment) { if ($FileObject.Comment) { $currentNode['_comment'] = $FileObject.Comment } } else { if (-not $currentNode.ContainsKey("_files")) { $currentNode["_files"] = [System.Collections.Generic.List[pscustomobject]]::new() }; $currentNode["_files"].Add($FileObject) } }
function New-Shortcut { param([string]$ShortcutPath, [string]$TargetPath); try { $shell = New-Object -ComObject WScript.Shell; $shortcut = $shell.CreateShortcut($ShortcutPath); $shortcut.TargetPath = $TargetPath; $shortcut.Save() } catch { $errorMessage = "Creazione del collegamento '$ShortcutPath' non riuscita. Errore: $($_.Exception.Message)"; Write-Log -Level 'ERROR' -Message $errorMessage; $script:ErrorFilesLog.Add([pscustomobject]@{Timestamp=(Get-Date -Format 'dd-MM-yyyy HH:mm:ss'); FilePath=$ShortcutPath; Reason=$errorMessage}); $script:Counters.Errors++ } }
function Apply-RenameRules { param([string]$OriginalFileName); $newFileName = $OriginalFileName; if ($script:Configuration.renameRules) { foreach ($rule in $script:Configuration.renameRules) { $newFileName = $newFileName -replace $rule.find, $rule.replace } }; return $newFileName }
function Format-Bytes { param([long]$bytes); if ($bytes -ge 1GB) { return "{0:N2} GB" -f ($bytes / 1GB) } elseif ($bytes -ge 1MB) { return "{0:N2} MB" -f ($bytes / 1MB) } elseif ($bytes -ge 1KB) { return "{0:N0} KB" -f ($bytes / 1KB) } else { return "$bytes B" } }
function Get-LongPath { param([string]$Path); return "\\?\$Path" }

# --- Funzioni di Configurazione e Regole ---
function Get-ConfigurationPaths {
    $scriptDir = $PSScriptRoot
    if (Test-Path -LiteralPath (Join-Path $scriptDir "_organizer_settings.json")) {
        try {
            $savedSettings = Get-Content -Path (Join-Path $scriptDir "_organizer_settings.json") -Raw | ConvertFrom-Json -ErrorAction Stop
            if ($null -ne $savedSettings.customPath -and (Test-Path -LiteralPath (Join-Path $savedSettings.customPath "config.json"))) {
                return (Join-Path $savedSettings.customPath "config.json")
            }
        }
        catch {}
    }
    return $null
}
function Set-DynamicLogPaths { $timestampForFile = Get-Date -Format "dd-MM-yyyy_HH-mm-ss"; $baseLogPath = $script:Configuration.paths.logPath; if ($baseLogPath) { $logDirectory = Split-Path -Path $baseLogPath -Parent; if (-not (Test-Path $logDirectory -PathType Container)) { try { New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null } catch { Write-Warning "Impossibile creare la directory di log: $logDirectory" } }; $logBaseName = [System.IO.Path]::GetFileNameWithoutExtension($baseLogPath); $logExtension = [System.IO.Path]::GetExtension($baseLogPath); $newLogName = "$($logBaseName)_$($timestampForFile)$($logExtension)"; $script:DynamicLogPath = Join-Path $logDirectory $newLogName }; $baseReorgLogPath = $script:Configuration.paths.reorgLogPath; if ($baseReorgLogPath) { $reorgLogDirectory = Split-Path -Path $baseReorgLogPath -Parent; if (-not (Test-Path $reorgLogDirectory -PathType Container)) { try { New-Item -Path $reorgLogDirectory -ItemType Directory -Force | Out-Null } catch { Write-Warning "Impossibile creare la directory di log: $reorgLogDirectory" } }; $reorgLogBaseName = [System.IO.Path]::GetFileNameWithoutExtension($baseReorgLogPath); $reorgLogExtension = [System.IO.Path]::GetExtension($baseReorgLogPath); $newReorgLogName = "$($reorgLogBaseName)_$($timestampForFile)$($reorgLogExtension)"; $script:DynamicReorgLogPath = Join-Path $reorgLogDirectory $newReorgLogName }; if ($script:Configuration.debugSettings.enableDebugLog -and $script:Configuration.debugSettings.debugLogPath) { $debugLogPath = $script:Configuration.debugSettings.debugLogPath; $debugLogDirectory = Split-Path -Path $debugLogPath -Parent; if (-not (Test-Path $debugLogDirectory)) { try { New-Item -Path $debugLogDirectory -ItemType Directory -Force | Out-Null } catch {} }; $debugBaseName = [System.IO.Path]::GetFileNameWithoutExtension($debugLogPath); $debugExtension = [System.IO.Path]::GetExtension($debugLogPath); $newDebugLogName = "$($debugBaseName)_$($timestampForFile)$($debugExtension)"; $script:DynamicDebugLogPath = Join-Path $debugLogDirectory $newDebugLogName } }
function Load-ConfigAndValidate { param([string]$Path); Write-Host "INFO: Caricamento configurazione da '$Path'..." -ForegroundColor Green; if (-not (Test-Path $Path -PathType Leaf)) { Write-Error "File di configurazione '$Path' non trovato o è una cartella. Uscita."; exit 1 }; try { $script:Configuration = Get-Content -Path $Path -Raw | ConvertFrom-Json -ErrorAction Stop } catch { Write-Error "Impossibile analizzare '$Path'. Errore: $_"; exit 1 }; if (-not $script:Configuration.paths.source -or -not (Test-Path $script:Configuration.paths.source -PathType Container)) { Write-Error "Percorso di origine '$($script:Configuration.paths.source)' non valido o non esiste. Uscita."; exit 1 }; if (-not $script:Configuration.paths.destination) { Write-Error "Percorso di destinazione non specificato. Uscita."; exit 1 }; $longDestPath = Get-LongPath -Path $script:Configuration.paths.destination; if (-not (Test-Path $longDestPath -PathType Container)) { Write-Host "INFO: Percorso destinazione '$($script:Configuration.paths.destination)' non esiste. Verrà creato."; New-Item -Path $longDestPath -ItemType Directory -Force | Out-Null }; if (-not $script:Configuration.paths.rules_file) { Write-Error "La chiave 'rules_file' nel file di configurazione è mancante. Uscita."; exit 1 } }
function Load-Rules { param([Parameter(Mandatory = $true)][string]$RulesPath); Write-Host "INFO: Caricamento regole da '$RulesPath'..." -ForegroundColor Green; if (-not (Test-Path -Path $RulesPath -PathType Leaf)) { Write-Error "ERRORE CRITICO: Il percorso delle regole '$RulesPath' non punta a un file valido o il file non esiste. Controlla la chiave 'rules_file' in config.json e la posizione del file."; exit 1 }; try { $script:Rules = Get-Content -Path $RulesPath -Raw | ConvertFrom-Json -ErrorAction Stop } catch { Write-Error "Impossibile analizzare il file delle regole '$RulesPath'. Errore: $_"; exit 1 } }
function Confirm-SourcePath {
    $currentDirectory = $PWD.Path
    $defaultSourcePath = $script:Configuration.paths.source
    $chosenSourcePath = $defaultSourcePath

    if (($currentDirectory -ne $defaultSourcePath) -and (Test-Path -Path $currentDirectory -PathType Container)) {
        
        Write-Host "`n" + ("-"*30) -ForegroundColor Yellow
        Write-Host " Rilevata Posizione Personalizzata " -ForegroundColor Yellow
        Write-Host ("-"*30) -ForegroundColor Yellow
        
        Write-Host "La cartella di origine predefinita (da config.json) è:`n `b>$($defaultSourcePath)`b`n"
        Write-Host "Lo script è stato però avviato dalla seguente cartella:`n `b>$($currentDirectory)`b`n"

        $prompt = "Vuoi usare la cartella corrente come origine per questa sessione? (si / qualsiasi altro tasto per default)"
        $choice = Read-Host -Prompt $prompt

        if ($choice -eq 'si') {
            $chosenSourcePath = $currentDirectory
            Write-Host "[OK] Verrà usata la cartella corrente come origine." -ForegroundColor Green
        } else {
            Write-Host "[INFO] Verrà usata la cartella di origine predefinita." -ForegroundColor Cyan
        }
    }

    Write-Host "`n" + ("-"*30) -ForegroundColor Yellow
    Write-Host " Conferma Finale Percorso Sorgente " -ForegroundColor Yellow
    Write-Host ("-"*30) -ForegroundColor Yellow

    $confirmPrompt = "L'operazione utilizzerà la seguente cartella di origine:`n `b>$($chosenSourcePath)`b`n`nSei assolutamente sicuro di voler procedere? (si / no)"
    $confirmation = Read-Host -Prompt $confirmPrompt
    
    if ($confirmation -ne 'si') {
        Write-Warning "Operazione annullata dall'utente. Lo script verrà terminato."
        Read-Host "Premere INVIO per uscire."
        exit
    }

    $script:Configuration.paths.source = $chosenSourcePath
    Write-Host "[CONFERMATO] Origine impostata. Si procede al menu principale..." -ForegroundColor Green
}
function Test-Rule {
    param([string]$FileName, [psobject]$Rule)

    function Test-Condition {
        param ($InnerRule)
        
        $caseOption = if ($script:Configuration.settings.caseInsensitiveMatch) { [System.Text.RegularExpressions.RegexOptions]::IgnoreCase } else { [System.Text.RegularExpressions.RegexOptions]::None }
        
        if ($InnerRule.PSObject.Properties.Name -contains 'OR') {
            foreach ($c in $InnerRule.OR) {
                if (($c -is [psobject]) -and ($c.PSObject.Properties.Name -match '^(AND|OR|NOT)$')) {
                    if (Test-Condition -InnerRule $c) { return $true }
                }
                else {
                    $flexiblePattern = $c -replace ' ', '[ _-]'
                    if ($FileName -match [regex]::new($flexiblePattern, $caseOption)) { return $true }
                }
            }
            return $false
        }
        elseif ($InnerRule.PSObject.Properties.Name -contains 'AND') {
            foreach ($c in $InnerRule.AND) {
                if (($c -is [psobject]) -and ($c.PSObject.Properties.Name -match '^(AND|OR|NOT)$')) {
                    if (-not (Test-Condition -InnerRule $c)) { return $false }
                }
                else {
                    $flexiblePattern = $c -replace ' ', '[ _-]'
                    if ($FileName -notmatch [regex]::new($flexiblePattern, $caseOption)) { return $false }
                }
            }
            return $true
        }
        elseif ($InnerRule.PSObject.Properties.Name -contains 'NOT') {
            foreach ($c in $InnerRule.NOT) {
                if (($c -is [psobject]) -and ($c.PSObject.Properties.Name -match '^(AND|OR|NOT)$')) {
                    if (Test-Condition -InnerRule $c) { return $false }
                }
                else {
                    $flexiblePattern = $c -replace ' ', '[ _-]'
                    if ($FileName -match [regex]::new($flexiblePattern, $caseOption)) { return $false }
                }
            }
            return $true
        }
        return $false
    }

    return Test-Condition -InnerRule $Rule
}
function Get-DestinationPath { 
    param( [System.IO.FileInfo]$File, [psobject]$RuleSet, [array]$MatchedPath = @() );
    $fileName = $File.Name;
    $potentialMatches = [System.Collections.Generic.List[object]]::new();
    
    foreach ($structure in @($RuleSet)) {
        if ($structure.rules -and (Test-Rule -FileName $fileName -Rule $structure.rules)) {
            $potentialMatches.Add($structure)
        }
    };

    if ($potentialMatches.Count -eq 0) {
        if ($MatchedPath.Count -gt 0) {
            return $MatchedPath
        }
        else {
            return $null
        }
    }
    
    foreach ($match in $potentialMatches) {
        if (-not $match.PSObject.Properties['priority']) {
            $match | Add-Member -MemberType NoteProperty -Name 'priority' -Value 99
        }
    };
    $winner = $potentialMatches | Sort-Object -Property priority | Select-Object -First 1;
    $currentLevelName = if ($winner.name) { $winner.name } else { $winner.baseFolder };
    $newMatchedPath = $MatchedPath + [pscustomobject]@{ PathSegment = $currentLevelName; Rule = $winner };
    
    if ($winner.subfolders) {
        $subfolderResult = Get-DestinationPath -File $File -RuleSet $winner.subfolders -MatchedPath $newMatchedPath;
        if ($subfolderResult) {
            return $subfolderResult
        }
    };
    return $newMatchedPath
}

# --- Worker ---
function Pre-IndexDestination { Write-Log -Level 'INFO' -Message "Pre-indicizzazione della destinazione..."; $script:DestinationInitialHashMap.Clear(); $destPath = $script:Configuration.paths.destination; $existingFiles = Get-ChildItem -Path $destPath -Recurse -File -ErrorAction SilentlyContinue; foreach($f in $existingFiles){ if (($f.Attributes -band [System.IO.FileAttributes]::Offline)) { Write-Log -Level 'INFO' -Message "File ignorato durante l'indicizzazione perché solo online: $($f.FullName)"; continue }; if ($f.Length -eq 0) { continue }; $h = Get-FileMD5Hash -FilePath $f.FullName; if($h -and -not $script:DestinationInitialHashMap.ContainsKey($h)){ $script:DestinationInitialHashMap.Add($h, $f.FullName) } }; Write-Log -Level 'INFO' -Message "Indicizzazione completata: $($script:DestinationInitialHashMap.Count) file unici trovati nell'archivio." }
function Invoke-FileProcessingLogic { param( [Parameter(Mandatory = $true)] [System.IO.FileInfo]$File, [Parameter(Mandatory = $true)] [string]$OperationMode, [Parameter(Mandatory = $true)] [hashtable]$RunHashMap, [string]$LogPrefix = "", [string]$DuplicateHandlingOverride = "", [switch]$IsDownloadMode ); $script:Counters.Analyzed++; Write-DebugLog -Message "Invoke-FileProcessingLogic: Inizio elaborazione per '$($File.FullName)'"; $logIgnored = { param($reason) $script:IgnoredFilesLog.Add([pscustomobject]@{Timestamp=(Get-Date -Format 'dd-MM-yyyy HH:mm:ss'); FilePath=$File.FullName; Reason=$reason}) }; if (($File.Attributes -band [System.IO.FileAttributes]::Offline)) { $logMessage = "File ignorato perché disponibile solo online."; Write-Log -Level 'INFO' -Message $logMessage; $script:Counters.Ignored++; . $logIgnored "File solo online"; $script:OnlineOnlyFilesLog.Add([pscustomobject]@{ Timestamp=(Get-Date -Format 'dd-MM-yyyy HH:mm:ss'); FilePath=$File.FullName; Size=(Format-Bytes -bytes $File.Length) }); return }; $ext = $File.Extension.TrimStart('.'); if ($script:Configuration.fileFilters.extensions -and $ext -notin $script:Configuration.fileFilters.extensions) { $script:Counters.Ignored++; . $logIgnored "Estensione non valida (`.$ext`)"; return }; if ($File.Length -lt ($script:Configuration.fileFilters.minSizeKB * 1024) -and $File.Length -ne 0) { $script:Counters.Ignored++; . $logIgnored "Dimensione minima non raggiunta ($([math]::Round($File.Length / 1KB, 2)) KB)"; return }; if ($File.Length -gt ($script:Configuration.fileFilters.maxSizeMB * 1024 * 1024)) { $script:Counters.Ignored++; . $logIgnored "Dimensione massima superata ($([math]::Round($File.Length / 1MB, 2)) MB)"; return }; $pathHierarchy = Get-DestinationPath -File $File -RuleSet $script:Rules.structures; if (-not $pathHierarchy) { $script:Counters.Ignored++; . $logIgnored "Nessuna regola di classificazione"; return }; $currentRelativePath = ""; foreach ($level in $pathHierarchy) { $currentRelativePath = if ([string]::IsNullOrEmpty($currentRelativePath)) { $level.PathSegment } else { Join-Path $currentRelativePath $level.PathSegment }; if ($level.Rule.metadata.comment) { $folderComment = [pscustomobject]@{ IsFolderComment = $true; Comment = $level.Rule.metadata.comment }; Add-ToVirtualTree -Tree $script:VirtualDestinationTree -RelativePath $currentRelativePath -FileObject $folderComment } }; $pathFromRules = $pathHierarchy.PathSegment -join [System.IO.Path]::DirectorySeparatorChar; $winningRule = $pathHierarchy[-1].Rule; $baseDestinationPath = $script:Configuration.paths.destination; if ($IsDownloadMode.IsPresent -and $script:Configuration.paths.downloadDestinationSubfolder) { $baseDestinationPath = Join-Path $baseDestinationPath $script:Configuration.paths.downloadDestinationSubfolder }; $finalDestFolder = Join-Path $baseDestinationPath $pathFromRules; if ($winningRule.PSObject.Properties.Name -contains 'dynamic_folders' -and $winningRule.dynamic_folders) { $dateToUse = $File.LastWriteTime; $dynamicPathParts = [System.Collections.Generic.List[string]]::new(); $addYear = ($winningRule.dynamic_folders.by_year -or $winningRule.dynamic_folders.by_month); if ($addYear) { $dynamicPathParts.Add($dateToUse.ToString("yyyy")) }; if ($winningRule.dynamic_folders.by_month) { $cultureString = if ($script:Configuration.settings.cultureInfo) { $script:Configuration.settings.cultureInfo } else { 'it-IT' }; $culture = [cultureinfo]::GetCultureInfo($cultureString); $dynamicPathParts.Add($dateToUse.ToString("MM - MMMM", $culture)) }; if ($winningRule.dynamic_folders.by_extension) { $dynamicPathParts.Add($File.Extension.TrimStart('.').ToUpper()) }; if ($dynamicPathParts.Count -gt 0) { $finalDestFolder = Join-Path $finalDestFolder ($dynamicPathParts -join [System.IO.Path]::DirectorySeparatorChar) } }; $originalFileName = $File.Name; $newFileName = Apply-RenameRules -OriginalFileName $originalFileName; $wasRenamed = $newFileName -ne $originalFileName; $renameLogInfo = if ($wasRenamed) { " (rinominato da '$originalFileName')" } else { "" }; $finalDestPath = Join-Path $finalDestFolder $newFileName; if ($wasRenamed) { $script:RenamedFilesLog.Add([pscustomobject]@{ Timestamp=(Get-Date -Format 'dd-MM-yyyy HH:mm:ss'); OriginalPath=$File.FullName; OriginalName=$originalFileName; NewName=$newFileName; DestinationPath=$finalDestPath}) }; $fileHash = $null; $isDuplicateInDestination = $false; $isDuplicateInSourceRun = $false; if ($File.Length -gt 0) { $fileHash = Get-FileMD5Hash -FilePath $File.FullName; if ($fileHash) { $isDuplicateInDestination = $script:DestinationInitialHashMap.ContainsKey($fileHash); $isDuplicateInSourceRun = $RunHashMap.ContainsKey($fileHash) } }; Write-DebugLog -Message "File '$($File.Name)': Hash=`'$($fileHash)`'. Duplicato in Destinazione=$isDuplicateInDestination. Duplicato in Sorgente=$isDuplicateInSourceRun."; if ($isDuplicateInDestination) {
        $existingFilePath = $script:DestinationInitialHashMap[$fileHash]

        if ($existingFilePath -eq $finalDestPath) {
            Write-Log -Level 'INFO' -Message "DUPLICATO (IDENTICO): Il file '$($File.FullName)' è già presente e correttamente posizionato in '$existingFilePath'. Ignorato."
            . $logIgnored "Duplicato identico già in posizione corretta"
            $script:Counters.Ignored++
            return 
        }

        Write-Log -Level 'INFO' -Message "DUPLICATO (vs ARCHIVIO): Trovato duplicato per '$($File.FullName)', già presente come '$existingFilePath'."; $duplicateHandlingMode = if( -not [string]::IsNullOrEmpty($DuplicateHandlingOverride)) { $DuplicateHandlingOverride } else { $script:Configuration.settings.duplicateHandling }; switch ($duplicateHandlingMode) { "CreateShortcut" { $shortcutName = "$newFileName.lnk"; $shortcutRelativePath = $finalDestFolder.Substring($script:Configuration.paths.destination.Length).TrimStart('\/'); $shortcutToTargetExists = $false; $existingShortcuts = Get-ChildItem -Path $finalDestFolder -Filter *.lnk -ErrorAction SilentlyContinue; if ($existingShortcuts) { $wshShell = New-Object -ComObject WScript.Shell; foreach ($lnk in $existingShortcuts) { try { $target = $wshShell.CreateShortcut($lnk.FullName).TargetPath; if ($target -eq $existingFilePath) { $shortcutToTargetExists = $true; break } } catch {} } }; if ($shortcutToTargetExists) { Write-Log -Level 'INFO' -Message "DUPLICATO: Creazione shortcut per '$newFileName' saltata, un collegamento allo stesso file esiste già."; $script:Counters.Ignored++ } else { $fileObject = [pscustomobject]@{ Name=$shortcutName; Size=(Format-Bytes -bytes $File.Length); IsShortcut=$true; Comment="Collegamento a duplicato in archivio: `"$($existingFilePath)`""; Length=$File.Length }; Add-ToVirtualTree -Tree $script:VirtualDestinationTree -RelativePath $shortcutRelativePath -FileObject $fileObject; $script:Counters.Shortcuts++; if ($OperationMode -ne 'DryRun') { $longFinalDestFolder = Get-LongPath -Path $finalDestFolder; if (-not (Test-Path $longFinalDestFolder)) { New-Item -Path $longFinalDestFolder -ItemType Directory -Force | Out-Null }; try { $shortcutDestPath = Join-Path $finalDestFolder $shortcutName; New-Shortcut -ShortcutPath $shortcutDestPath -TargetPath $existingFilePath; $script:ShortcutsLog.Add([pscustomobject]@{Timestamp=(Get-Date -Format 'dd-MM-yyyy HH:mm:ss');ShortcutPath=$shortcutDestPath;TargetPath=$existingFilePath}); Write-Log -Level 'INFO' -Message "DUPLICATO: Creato collegamento per '$($File.FullName)' in '$shortcutDestPath'.$renameLogInfo" } catch { $errMsg = "Errore durante la creazione dello shortcut per '$($File.FullName)'. Errore: $($_.Exception.Message)"; Write-Log -Level 'ERROR' -Message $errMsg; $script:ErrorFilesLog.Add([pscustomobject]@{Timestamp=(Get-Date -Format 'dd-MM-yyyy HH:mm:ss');FilePath=$File.FullName;Reason=$errMsg}); $script:Counters.Errors++ } } else { Write-Log -Level 'INFO' -Message "DRYRUN: Verrebbe creato collegamento '$shortcutName' in '$finalDestFolder'.$renameLogInfo"; $script:ShortcutsLog.Add([pscustomobject]@{Timestamp='DRYRUN';ShortcutPath=(Join-Path $finalDestFolder $shortcutName);TargetPath=$existingFilePath}) } } }; "Ignore" { $script:Counters.Ignored++; Write-Log -Level 'INFO' -Message "DUPLICATO: File '$($File.FullName)' ignorato perché già presente in archivio."; . $logIgnored "Duplicato ignorato (vs archivio)" }; "DeleteSource" { if ($OperationMode -eq 'Move') { $script:Counters.DuplicatesDeleted++; Write-Log -Level 'INFO' -Message "AVVISO - CANCELLAZIONE DUPLICATO: Il file '$($File.FullName)' verrà cancellato dalla sorgente perché già presente in archivio."; if ($OperationMode -ne 'DryRun') { try { Remove-Item -LiteralPath (Get-LongPath -Path $File.FullName) -Force -ErrorAction Stop; $script:DeletedDuplicatesLog.Add([pscustomobject]@{Timestamp=(Get-Date -Format 'dd-MM-yyyy HH:mm:ss');FilePath=$File.FullName;Reason="Duplicato (vs archivio) rimosso da sorgente."}) } catch { $errMsg = "Impossibile eliminare file duplicato '$($File.FullName)'. Errore: $($_.Exception.Message)"; Write-Log -Level 'ERROR' -Message $errMsg; $script:ErrorFilesLog.Add([pscustomobject]@{Timestamp=(Get-Date -Format 'dd-MM-yyyy HH:mm:ss');FilePath=$File.FullName;Reason=$errMsg}); $script:Counters.Errors++ } } } else { $script:Counters.Ignored++; Write-Log -Level 'INFO' -Message "DUPLICATO (IGNORE): File '$($File.FullName)' ignorato. La cancellazione (vs archivio) è attiva solo in modalità 'Move'."; . $logIgnored "Duplicato ignorato (DeleteSource solo in Move)" } } } } elseif ($isDuplicateInSourceRun) { $script:Counters.Ignored++; $originalSourceFile = $RunHashMap[$fileHash]; $logMessage = "Duplicato ignorato (contenuto identico a '$originalSourceFile' già processato da sorgente in questa sessione)."; Write-Log -Level 'INFO' -Message "DUPLICATO (SORGENTE): File '$($File.FullName)' ignorato. $logMessage"; . $logIgnored $logMessage } else { $fileObject = [pscustomobject]@{ Name=$newFileName; Size=(Format-Bytes -bytes $File.Length); IsShortcut=$false; Comment=""; Length=$File.Length }; Add-ToVirtualTree -Tree $script:VirtualDestinationTree -RelativePath $finalDestFolder.Substring($script:Configuration.paths.destination.Length).TrimStart('\/') -FileObject $fileObject; if ($File.LastWriteTime -gt (Get-Date).AddDays(-30)) { $script:RecentFilesLog.Add([pscustomobject]@{Path=$finalDestPath; LastWriteTime=$File.LastWriteTime; SizeInBytes=$File.Length}) }; if ($OperationMode -eq 'DryRun') { $script:Counters.Simulated++; Write-Log -Level 'INFO' -Message "DRYRUN: $LogPrefix Verrebbe processato '$($File.FullName)' in '$finalDestPath'.$renameLogInfo" } else { $longFinalDestFolder = Get-LongPath -Path $finalDestFolder; if (-not (Test-Path $longFinalDestFolder)) { New-Item -Path $longFinalDestFolder -ItemType Directory -Force | Out-Null }; $longFinalDestPath = Get-LongPath -Path $finalDestPath; $longSourcePath = Get-LongPath -Path $File.FullName; if ($OperationMode -eq 'Copy') { $script:Counters.Copied++; Write-Log -Level 'INFO' -Message "COPIA: $LogPrefix '$($File.FullName)' -> '$finalDestPath'.$renameLogInfo"; try { Copy-Item -LiteralPath $longSourcePath -Destination $longFinalDestPath -Force -ErrorAction Stop } catch { $errMsg = "Impossibile copiare il file '$($File.FullName)'. Errore: $($_.Exception.Message)"; Write-Log -Level 'ERROR' -Message $errMsg; $script:ErrorFilesLog.Add([pscustomobject]@{Timestamp=(Get-Date -Format 'dd-MM-yyyy HH:mm:ss');FilePath=$File.FullName;Reason=$errMsg}); $script:Counters.Errors++ } } elseif ($OperationMode -eq 'Move') { $script:Counters.Moved++; Write-Log -Level 'INFO' -Message "SPOSTA: $LogPrefix '$($File.FullName)' -> '$finalDestPath'.$renameLogInfo"; try { $originalFullPath = $File.FullName; Move-Item -LiteralPath $longSourcePath -Destination $longFinalDestPath -Force; $script:MovedFilesLog.Add([pscustomobject]@{Timestamp=(Get-Date -Format 'dd-MM-yyyy HH:mm:ss'); OriginalPath=$originalFullPath; NewPath=$finalDestPath}) } catch { $errMsg = "Impossibile spostare il file '$($File.FullName)'. Errore: $($_.Exception.Message)"; Write-Log -Level 'ERROR' -Message $errMsg; $script:ErrorFilesLog.Add([pscustomobject]@{Timestamp=(Get-Date -Format 'dd-MM-yyyy HH:mm:ss');FilePath=$File.FullName;Reason=$errMsg}); $script:Counters.Errors++ } } }; if ($fileHash) { $RunHashMap.Add($fileHash, $File.FullName) } } }
function Process-File { param([System.IO.FileInfo]$File, [string]$OperationMode, [hashtable]$RunHashMap); Invoke-FileProcessingLogic -File $File -OperationMode $OperationMode -RunHashMap $RunHashMap }
function Process-DownloadedFile { param([System.IO.FileInfo]$File, [bool]$IsDryRun, [hashtable]$RunHashMap); $operationMode = if ($IsDryRun) { "DryRun" } else { "Move" }; Invoke-FileProcessingLogic -File $File -OperationMode $operationMode -RunHashMap $runHashMap -LogPrefix "(Download)" -DuplicateHandlingOverride "DeleteSource" -IsDownloadMode }
function Remove-EmptyDirectories { param([string]$Path,[bool]$IsDryRun); Write-ReorgLog -Level INFO -Message "Avvio pulizia cartelle vuote..."; $allDirs = Get-ChildItem -Path $Path -Recurse -Directory | Sort-Object -Property FullName -Descending; $delCount = 0; foreach($d in $allDirs){ $longDirPath = Get-LongPath -Path $d.FullName; if(-not(Get-ChildItem -LiteralPath $longDirPath -ErrorAction SilentlyContinue | Select-Object -First 1)){$logMsg="La cartella '$($d.FullName)' è vuota"; $delCount++; if($IsDryRun){Write-ReorgLog -Level DRYRUN -Message "DRYRUN: $logMsg e verrebbe eliminata."}else{try{Remove-Item -LiteralPath $longDirPath -Force -ErrorAction Stop;Write-ReorgLog -Level INFO -Message "$logMsg ed è stata eliminata."}catch{$errMsg="Impossibile eliminare '$($d.FullName)'. Errore: $($_.Exception.Message)";Write-ReorgLog -Level ERROR -Message $errMsg;$script:ErrorFilesLog.Add([pscustomobject]@{Timestamp=(Get-Date -Format 'dd-MM-yyyy HH:mm:ss');FilePath=$d.FullName;Reason=$errMsg})}}}};Write-ReorgLog -Level INFO -Message "Pulizia completata. Gestite $delCount cartelle vuote."}
function Remove-DuplicateShortcuts { 
    param( [string]$Path, [bool]$IsDryRun, [hashtable]$ReorgCounters );
    Write-ReorgLog -Level INFO -Message "Avvio pulizia shortcut duplicati (stesso target)..."; 
    $wshShell = New-Object -ComObject WScript.Shell; 
    $deletedCount = 0;
    $allDirs = Get-ChildItem -Path $Path -Recurse -Directory -ErrorAction SilentlyContinue; 
    $dirList = @($allDirs) + (Get-Item -Path $Path);
    foreach ($dir in $dirList) {
        $shortcuts = Get-ChildItem -Path $dir.FullName -Filter *.lnk -ErrorAction SilentlyContinue;
        if ($shortcuts.Count -lt 2) { continue };
        $targetMap = @{};
        foreach ($shortcut in $shortcuts) { 
            try { 
                $targetPath = $wshShell.CreateShortcut($shortcut.FullName).TargetPath;
                if (-not $targetMap.ContainsKey($targetPath)) { $targetMap[$targetPath] = [System.Collections.Generic.List[object]]::new() };
                $targetMap[$targetPath].Add($shortcut) 
            } catch { 
                Write-ReorgLog -Level WARN -Message "Impossibile risolvere il target per lo shortcut '$($shortcut.FullName)'. Verrà ignorato."
            } 
        };
        foreach ($target in $targetMap.Keys) { 
            $group = $targetMap[$target];
            if ($group.Count -lt 2) { continue };
            
            $oldest = $group | Sort-Object CreationTime | Select-Object -First 1;
            $toDelete = $group | Where-Object { $_.FullName -ne $oldest.FullName };
            foreach ($shortcutToDelete in $toDelete) { 
                $deletedCount++;
                $logMsg = "Trovato shortcut duplicato '$($shortcutToDelete.FullName)' che punta a '$target'. Verrà eliminato (conservato: '$($oldest.Name)')'.";
                if ($IsDryRun) { 
                    Write-ReorgLog -Level DRYRUN -Message "DRYRUN: $logMsg" 
                } else { 
                    try { 
                        Remove-Item -LiteralPath $shortcutToDelete.FullName -Force -ErrorAction Stop;
                        Write-ReorgLog -Level INFO -Message $logMsg 
                    } catch { 
                        $errMsg = "Impossibile eliminare shortcut duplicato '$($shortcutToDelete.FullName)'. Errore: $($_.Exception.Message)";
                        Write-ReorgLog -Level ERROR -Message $errMsg; 
                        $script:ErrorFilesLog.Add([pscustomobject]@{Timestamp = (Get-Date -Format 'dd-MM-yyyy HH:mm:ss'); FilePath = $shortcutToDelete.FullName; Reason = $errMsg}) 
                    } 
                } 
            } 
        } 
    }

    Write-ReorgLog -Level INFO -Message "Pulizia shortcut (stesso target) completata. Trovati e gestiti $deletedCount duplicati.";
    if ($ReorgCounters.ContainsKey('ShortcutsSameTargetDeleted')) { 
        $ReorgCounters['ShortcutsSameTargetDeleted'] += $deletedCount 
    } else { 
        $ReorgCounters['ShortcutsSameTargetDeleted'] = $deletedCount 
    } 
}
function Remove-ObsoleteShortcutsByFilePresence { 
    param( [string]$Path, [bool]$IsDryRun, [hashtable]$ReorgCounters );
    Write-ReorgLog -Level INFO -Message "Avvio pulizia shortcut resi obsoleti da file reali..."; 
    $deletedCount = 0;
    $allDirs = Get-ChildItem -Path $Path -Recurse -Directory -ErrorAction SilentlyContinue; 
    $dirList = @($allDirs) + (Get-Item -Path $Path);
    foreach ($dir in $dirList) { 
        $files = Get-ChildItem -Path $dir.FullName -File -ErrorAction SilentlyContinue;
        if ($files.Count -eq 0) { continue }; 
        
        $fileBasenames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::InvariantCultureIgnoreCase);
        foreach ($file in $files) { 
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name);
            if (-not $fileBasenames.Contains($baseName)) { $null = $fileBasenames.Add($baseName) } 
        };
        $shortcuts = Get-ChildItem -Path $dir.FullName -Filter *.lnk -ErrorAction SilentlyContinue;
        foreach ($shortcut in $shortcuts) { 
            $shortcutBasename = $shortcut.Name.Substring(0, $shortcut.Name.Length - 4);
            
            if ($fileBasenames.Contains($shortcutBasename)) { 
                $deletedCount++;
                $logMsg = "Trovato shortcut obsoleto '$($shortcut.Name)' perché esiste un file con lo stesso nome. Verrà eliminato.";
                if ($IsDryRun) { 
                    Write-ReorgLog -Level DRYRUN -Message "DRYRUN: In '$($dir.FullName)', $logMsg" 
                } else { 
                    try { 
                        Remove-Item -LiteralPath $shortcut.FullName -Force -ErrorAction Stop;
                        Write-ReorgLog -Level INFO -Message "In '$($dir.FullName)', $logMsg" 
                    } catch { 
                        $errMsg = "Impossibile eliminare shortcut obsoleto '$($shortcut.FullName)'. Errore: $($_.Exception.Message)";
                        Write-ReorgLog -Level ERROR -Message $errMsg; 
                        $script:ErrorFilesLog.Add([pscustomobject]@{Timestamp = (Get-Date -Format 'dd-MM-yyyy HH:mm:ss'); FilePath = $shortcut.FullName; Reason = $errMsg}) 
                    } 
                } 
            } 
        } 
    };
    Write-ReorgLog -Level INFO -Message "Pulizia shortcut obsoleti completata. Trovati e gestiti $deletedCount duplicati.";
    if ($ReorgCounters.ContainsKey('ObsoleteShortcutsDeleted')) { 
        $ReorgCounters['ObsoleteShortcutsDeleted'] += $deletedCount 
    } else { 
        $ReorgCounters['ObsoleteShortcutsDeleted'] = $deletedCount 
    } 
}
function Generate-DetailLogs { param([string]$LogIdentifier); $logDir = if($script:DynamicLogPath){ Split-Path $script:DynamicLogPath -Parent } else { Split-Path $script:DynamicReorgLogPath -Parent }; if(-not $logDir){ return }; $ts = Get-Date -Format "dd-MM-yyyy_HH-mm-ss"; if($script:IgnoredFilesLog.Count -gt 0){ $filePath = Join-Path $logDir "Ignored_Files_$($LogIdentifier)_$($ts).csv"; try { $script:IgnoredFilesLog | Export-Csv -Path $filePath -NoTypeInformation -Encoding UTF8 -Delimiter ';'; Write-Host "Log file ignorati: $filePath" -F DarkGray } catch {} }; if($script:ErrorFilesLog.Count -gt 0){ $filePath = Join-Path $logDir "Error_Files_$($LogIdentifier)_$($ts).csv"; try { $script:ErrorFilesLog | Export-Csv -Path $filePath -NoTypeInformation -Encoding UTF8 -Delimiter ';'; Write-Host "Log errori: $filePath" -F Red } catch {} }; if($script:DeletedDuplicatesLog.Count -gt 0){ $filePath = Join-Path $logDir "Deleted_Duplicates_$($LogIdentifier)_$($ts).csv"; try { $script:DeletedDuplicatesLog | Export-Csv -Path $filePath -NoTypeInformation -Encoding UTF8 -Delimiter ';'; Write-Host "Log duplicati cancellati: $filePath" -F DarkGray } catch {} }; if($script:OnlineOnlyFilesLog.Count -gt 0){ $filePath = Join-Path $logDir "OnlineOnly_Skipped_Files_$($LogIdentifier)_$($ts).csv"; try { $script:OnlineOnlyFilesLog | Export-Csv -Path $filePath -NoTypeInformation -Encoding UTF8 -Delimiter ';'; Write-Host "Log file solo online ignorati: $filePath" -F Cyan } catch {} }; if($script:RenamedFilesLog.Count -gt 0){ $filePath = Join-Path $logDir "Renamed_Files_$($LogIdentifier)_$($ts).csv"; try { $script:RenamedFilesLog | Export-Csv -Path $filePath -NoTypeInformation -Encoding UTF8 -Delimiter ';'; Write-Host "Log file rinominati: $filePath" -F Magenta } catch {} }; if($script:MovedFilesLog.Count -gt 0){ $filePath = Join-Path $logDir "Moved_Files_$($LogIdentifier)_$($ts).csv"; try { $script:MovedFilesLog | Export-Csv -Path $filePath -NoTypeInformation -Encoding UTF8 -Delimiter ';'; Write-Host "Log file spostati (Rollback Plan): $filePath" -F Blue } catch {} }; if($script:ShortcutsLog.Count -gt 0){ $filePath = Join-Path $logDir "Shortcuts_Created_$($LogIdentifier)_$($ts).csv"; try { $script:ShortcutsLog | Export-Csv -Path $filePath -NoTypeInformation -Encoding UTF8 -Delimiter ';'; Write-Host "Log collegamenti creati: $filePath" -F Green } catch {} }; if($script:DiskSpaceCheckLog.Count -gt 0){ $filePath = Join-Path $logDir "DiskSpace_Check_Failed_$($LogIdentifier)_$($ts).csv"; try { $script:DiskSpaceCheckLog | Export-Csv -Path $filePath -NoTypeInformation -Encoding UTF8 -Delimiter ';'; Write-Host "Log controllo spazio su disco fallito: $filePath" -F Yellow } catch {} }; if ($script:ConflictLog.Count -gt 0) { $filePath = Join-Path $logDir "Reorg_Conflicts_$($LogIdentifier)_$($ts).csv"; try { $script:ConflictLog | Export-Csv -Path $filePath -NoTypeInformation -Encoding UTF8 -Delimiter ';'; Write-Host "Log conflitti di riorganizzazione: $filePath" -F Yellow } catch {} } }

# --- Orchestrator ---
function Start-Import { 
    param([string]$OperationMode)

    $script:IgnoredFilesLog.Clear();$script:ErrorFilesLog.Clear();$script:DeletedDuplicatesLog.Clear();$script:RecentFilesLog.Clear();$script:OnlineOnlyFilesLog.Clear();$script:RenamedFilesLog.Clear();$script:MovedFilesLog.Clear();$script:ShortcutsLog.Clear();$script:DiskSpaceCheckLog.Clear()
    $startTime=Get-Date
    
    Build-InitialVirtualTreeFromDestination
    
    $runHashMap = [System.Collections.Generic.Dictionary[string, string]]::new()
    Write-Log -Level 'INFO' -Message "--- Inizio Operazione di Importazione ($OperationMode) ---"
    
    $sourcePath = $script:Configuration.paths.source
    $destPath = $script:Configuration.paths.destination
    $allSrcFiles = Get-ChildItem -Path $sourcePath -Recurse -File -ErrorAction SilentlyContinue
    
    Write-Log -Level 'INFO' -Message "Trovati $($allSrcFiles.Count) file in totale nella sorgente."
    
    Pre-IndexDestination

    Write-Log -Level 'INFO' -Message "FASE 1: Processo le cartelle con struttura da preservare...";
    $preservePatterns = $script:Configuration.folderRules.preserveStructureFolders
    $filesToExcludeFromRules = [System.Collections.Generic.List[string]]::new()
    if ($preservePatterns) {
        foreach ($pattern in $preservePatterns) {
            $fullPatternPath = Join-Path $sourcePath $pattern
            $foldersToPreserve = Get-Item -Path $fullPatternPath -ErrorAction SilentlyContinue
            foreach ($folder in $foldersToPreserve) {
                if ($folder.PSIsContainer) {
                    $filesInFolder = Get-ChildItem -Path $folder.FullName -Recurse -File
                    $folderCommentObject = [pscustomobject]@{ IsFolderComment = $true; Comment = "Struttura preservata dalla sorgente" }
                    Add-ToVirtualTree -Tree $script:VirtualDestinationTree -RelativePath $folder.Name -FileObject $folderCommentObject
                    foreach ($file in $filesInFolder) {
                        $script:Counters.Analyzed++
                        $relativePath = $file.FullName.Substring($sourcePath.Length).TrimStart('\/')
                        $finalDestPath = Join-Path $destPath $relativePath
                        $fileObject = [pscustomobject]@{ Name = $file.Name; Size = (Format-Bytes -bytes $file.Length); IsShortcut = $false; Comment = ""; Length = $file.Length }
                        Add-ToVirtualTree -Tree $script:VirtualDestinationTree -RelativePath $relativePath.Replace($file.Name, "").TrimEnd('\/') -FileObject $fileObject
                        if ($OperationMode -eq 'DryRun') {
                            $script:Counters.Simulated++
                        }
                        else {
                            try {
                                $longFinalDestFolder = Get-LongPath -Path (Split-Path $finalDestPath -Parent)
                                if (-not (Test-Path $longFinalDestFolder)) {
                                    New-Item -Path $longFinalDestFolder -ItemType Directory -Force | Out-Null
                                }
                                if ($OperationMode -eq 'Copy') {
                                    Copy-Item -LiteralPath (Get-LongPath -Path $file.FullName) -Destination (Get-LongPath -Path $finalDestPath) -Force
                                    $script:Counters.Copied++
                                }
                                elseif ($OperationMode -eq 'Move') {
                                    Move-Item -LiteralPath (Get-LongPath -Path $file.FullName) -Destination (Get-LongPath -Path $finalDestPath) -Force
                                    $script:Counters.Moved++
                                }
                                $script:MovedFilesLog.Add([pscustomobject]@{Timestamp=(Get-Date -F 'dd-MM-yyyy HH:mm:ss'); OriginalPath=$file.FullName; NewPath=$finalDestPath; Comment="Struttura Preservata"})
                            }
                            catch {
                                $errMsg = "Impossibile processare (Preserva Struttura) il file '$($file.FullName)'. Errore: $($_.Exception.Message)"
                                Write-Log -Level 'ERROR' -Message $errMsg
                                $script:ErrorFilesLog.Add([pscustomobject]@{Timestamp=(Get-Date -Format 'dd-MM-yyyy HH:mm:ss');FilePath=$file.FullName;Reason=$errMsg})
                                $script:Counters.Errors++
                            }
                        }
                    }
                    $logMsg = "Processata cartella '$($folder.FullName)' ($($filesInFolder.Count) file) con modalità (Preserva Struttura)"
                    Write-Log -Level 'INFO' -Message $logMsg
                    $filesInFolder.FullName | ForEach-Object { $filesToExcludeFromRules.Add($_) }
                }
            }
        }
    }
    
    $filesForRulesEngineList = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    $ignorePatterns = $script:Configuration.folderRules.ignoredSourceFolders
    $logIgnored = { param($f,$r)$script:IgnoredFilesLog.Add([pscustomobject]@{Timestamp=(Get-Date -Format 'dd-MM-yyyy HH:mm:ss');FilePath=$f.FullName;Reason=$r}) }
    $tempFiles = $allSrcFiles | Where-Object { $_.FullName -notin $filesToExcludeFromRules }
    if ($ignorePatterns) {
        foreach($f in $tempFiles){
            $isIgnored = $false
            foreach($p in $ignorePatterns){
                $fp = Join-Path $sourcePath $p
                if($f.DirectoryName -like "$fp*"){
                    $script:Counters.Ignored++
                    . $logIgnored $f "Cartella ignorata da config (pattern: $p)"
                    $isIgnored=$true
                    break
                }
            }
            if(-not $isIgnored){
                $filesForRulesEngineList.Add($f)
            }
        }
    }
    else {
        foreach($item in $tempFiles) {
            $filesForRulesEngineList.Add($item)
        }
    }
    
    $filesForRulesEngine = $filesForRulesEngineList
    Write-Log -Level 'INFO' -Message "FASE 2: Trovati $($filesForRulesEngine.Count) file da elaborare con il motore delle regole."
    if($OperationMode -in @('Copy','move') -and $filesForRulesEngine.Count -gt 0){
        Write-Log -Level 'INFO' -Message 'FASE 2: Calcolo spazio su disco necessario...'
        $requiredSpace=0
        $tempHashMap=[System.Collections.Generic.Dictionary[string,bool]]::new()
        $script:DestinationInitialHashMap.Keys|ForEach-Object{$tempHashMap.Add($_,$true)}
        foreach($f in $filesForRulesEngine){
            if(($f.Attributes-band[System.IO.FileAttributes]::Offline) -or $f.Length -eq 0){continue}
            $h=Get-FileMD5Hash -FilePath $f.FullName
            if(-not$h -or $tempHashMap.ContainsKey($h)){continue}
            $requiredSpace+=$f.Length
            $tempHashMap.Add($h,$true)
        }
        $destDriveLetter=([System.IO.Path]::GetPathRoot($destPath)).Substring(0,1)
        $freeSpace=(Get-PSDrive -Name $destDriveLetter).Free
        Write-Log -Level 'INFO' -Message("Spazio richiesto: $(Format-Bytes $requiredSpace). Spazio disponibile: $(Format-Bytes $freeSpace).")
        if($freeSpace-lt $requiredSpace){
            $errMsg="Spazio su disco insufficiente per i file soggetti a regole. Richiesti: $(Format-Bytes $requiredSpace). Disponibili: $(Format-Bytes $freeSpace)."
            Write-Log -Level 'ERROR' -Message $errMsg
            $script:DiskSpaceCheckLog.Add([pscustomobject]@{Timestamp=(Get-Date -Format 'dd-MM-yyyy HH:mm:ss');RequiredSpace=(Format-Bytes $requiredSpace);FreeSpace=(Format-Bytes $freeSpace);Message=$errMsg})
            Generate-DetailLogs -LogIdentifier "DiskCheckFailure"
            [System.Windows.Forms.MessageBox]::Show($errMsg,"Errore Spazio Disco Insufficiente","OK","Error")
            return
        }
    }
    
    foreach($f in $filesForRulesEngine){
        Process-File -File $f -OperationMode $OperationMode -RunHashMap $runHashMap
    }
    
    $endTime=Get-Date
    $duration=New-TimeSpan -Start $startTime -End $endTime
    Write-Log -Level 'INFO' -Message "Operazione completata. Durata: $($duration.TotalSeconds.ToString("F2")) sec."
    Write-Host "`n--- Riepilogo Importazione ---" -ForegroundColor Yellow
    $script:Counters.GetEnumerator()|Sort-Object Name|ForEach-Object{Write-Host "$($_.Name): $($_.Value)"}
    Generate-DetailLogs -LogIdentifier "Import"
    if($script:Configuration.paths.logPath){
        $fileNameSuffix = switch ($OperationMode) {
            'DryRun' { "Simulazione_Import" }
            'Copy'   { "Copia" }
            'Move'   { "Spostamento" }
            default  { "Import" }
        }
        $title = "Report Importazione - $($fileNameSuffix.Replace('_', ' '))"
        $script:Counters["Dimensione Totale Archivio"] = Format-Bytes -bytes $script:VirtualDestinationTree._totalSizeInBytes
        $reportParams = @{
            ReportTitle     = $title
            OutputFilePath  = Join-Path $destPath "Report_${fileNameSuffix}_$(Get-Date -Format 'dd-MM-yyyy_HH-mm-ss').html"
            Counters        = $script:Counters
            RecentFiles     = $script:RecentFilesLog
            ScriptVersion   = $script:Version
            ScriptAuthor    = $script:Author
            DataTree        = $script:VirtualDestinationTree
            DestinationPath = $destPath
        }
        New-HtmlReport @reportParams
    }
    
    if ($OperationMode -in 'Copy', 'Move') {
        Generate-FolderIndexFiles -DestinationPath $destPath
    }
}

function Start-Reorganization { 
    param([bool]$IsDryRun=$false)

    $script:IgnoredFilesLog.Clear();$script:ErrorFilesLog.Clear();$script:DeletedDuplicatesLog.Clear();$script:RecentFilesLog.Clear();$script:OnlineOnlyFilesLog.Clear();$script:RenamedFilesLog.Clear();$script:MovedFilesLog.Clear();$script:ShortcutsLog.Clear();$script:ConflictLog.Clear()
    $startTime=Get-Date
    $destPath=$script:Configuration.paths.destination
    $reorgCounters=@{Scanned=0;Moved=0;Shortcuts=0;Conflicts=0;AlreadyCorrect=0;Excluded=0;ShortcutsSameTargetDeleted=0;ObsoleteShortcutsDeleted=0}
    
    $script:VirtualDestinationTree=@{'_totalSizeInBytes' = 0}

    $modeStr=if($IsDryRun){"(DRYRUN)"}else{"(LIVE)"}
    Write-ReorgLog -Level INFO -Message "--- Inizio Riorganizzazione Destinazione $modeStr ---"
    
    Write-ReorgLog -Level INFO -Message "Passo 1/7: Indicizzazione file..."
    
    $allDestFiles = Get-ChildItem -Path $destPath -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -ne '.lnk' }

    if ($script:Configuration.folderRules.reorgIgnoredFilePatterns) {
        foreach ($pattern in $script:Configuration.folderRules.reorgIgnoredFilePatterns) {
            $allDestFiles = $allDestFiles | Where-Object { $_.Name -notlike $pattern }
        }
    }

    $filesToReorgList = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    $excludePatterns = @()
    if ($script:Configuration.folderRules.reorgIgnoredFolders) { $excludePatterns += $script:Configuration.folderRules.reorgIgnoredFolders }
    if ($script:Configuration.folderRules.preserveStructureFolders) { $excludePatterns += $script:Configuration.folderRules.preserveStructureFolders }

    if ($excludePatterns.Count -gt 0) {
        foreach ($file in $allDestFiles) {
            $isExcluded = $false
            $relPath = $file.FullName.Substring($destPath.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar)
            $topFolder = ($relPath.Split([System.IO.Path]::DirectorySeparatorChar))[0]
            foreach ($pattern in $excludePatterns) {
                if ($topFolder -like $pattern) {
                    $isExcluded = $true
                    break
                }
            }
            if (-not $isExcluded) { $filesToReorgList.Add($file) }
        }
    } else {
        $filesToReorgList.AddRange($allDestFiles)
    }
    $filesToReorg = $filesToReorgList
    $excludedCount = $allDestFiles.Count - $filesToReorg.Count
    if($excludedCount -gt 0){
        $reorgCounters.Excluded=$excludedCount
        Write-ReorgLog -Level INFO -Message "$excludedCount file esclusi in base ai pattern."
    }

    $destHashMap=@{}
    foreach($f in $filesToReorg){
        if ($f.Length -eq 0) { continue; }
        if(($f.Attributes -band [System.IO.FileAttributes]::Offline)){
            Write-ReorgLog -Level 'INFO' -Message "File ignorato perché solo online: $($f.FullName)"
            $reorgCounters.Excluded++
            $script:OnlineOnlyFilesLog.Add([pscustomobject]@{Timestamp=(Get-Date -Format 'dd-MM-yyyy HH:mm:ss');FilePath=$f.FullName;Size=(Format-Bytes -bytes $f.Length)})
            continue
        }
        $reorgCounters.Scanned++
        $h=Get-FileMD5Hash -FilePath $f.FullName
        if($h){
            if(-not $destHashMap.ContainsKey($h)){$destHashMap[$h]=[System.Collections.Generic.List[string]]::new()}
            $destHashMap[$h].Add($f.FullName)
        }
    }
    Write-ReorgLog -Level INFO -Message "Indicizzati $($reorgCounters.Scanned) file da elaborare."

    Write-ReorgLog -Level INFO -Message "Passo 2/7: Analisi e spostamento file..."
    foreach($h in $destHashMap.Keys){
        $paths=$destHashMap[$h]
        $firstPath=$paths[0]
        $fInfo=Get-Item $firstPath
        $pathHierarchy=Get-DestinationPath -File $fInfo -RuleSet $script:Rules.structures
        
        if(-not $pathHierarchy){
            Write-ReorgLog -Level WARN -Message "File '$($fInfo.Name)' non corrisponde a regola. Ignorato."
            continue
        }

        $correctBasePath = ($pathHierarchy.PathSegment -join [System.IO.Path]::DirectorySeparatorChar)
        $correctFullPath=Join-Path $destPath $correctBasePath
        $correctFullFilePath=Join-Path $correctFullPath $fInfo.Name
        $currentFullPath=Split-Path $firstPath -Parent

        $fileObject = [pscustomobject]@{ Name=$fInfo.Name; Size=(Format-Bytes -bytes $fInfo.Length); IsShortcut=$false; Comment=""; Length=$fInfo.Length }
        Add-ToVirtualTree -Tree $script:VirtualDestinationTree -RelativePath $correctBasePath -FileObject $fileObject
        
        $currentRelativePathForComment = ""
        foreach ($level in $pathHierarchy) {
            $currentRelativePathForComment = if ([string]::IsNullOrEmpty($currentRelativePathForComment)) { $level.PathSegment } else { Join-Path $currentRelativePathForComment $level.PathSegment }
            if ($level.Rule.metadata.comment) {
                $folderComment = [pscustomobject]@{ IsFolderComment = $true; Comment = $level.Rule.metadata.comment }
                Add-ToVirtualTree -Tree $script:VirtualDestinationTree -RelativePath $currentRelativePathForComment -FileObject $folderComment
            }
        }

        if($fInfo.LastWriteTime -gt (Get-Date).AddDays(-30)){$script:RecentFilesLog.Add([pscustomobject]@{Path=$correctFullFilePath;LastWriteTime=$fInfo.LastWriteTime;SizeInBytes=$fInfo.Length})}
        
        if($currentFullPath -ne $correctFullPath){
            $logMsg="Spostamento: '$firstPath' -> '$correctFullFilePath'"
            if($IsDryRun){
                $reorgCounters.Moved++
                Write-ReorgLog -Level DRYRUN -Message "DRYRUN: $logMsg"
            }else{
                $err="CONFLITTO: Impossibile spostare '$firstPath' a '$correctFullFilePath' perché un file con un contenuto diverso esiste già."
                $longCorrectFullFilePath=Get-LongPath -Path $correctFullFilePath
                if((Test-Path $longCorrectFullFilePath)-and((Get-FileMD5Hash $correctFullFilePath)-ne $h)){
                    $reorgCounters.Conflicts++
                    Write-ReorgLog -Level WARN -Message "$err Il file non verrà spostato."
                    $script:ConflictLog.Add([pscustomobject]@{Timestamp=(Get-Date -Format 'dd-MM-yyyy HH:mm:ss');FileNotMoved=$firstPath;AttemptedDestination=$correctFullFilePath;ConflictingFile=$correctFullFilePath})
                }else{
                    $longCorrectFullPath=Get-LongPath -Path $correctFullPath
                    if(-not(Test-Path $longCorrectFullPath)){New-Item -Path $longCorrectFullPath -ItemType Directory -Force|Out-Null}
                    $reorgCounters.Moved++
                    Move-Item -LiteralPath (Get-LongPath -Path $firstPath) -Destination $longCorrectFullFilePath -Force
                    Write-ReorgLog -Level INFO -Message $logMsg
                    $script:MovedFilesLog.Add([pscustomobject]@{Timestamp=(Get-Date -Format 'dd-MM-yyyy HH:mm:ss');OriginalPath=$firstPath;NewPath=$correctFullFilePath})
                }
            }
        }else{
            $reorgCounters.AlreadyCorrect++
        }
        
        if($paths.Count-gt 1){
            for($i=1;$i -lt $paths.Count;$i++){
                $dupPath=$paths[$i]
                $reorgCounters.Shortcuts++
                $target=if(($currentFullPath-ne $correctFullPath)-and($reorgCounters.Conflicts-eq 0)){$correctFullFilePath}else{$firstPath}
                $shortcutPath="$dupPath.lnk"
                $logMsg="DUPLICATO: Sostituzione di '$dupPath' con collegamento a '$target'"

                if($IsDryRun){
                    Write-ReorgLog -Level DRYRUN -Message "DRYRUN: $logMsg"
                }else{
                    Remove-Item -LiteralPath (Get-LongPath -Path $dupPath) -Force
                    New-Shortcut -ShortcutPath $shortcutPath -TargetPath $target
                    Write-ReorgLog -Level INFO -Message $logMsg
                    $script:ShortcutsLog.Add([pscustomobject]@{Timestamp=(Get-Date -Format 'dd-MM-yyyy HH:mm:ss');ShortcutPath=$shortcutPath;TargetPath=$target})
                }
            }
        }
    }
    
    Write-ReorgLog -Level INFO -Message "Passo 3/7: Pulizia collegamenti duplicati (stesso target)..."; Remove-DuplicateShortcuts -Path $destPath -IsDryRun $IsDryRun -ReorgCounters $reorgCounters
    Write-ReorgLog -Level INFO -Message "Passo 4/7: Pulizia collegamenti resi obsoleti da file..."; Remove-ObsoleteShortcutsByFilePresence -Path $destPath -IsDryRun $IsDryRun -ReorgCounters $reorgCounters
    Write-ReorgLog -Level INFO -Message "Passo 5/7: Pulizia cartelle vuote...";Remove-EmptyDirectories -Path $destPath -IsDryRun $IsDryRun
    
    Write-ReorgLog -Level INFO -Message "Passo 6/7: Generazione report e riepilogo..."
    Generate-DetailLogs -LogIdentifier "Reorg"
    $fileNameSuffix = if ($IsDryRun) { "Simulazione_Riorganizzazione" } else { "Riorganizzazione_Eseguita" }
    $reportTitle  = if ($IsDryRun) { "Report Simulazione (DryRun) - Riorganizzazione" } else { "Report Riorganizzazione Eseguita" }
    
    $reorgCounters["Dimensione Totale Archivio"] = Format-Bytes -bytes $script:VirtualDestinationTree._totalSizeInBytes

    $reportParams = @{
        ReportTitle     = $reportTitle
        OutputFilePath  = Join-Path $destPath "Report_${fileNameSuffix}_$(Get-Date -Format 'dd-MM-yyyy_HH-mm-ss').html"
        Counters        = $reorgCounters
        RecentFiles     = $script:RecentFilesLog
        ScriptVersion   = $script:Version
        ScriptAuthor    = $script:Author
        DataTree        = $script:VirtualDestinationTree
        DestinationPath = $destPath
        Conflicts       = $script:ConflictLog
    }
    New-HtmlReport @reportParams

    if (-not $IsDryRun) {
        Generate-FolderIndexFiles -DestinationPath $destPath
    }

    $duration=New-TimeSpan -Start $startTime -End(Get-Date)
    Write-ReorgLog -Level INFO -Message "Passo 7/7: Riepilogo finale Riorganizzazione"
    $reorgCounters.GetEnumerator()|Sort-Object Name|ForEach-Object{Write-ReorgLog -Level INFO -Message "$($_.Name): $($_.Value)"}
    Write-ReorgLog -Level INFO -Message("Durata Totale: {0:N2} secondi" -f $duration.TotalSeconds)
    Write-ReorgLog -Level INFO -Message "--- Fine Riorganizzazione ---"
}
function Start-DownloadProcessing { 
    param([bool]$IsDryRun)

    $script:IgnoredFilesLog.Clear();$script:ErrorFilesLog.Clear();$script:DeletedDuplicatesLog.Clear();$script:RecentFilesLog.Clear();$script:OnlineOnlyFilesLog.Clear();$script:RenamedFilesLog.Clear();$script:MovedFilesLog.Clear();$script:ShortcutsLog.Clear();$script:DiskSpaceCheckLog.Clear()
    $startTime=Get-Date
    
    Build-InitialVirtualTreeFromDestination

    $dlCounters=@{Analyzed=0;Moved=0;DuplicatesDeleted=0;Ignored=0;Errors=0}
    $runHashMap = [System.Collections.Generic.Dictionary[string, string]]::new()
    $modeStr=if($IsDryRun){"(DRYRUN)"}else{"(LIVE)"}
    
    Write-Log -Level 'INFO' -Message "--- Inizio Processo Cartella Download $modeStr ---"
    Pre-IndexDestination
    $dlPath=$script:Configuration.paths.downloadSource
    if(-not(Test-Path $dlPath)){Write-Log -Level 'ERROR' -Message "Cartella di download '$dlPath' non trovata.";return}
    $dlFiles=Get-ChildItem -Path $dlPath -Recurse -File -ErrorAction SilentlyContinue
    if(-not $IsDryRun){Write-Log -Level 'INFO' -Message 'Fase 1/2: Calcolo spazio su disco necessario...';$requiredSpace=0;$tempHashMap=[System.Collections.Generic.Dictionary[string,bool]]::new();$script:DestinationInitialHashMap.Keys|ForEach-Object{$tempHashMap.Add($_,$true)};foreach($f in $dlFiles){if(($f.Attributes-band[System.IO.FileAttributes]::Offline)){continue};$ext=$f.Extension.TrimStart('.');if($script:Configuration.fileFilters.extensions-and$ext-notin$script:Configuration.fileFilters.extensions){continue};if($f.Length-lt($script:Configuration.fileFilters.minSizeKB*1024)){continue};if($f.Length-gt($script:Configuration.fileFilters.maxSizeMB*1024*1024)){continue};$pathHierarchy=Get-DestinationPath -File $f -RuleSet $script:Rules.structures;if(-not $pathHierarchy){continue};$h=Get-FileMD5Hash -FilePath $f.FullName;if(-not$h -or $tempHashMap.ContainsKey($h)){continue};$requiredSpace+=$f.Length;$tempHashMap.Add($h,$true)};$destDriveLetter=([System.IO.Path]::GetPathRoot($script:Configuration.paths.destination)).Substring(0,1);$freeSpace=(Get-PSDrive -Name $destDriveLetter).Free;Write-Log -Level 'INFO' -Message("Spazio richiesto: $(Format-Bytes $requiredSpace). Spazio disponibile: $(Format-Bytes $freeSpace).");if($freeSpace-lt $requiredSpace){$errMsg="Spazio su disco insufficiente. Richiesti: $(Format-Bytes $requiredSpace). Disponibili: $(Format-Bytes $freeSpace).";Write-Log -Level 'ERROR' -Message $errMsg;$script:DiskSpaceCheckLog.Add([pscustomobject]@{Timestamp=(Get-Date -Format 'dd-MM-yyyy HH:mm:ss');RequiredSpace=(Format-Bytes $requiredSpace);FreeSpace=(Format-Bytes $freeSpace);Message=$errMsg});Generate-DetailLogs -LogIdentifier "DiskCheckFailure";[System.Windows.Forms.MessageBox]::Show($errMsg,"Errore Spazio Disco Insufficiente","OK","Error");return};Write-Log -Level 'INFO' -Message "Fase 2/2: Esecuzione operazione..."}
    Write-Log -Level 'INFO' -Message "Trovati $($dlFiles.Count) file da processare."
    foreach($f in $dlFiles){ Process-DownloadedFile -File $f -IsDryRun $IsDryRun -RunHashMap $runHashMap -Counters $dlCounters }
    $endTime=Get-Date
    $duration=New-TimeSpan -Start $startTime -End $endTime
    Write-Log -Level 'INFO' -Message "Processo completato. Durata: $($duration.TotalSeconds.ToString("F2")) sec."
    Write-Host "`n--- Riepilogo Processo Download ---" -ForegroundColor Yellow
    $dlCounters.GetEnumerator()|Sort-Object Name|ForEach-Object{Write-Host "$($_.Name): $($_.Value)"}
    Generate-DetailLogs -LogIdentifier "Download"
    $destPath = $script:Configuration.paths.destination
    $fileNameSuffix = if ($IsDryRun) { "Simulazione_Download" } else { "Processo_Download_Eseguito" }
    $reportTitle  = if ($IsDryRun) { "Report Simulazione (DryRun) - Processa Download" } else { "Report Processo Download Eseguito" }
    $totalSizeInBytes = $script:VirtualDestinationTree._totalSizeInBytes
    $dlCounters["Dimensione Totale Archivio"] = Format-Bytes -bytes $totalSizeInBytes
    $reportParams = @{ ReportTitle = $reportTitle; OutputFilePath = Join-Path $destPath "Report_${fileNameSuffix}_$(Get-Date -Format 'dd-MM-yyyy_HH-mm-ss').html"; Counters = $dlCounters; RecentFiles = $script:RecentFilesLog; ScriptVersion = $script:Version; ScriptAuthor = $script:Author; DataTree = $script:VirtualDestinationTree; DestinationPath = $destPath }
    New-HtmlReport @reportParams
    Write-Host "`nReport generato." -ForegroundColor Green 
}


# --- Blocco di Esecuzione Principale ---
Write-Host "`n--- File Organizer v$($script:Version) | Autore: $($script:Author) ---" -ForegroundColor Yellow

[System.Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "INFO: Tentativo di localizzare il file di configurazione tramite Get-ConfigurationPaths..."
$configPath = Get-ConfigurationPaths

if ([string]::IsNullOrWhiteSpace($configPath)) {
    Write-Error "ERRORE CRITICO: Impossibile localizzare 'config.json'."
    Read-Host "Premere INVIO per uscire."
    exit 1
}

Write-Host "SUCCESS: File di configurazione localizzato in: '$configPath'" -ForegroundColor Green

# Validazione preventiva
$rulesFilePathForValidation = ""
try {
    $tempConfig = Get-Content -Path $configPath -Raw | ConvertFrom-Json
    $projectRoot = (Split-Path $configPath -Parent) | Split-Path -Parent
    $rulesFilePathForValidation = if ([System.IO.Path]::IsPathRooted($tempConfig.paths.rules_file)) { $tempConfig.paths.rules_file } else { Join-Path $projectRoot $tempConfig.paths.rules_file }
}
catch {
    Write-Error "Impossibile leggere il file di configurazione '$configPath' per la validazione."
    exit 1
}
if (-not (Test-ConfigurationIntegrity -ConfigPath $configPath -RulesPath $rulesFilePathForValidation)) {
    Write-Error "Validazione fallita. Correggere gli errori nei file JSON prima di procedere."
    exit 1
}

# Caricamento effettivo
Load-ConfigAndValidate -Path $configPath

$projectRoot = (Split-Path $configPath -Parent) | Split-Path -Parent
$rulesFilePath = if ([System.IO.Path]::IsPathRooted($script:Configuration.paths.rules_file)) { $script:Configuration.paths.rules_file } else { Join-Path $projectRoot $script:Configuration.paths.rules_file }
Load-Rules -RulesPath $rulesFilePath
Set-DynamicLogPaths

# Determina e conferma il percorso sorgente da utilizzare per la sessione corrente.
Confirm-SourcePath

[System.Console]::WriteLine("`nSeleziona una modalità operativa:")
[System.Console]::WriteLine("")
[System.Console]::WriteLine("-- Organizzazione da Sorgente Standard --")
[System.Console]::WriteLine("1. DryRun (Simula importazione)")
[System.Console]::WriteLine("2. Copy")
[System.Console]::WriteLine("3. Move")
[System.Console]::WriteLine("")
[System.Console]::WriteLine("-- Manutenzione Destinazione --")
[System.Console]::WriteLine("4. Reorganize Destination (DRYRUN)")
[System.Console]::WriteLine("5. Reorganize Destination (ESEGUI)")
[System.Console]::WriteLine("")
[System.Console]::WriteLine("-- Processa Cartella Download --")
[System.Console]::WriteLine("6. Process Downloads (DRYRUN)")
[System.Console]::WriteLine("7. Process Downloads (ESEGUI)")
[System.Console]::WriteLine("")
[System.Console]::WriteLine("Q. Esci   - Termina lo script")

$choice = Read-Host "Inserisci la tua scelta"
switch ($choice) {
    '1' { Start-Import -OperationMode 'DryRun' }
    '2' { Start-Import -OperationMode 'Copy' }
    '3' { Start-Import -OperationMode 'Move' }
    '4' { Start-Reorganization -IsDryRun $true }
    '5' { Start-Reorganization -IsDryRun $false }
    '6' { Start-DownloadProcessing -IsDryRun $true }
    '7' { Start-DownloadProcessing -IsDryRun $false }
    'q' { Write-Host "Operazione annullata dall'utente." }
    default { Write-Error "Scelta non valida. Uscita." }
}
Write-Host "`nScript terminato." -ForegroundColor Green