# --- JsonValidator.psm1 ---

function Test-ConfigurationIntegrity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ConfigPath,
        
        [Parameter(Mandatory=$true)]
        [string]$RulesPath
    )

    $errors = [System.Collections.Generic.List[string]]::new()

    # --- Test 1: Validità Sintassi JSON ---
    Write-Host "INFO: Esecuzione validazione sintassi JSON..." -ForegroundColor Cyan
    
    # Controlla config.json
    try {
        $null = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $errors.Add("Errore di sintassi nel file '$ConfigPath': $($_.Exception.Message)")
    }
    
    # Controlla rules.json
    try {
        $rulesContent = Get-Content -Path $RulesPath -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $errors.Add("Errore di sintassi nel file '$RulesPath': $($_.Exception.Message)")
    }

    # Se ci sono errori di sintassi, non ha senso continuare con il controllo dello schema
    if ($errors.Count -gt 0) {
        Write-Host "`n--- ERRORE DI VALIDAZIONE ---" -ForegroundColor Red
        $errors | ForEach-Object { Write-Error $_ }
        return $false
    }
    
    # --- Test 2: Validità Schema Logico ---
    Write-Host "INFO: Esecuzione validazione schema logico delle regole..." -ForegroundColor Cyan
    
    # Funzione ricorsiva per controllare ogni regola e sottoregola
    function Test-RuleStructure {
        param(
            [psobject[]]$Structures,
            [string]$ParentPath
        )
        
        foreach ($rule in $Structures) {
            $currentPath = if ($ParentPath) { "$ParentPath -> $($rule.name)" } else { $rule.name }

            if (-not $rule.PSObject.Properties.Name -contains 'name') { $errors.Add("Regola in '$currentPath' è senza la chiave 'name'.") }
            if (-not $rule.PSObject.Properties.Name -contains 'priority') { $errors.Add("Regola '$currentPath' è senza la chiave 'priority'.") }
            if (-not $rule.PSObject.Properties.Name -contains 'rules') { $errors.Add("Regola '$currentPath' è senza la chiave 'rules'.") }

            if ($rule.subfolders) {
                Test-RuleStructure -Structures $rule.subfolders -ParentPath $currentPath
            }
        }
    }

    if ($rulesContent.structures) {
        Test-RuleStructure -Structures $rulesContent.structures -ParentPath ""
    } else {
        $errors.Add("Il file '$RulesPath' non contiene la chiave principale 'structures'.")
    }

    if ($errors.Count -gt 0) {
        Write-Host "`n--- ERRORE DI VALIDAZIONE ---" -ForegroundColor Red
        $errors | ForEach-Object { Write-Error $_ }
        return $false
    }

    Write-Host "INFO: Validazione completata con successo. Nessun errore trovato." -ForegroundColor Green
    return $true
}

Export-ModuleMember -Function Test-ConfigurationIntegrity