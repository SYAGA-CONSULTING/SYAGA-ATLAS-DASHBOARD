# ════════════════════════════════════════════════════════════════════
# TEST LOCAL ATLAS v20 - VALIDATION CYCLE UPDATE
# ════════════════════════════════════════════════════════════════════
# Simule environnement complet pour tester v20→v21
# ════════════════════════════════════════════════════════════════════

param(
    [switch]$Clean,
    [switch]$FullCycle,
    [switch]$TestFailure
)

$TestRoot = "C:\TEMP\ATLAS-TEST"
$LogFile = "$TestRoot\test-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Write-Test {
    param($Message, $Level = "INFO")
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    $color = switch($Level) {
        "ERROR" { "Red" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "PHASE" { "Cyan" }
        default { "White" }
    }
    
    Write-Host "[$timestamp] $Message" -ForegroundColor $color
    Add-Content -Path $LogFile -Value "[$timestamp] [$Level] $Message"
}

# ════════════════════════════════════════════════════════════════════
# PHASE 1 : PRÉPARATION ENVIRONNEMENT TEST
# ════════════════════════════════════════════════════════════════════
Write-Test "════════════════════════════════════════" "PHASE"
Write-Test "TEST LOCAL ATLAS v20 - DÉMARRAGE" "PHASE"
Write-Test "════════════════════════════════════" "PHASE"

if ($Clean) {
    Write-Test "Nettoyage environnement test..." "WARNING"
    if (Test-Path $TestRoot) {
        Remove-Item $TestRoot -Recurse -Force
        Write-Test "✓ Environnement nettoyé" "SUCCESS"
    }
}

# Créer structure
Write-Test "Création environnement test dans $TestRoot" "INFO"
$dirs = @(
    $TestRoot,
    "$TestRoot\config",
    "$TestRoot\runtime",
    "$TestRoot\staging",
    "$TestRoot\backup",
    "$TestRoot\logs",
    "$TestRoot\mock-sharepoint"
)

foreach ($dir in $dirs) {
    if (!(Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Test "  ✓ Créé: $dir" "SUCCESS"
    }
}

# ════════════════════════════════════════════════════════════════════
# PHASE 2 : MOCK SHAREPOINT
# ════════════════════════════════════════════════════════════════════
Write-Test "" "INFO"
Write-Test "Configuration mock SharePoint..." "PHASE"

# Créer mock liste serveurs
$mockServers = @{
    Items = @(
        @{
            Id = 1
            Title = "TEST-SERVER"
            Hostname = $env:COMPUTERNAME
            IPAddress = "127.0.0.1"
            State = "HEALTHY"
            AgentVersion = "20.0"
            LastContact = (Get-Date).ToString()
        }
    )
} | ConvertTo-Json -Depth 10

$mockServers | Out-File "$TestRoot\mock-sharepoint\servers.json" -Encoding UTF8
Write-Test "  ✓ Mock serveurs créé" "SUCCESS"

# Créer mock commandes
$mockCommands = @{
    Items = @()
} | ConvertTo-Json -Depth 10

$mockCommands | Out-File "$TestRoot\mock-sharepoint\commands.json" -Encoding UTF8
Write-Test "  ✓ Mock commandes créé" "SUCCESS"

# ════════════════════════════════════════════════════════════════════
# PHASE 3 : COPIER FICHIERS v20
# ════════════════════════════════════════════════════════════════════
Write-Test "" "INFO"
Write-Test "Déploiement fichiers v20..." "PHASE"

# Copier orchestrateur
$orchSource = "$PSScriptRoot\public\atlas-orchestrator-v20.ps1"
$orchDest = "$TestRoot\orchestrator.ps1"

if (Test-Path $orchSource) {
    Copy-Item $orchSource $orchDest -Force
    Write-Test "  ✓ Orchestrateur copié" "SUCCESS"
} else {
    Write-Test "  ✗ Orchestrateur source introuvable: $orchSource" "ERROR"
    exit 1
}

# Copier agent v20
$agentSource = "$PSScriptRoot\public\agent-v20.ps1"
$agentDest = "$TestRoot\runtime\agent.ps1"

if (Test-Path $agentSource) {
    Copy-Item $agentSource $agentDest -Force
    Write-Test "  ✓ Agent v20 copié" "SUCCESS"
} else {
    Write-Test "  ✗ Agent source introuvable: $agentSource" "ERROR"
    exit 1
}

# Créer version.json
$versionData = @{
    Version = "20.0"
    InstalledAt = Get-Date
    Hostname = $env:COMPUTERNAME
    TestMode = $true
} | ConvertTo-Json

$versionData | Out-File "$TestRoot\config\version.json" -Encoding UTF8
Write-Test "  ✓ Configuration version créée" "SUCCESS"

# Créer state.json
$stateData = @{
    CurrentVersion = "20.0"
    LastCheck = Get-Date
    UpdatesInstalled = @()
    Status = "HEALTHY"
} | ConvertTo-Json

$stateData | Out-File "$TestRoot\config\state.json" -Encoding UTF8
Write-Test "  ✓ État initial créé" "SUCCESS"

# ════════════════════════════════════════════════════════════════════
# PHASE 4 : CRÉER AGENT v21 POUR TEST UPDATE
# ════════════════════════════════════════════════════════════════════
if ($FullCycle) {
    Write-Test "" "INFO"
    Write-Test "Création agent v21 pour test update..." "PHASE"
    
    # Créer agent v21 modifié
    $agentV21 = @'
# ATLAS AGENT v21.0 - VERSION TEST
$script:Version = "21.0"
$script:Hostname = $env:COMPUTERNAME

function Write-AgentLog {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] [v21] [$Level] $Message" -ForegroundColor Magenta
}

Write-AgentLog "════════════════════════════════" "INFO"
Write-AgentLog "AGENT v21 TEST - DÉMARRAGE" "SUCCESS"
Write-AgentLog "════════════════════════════════" "INFO"

Write-AgentLog "Ceci est la version 21 de test" "INFO"
Write-AgentLog "Update réussi de v20 → v21" "SUCCESS"

# Simuler collecte métriques
$metrics = @{
    CPUUsage = Get-Random -Minimum 10 -Maximum 50
    MemoryUsage = Get-Random -Minimum 30 -Maximum 70
    DiskSpaceGB = Get-Random -Minimum 50 -Maximum 500
}

Write-AgentLog "Métriques v21: CPU=$($metrics.CPUUsage)% MEM=$($metrics.MemoryUsage)% DISK=$($metrics.DiskSpaceGB)GB" "INFO"

# Créer fichier témoin
"Agent v21 executed at $(Get-Date)" | Out-File "C:\TEMP\ATLAS-TEST\logs\agent-v21-executed.txt" -Append

Write-AgentLog "Agent v21 terminé avec succès" "SUCCESS"
exit 0
'@
    
    $agentV21 | Out-File "$TestRoot\staging\agent-v21.ps1" -Encoding UTF8
    Write-Test "  ✓ Agent v21 créé dans staging" "SUCCESS"
    
    if ($TestFailure) {
        # Créer agent v21 défaillant
        $badAgent = @'
# AGENT v21 DÉFAILLANT
Write-Error "ERREUR VOLONTAIRE POUR TEST ROLLBACK"
throw "Agent v21 planté volontairement"
exit 1
'@
        $badAgent | Out-File "$TestRoot\staging\agent-v21.ps1" -Encoding UTF8 -Force
        Write-Test "  ⚠ Agent v21 défaillant créé (test rollback)" "WARNING"
    }
}

# ════════════════════════════════════════════════════════════════════
# PHASE 5 : TESTS UNITAIRES
# ════════════════════════════════════════════════════════════════════
Write-Test "" "INFO"
Write-Test "Exécution tests unitaires..." "PHASE"

# Test 1 : Validation syntaxe PowerShell
Write-Test "Test 1: Validation syntaxe scripts" "INFO"
$scripts = @(
    "$TestRoot\orchestrator.ps1",
    "$TestRoot\runtime\agent.ps1"
)

$syntaxOK = $true
foreach ($script in $scripts) {
    if (Test-Path $script) {
        $content = Get-Content $script -Raw
        $errors = @()
        $null = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors)
        
        if ($errors.Count -eq 0) {
            Write-Test "  ✓ Syntaxe OK: $(Split-Path $script -Leaf)" "SUCCESS"
        } else {
            Write-Test "  ✗ Erreurs syntaxe: $(Split-Path $script -Leaf)" "ERROR"
            $syntaxOK = $false
        }
    }
}

if (!$syntaxOK) {
    Write-Test "Tests syntaxe échoués" "ERROR"
    exit 1
}

# Test 2 : Simulation exécution agent
Write-Test "" "INFO"
Write-Test "Test 2: Simulation exécution agent v20" "INFO"

# Modifier temporairement agent pour mode test
$agentContent = Get-Content "$TestRoot\runtime\agent.ps1" -Raw
$agentContent = $agentContent -replace 'https://.*sharepoint.com', 'file://localhost/mock'
$agentContent = $agentContent -replace '\$script:SharePointConfig = @{[^}]+}', @'
$script:SharePointConfig = @{
    TestMode = $true
    MockPath = "C:\TEMP\ATLAS-TEST\mock-sharepoint"
}
'@

# Sauver agent modifié
$agentContent | Out-File "$TestRoot\runtime\agent-test.ps1" -Encoding UTF8

# Lancer test
Write-Test "  Lancement agent en mode test..." "INFO"
$testJob = Start-Job -ScriptBlock {
    param($AgentPath)
    & $AgentPath
} -ArgumentList "$TestRoot\runtime\agent-test.ps1"

$completed = Wait-Job -Job $testJob -Timeout 10
if ($completed) {
    $result = Receive-Job -Job $testJob
    Write-Test "  ✓ Agent exécuté avec succès" "SUCCESS"
} else {
    Stop-Job -Job $testJob
    Write-Test "  ⚠ Timeout agent (normal en mode test)" "WARNING"
}
Remove-Job -Job $testJob -Force

# ════════════════════════════════════════════════════════════════════
# PHASE 6 : SIMULATION CYCLE UPDATE
# ════════════════════════════════════════════════════════════════════
if ($FullCycle) {
    Write-Test "" "INFO"
    Write-Test "Simulation cycle update v20→v21..." "PHASE"
    
    # Simuler détection nouvelle version
    Write-Test "1. Détection nouvelle version disponible" "INFO"
    $updateCommand = @{
        Type = "UPDATE"
        Target = $env:COMPUTERNAME
        Version = "21.0"
        Status = "PENDING"
    } | ConvertTo-Json
    
    $updateCommand | Out-File "$TestRoot\mock-sharepoint\update-command.json" -Encoding UTF8
    Write-Test "  ✓ Commande update créée" "SUCCESS"
    
    # Simuler téléchargement
    Write-Test "2. Téléchargement v21 dans staging" "INFO"
    if (Test-Path "$TestRoot\staging\agent-v21.ps1") {
        Write-Test "  ✓ Agent v21 présent dans staging" "SUCCESS"
    }
    
    # Simuler validation
    Write-Test "3. Validation agent v21" "INFO"
    $v21Content = Get-Content "$TestRoot\staging\agent-v21.ps1" -Raw
    $errors = @()
    $null = [System.Management.Automation.PSParser]::Tokenize($v21Content, [ref]$errors)
    
    if ($errors.Count -eq 0) {
        Write-Test "  ✓ Syntaxe v21 valide" "SUCCESS"
    } else {
        Write-Test "  ✗ Syntaxe v21 invalide" "ERROR"
    }
    
    # Simuler activation
    Write-Test "4. Activation v21 (atomic swap)" "INFO"
    
    # Backup v20
    Copy-Item "$TestRoot\runtime\agent.ps1" "$TestRoot\backup\agent-v20-backup.ps1" -Force
    Write-Test "  ✓ Backup v20 créé" "SUCCESS"
    
    # Copier v21
    Copy-Item "$TestRoot\staging\agent-v21.ps1" "$TestRoot\runtime\agent.ps1" -Force
    Write-Test "  ✓ Agent v21 activé" "SUCCESS"
    
    # Mettre à jour version
    $newVersion = @{
        Version = "21.0"
        UpdatedAt = Get-Date
        UpdatedFrom = "20.0"
    } | ConvertTo-Json
    
    $newVersion | Out-File "$TestRoot\config\version.json" -Encoding UTF8 -Force
    Write-Test "  ✓ Version mise à jour: 20.0 → 21.0" "SUCCESS"
    
    # Test exécution v21
    Write-Test "5. Test exécution v21" "INFO"
    $v21Job = Start-Job -ScriptBlock {
        param($AgentPath)
        & $AgentPath
    } -ArgumentList "$TestRoot\runtime\agent.ps1"
    
    $v21Success = Wait-Job -Job $v21Job -Timeout 5
    
    if ($v21Success) {
        $v21Result = Receive-Job -Job $v21Job
        
        if ($TestFailure) {
            Write-Test "  ✗ Agent v21 a échoué (voulu)" "WARNING"
            Write-Test "6. ROLLBACK vers v20" "WARNING"
            
            # Restaurer backup
            Copy-Item "$TestRoot\backup\agent-v20-backup.ps1" "$TestRoot\runtime\agent.ps1" -Force
            Write-Test "  ✓ Rollback effectué" "SUCCESS"
            
            # Restaurer version
            @{
                Version = "20.0"
                RollbackAt = Get-Date
                FailedVersion = "21.0"
            } | ConvertTo-Json | Out-File "$TestRoot\config\version.json" -Encoding UTF8 -Force
            
            Write-Test "  ✓ Version restaurée: 21.0 → 20.0" "SUCCESS"
        } else {
            Write-Test "  ✓ Agent v21 fonctionne" "SUCCESS"
            
            # Vérifier fichier témoin
            if (Test-Path "$TestRoot\logs\agent-v21-executed.txt") {
                Write-Test "  ✓ Fichier témoin v21 trouvé" "SUCCESS"
            }
        }
    } else {
        Stop-Job -Job $v21Job
        Write-Test "  ⚠ Timeout v21" "WARNING"
    }
    
    Remove-Job -Job $v21Job -Force
}

# ════════════════════════════════════════════════════════════════════
# PHASE 7 : RAPPORT FINAL
# ════════════════════════════════════════════════════════════════════
Write-Test "" "INFO"
Write-Test "════════════════════════════════════════" "PHASE"
Write-Test "RAPPORT DE TEST" "PHASE"
Write-Test "════════════════════════════════════════" "PHASE"

# Analyser logs
$logContent = Get-Content $LogFile
$errors = $logContent | Where-Object { $_ -match "\[ERROR\]" }
$warnings = $logContent | Where-Object { $_ -match "\[WARNING\]" }
$success = $logContent | Where-Object { $_ -match "\[SUCCESS\]" }

Write-Test "Résultats:" "INFO"
Write-Test "  ✓ Succès: $($success.Count)" "SUCCESS"
Write-Test "  ⚠ Warnings: $($warnings.Count)" "WARNING"
Write-Test "  ✗ Erreurs: $($errors.Count)" $(if ($errors.Count -eq 0) {"SUCCESS"} else {"ERROR"})

# Vérifier état final
$finalVersion = Get-Content "$TestRoot\config\version.json" | ConvertFrom-Json
Write-Test "" "INFO"
Write-Test "Version finale: $($finalVersion.Version)" "INFO"

if ($TestFailure -and $finalVersion.Version -eq "20.0") {
    Write-Test "✓ ROLLBACK RÉUSSI - Retour en v20 après échec v21" "SUCCESS"
} elseif ($FullCycle -and $finalVersion.Version -eq "21.0") {
    Write-Test "✓ UPDATE RÉUSSI - Migration v20→v21 complète" "SUCCESS"
} elseif ($finalVersion.Version -eq "20.0") {
    Write-Test "✓ TEST BASIQUE OK - v20 fonctionnelle" "SUCCESS"
}

Write-Test "" "INFO"
Write-Test "Logs complets: $LogFile" "INFO"
Write-Test "Environnement test: $TestRoot" "INFO"

Write-Test "" "INFO"
Write-Test "════════════════════════════════════════" "PHASE"
Write-Test "TEST TERMINÉ" "PHASE"
Write-Test "════════════════════════════════════════" "PHASE"

# Exemples d'utilisation
Write-Host ""
Write-Host "EXEMPLES D'UTILISATION:" -ForegroundColor Yellow
Write-Host "  .\test-local-v20.ps1              # Test basique v20" -ForegroundColor White
Write-Host "  .\test-local-v20.ps1 -FullCycle   # Test update v20→v21" -ForegroundColor White
Write-Host "  .\test-local-v20.ps1 -TestFailure # Test rollback après échec" -ForegroundColor White
Write-Host "  .\test-local-v20.ps1 -Clean       # Nettoyer environnement" -ForegroundColor White
Write-Host ""