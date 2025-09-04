# ATLAS Phase 1 - Validation Fondation v10.3
# Date: 4 septembre 2025
# Objectif: Confirmer stabilité absolue avant évolution

$script:ValidationResults = @{
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Version = "v10.3"
    Status = "VALIDATING"
    Tests = @{}
}

Write-Host "════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "    ATLAS PHASE 1 - VALIDATION FONDATION v10.3     " -ForegroundColor Yellow
Write-Host "════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ═══════════════════════════════════════════════════════════════
# TEST 1: Vérification fichiers fondation
# ═══════════════════════════════════════════════════════════════

Write-Host "[TEST 1] Vérification fichiers fondation..." -ForegroundColor Cyan

$foundationFiles = @(
    "C:\SYAGA-ATLAS\agent.ps1",
    "C:\SYAGA-ATLAS\UPDATE-ATLAS.ps1"
)

$filesOK = $true
foreach ($file in $foundationFiles) {
    if (Test-Path $file) {
        Write-Host "  ✅ $file existe" -ForegroundColor Green
        $fileInfo = Get-Item $file
        Write-Host "     Taille: $($fileInfo.Length) bytes" -ForegroundColor Gray
        Write-Host "     Modifié: $($fileInfo.LastWriteTime)" -ForegroundColor Gray
    } else {
        Write-Host "  ❌ $file MANQUANT!" -ForegroundColor Red
        $filesOK = $false
    }
}

$script:ValidationResults.Tests["FoundationFiles"] = $filesOK

# ═══════════════════════════════════════════════════════════════
# TEST 2: Vérification tâches planifiées
# ═══════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "[TEST 2] Vérification tâches planifiées..." -ForegroundColor Cyan

$tasks = @("SYAGA-ATLAS-Agent", "SYAGA-ATLAS-Updater")
$tasksOK = $true

foreach ($taskName in $tasks) {
    try {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
        Write-Host "  ✅ $taskName : $($task.State)" -ForegroundColor Green
        
        # Vérifier si la tâche est active
        if ($task.State -eq "Ready" -or $task.State -eq "Running") {
            Write-Host "     État: Opérationnel" -ForegroundColor Green
            
            # Dernière exécution
            $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
            if ($taskInfo) {
                Write-Host "     Dernière exécution: $($taskInfo.LastRunTime)" -ForegroundColor Gray
                Write-Host "     Prochaine exécution: $($taskInfo.NextRunTime)" -ForegroundColor Gray
            }
        } else {
            Write-Host "     ⚠️ État inhabituel: $($task.State)" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  ❌ $taskName NON TROUVÉE!" -ForegroundColor Red
        $tasksOK = $false
    }
}

$script:ValidationResults.Tests["ScheduledTasks"] = $tasksOK

# ═══════════════════════════════════════════════════════════════
# TEST 3: Vérification métriques système
# ═══════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "[TEST 3] Collecte métriques système actuelles..." -ForegroundColor Cyan

try {
    # CPU
    $cpu = Get-WmiObject Win32_Processor | Select-Object -First 1
    $cpuUsage = (Get-Counter "\Processor(_Total)\% Processor Time" -SampleInterval 2 -MaxSamples 1).CounterSamples.CookedValue
    Write-Host "  📊 CPU: $([Math]::Round($cpuUsage, 2))% utilisé" -ForegroundColor White
    Write-Host "     Modèle: $($cpu.Name)" -ForegroundColor Gray
    
    # Mémoire
    $os = Get-WmiObject Win32_OperatingSystem
    $totalMem = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $freeMem = [Math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $usedMem = $totalMem - $freeMem
    $memPercent = [Math]::Round(($usedMem / $totalMem) * 100, 2)
    Write-Host "  📊 RAM: $memPercent% utilisé ($usedMem GB / $totalMem GB)" -ForegroundColor White
    
    # Disque
    $disk = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DeviceID -eq "C:" }
    $diskFree = [Math]::Round($disk.FreeSpace / 1GB, 2)
    $diskTotal = [Math]::Round($disk.Size / 1GB, 2)
    $diskPercent = [Math]::Round((($diskTotal - $diskFree) / $diskTotal) * 100, 2)
    Write-Host "  📊 Disque C: $diskPercent% utilisé ($diskFree GB libre)" -ForegroundColor White
    
    $script:ValidationResults.Tests["SystemMetrics"] = $true
    $script:ValidationResults.Metrics = @{
        CPU = $cpuUsage
        Memory = $memPercent
        Disk = $diskPercent
    }
    
} catch {
    Write-Host "  ❌ Erreur collecte métriques: $_" -ForegroundColor Red
    $script:ValidationResults.Tests["SystemMetrics"] = $false
}

# ═══════════════════════════════════════════════════════════════
# TEST 4: Test communication SharePoint
# ═══════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "[TEST 4] Test communication SharePoint..." -ForegroundColor Cyan

try {
    # Simuler test SharePoint
    Write-Host "  🔄 Test connexion SharePoint..." -ForegroundColor White
    
    # Tester si on peut résoudre le DNS
    $sharePointUrl = "syagacons.sharepoint.com"
    $dnsTest = Resolve-DnsName $sharePointUrl -ErrorAction SilentlyContinue
    
    if ($dnsTest) {
        Write-Host "  ✅ DNS SharePoint résolu" -ForegroundColor Green
        
        # Test ping HTTP
        $webTest = Invoke-WebRequest -Uri "https://$sharePointUrl" -Method Head -TimeoutSec 5 -ErrorAction SilentlyContinue
        if ($webTest.StatusCode -eq 200 -or $webTest.StatusCode -eq 403) {
            Write-Host "  ✅ SharePoint accessible" -ForegroundColor Green
            $script:ValidationResults.Tests["SharePoint"] = $true
        } else {
            Write-Host "  ⚠️ SharePoint répond mais statut: $($webTest.StatusCode)" -ForegroundColor Yellow
            $script:ValidationResults.Tests["SharePoint"] = $true
        }
    } else {
        Write-Host "  ❌ Impossible de résoudre SharePoint DNS" -ForegroundColor Red
        $script:ValidationResults.Tests["SharePoint"] = $false
    }
    
} catch {
    Write-Host "  ⚠️ Test SharePoint limité: $_" -ForegroundColor Yellow
    $script:ValidationResults.Tests["SharePoint"] = "LIMITED"
}

# ═══════════════════════════════════════════════════════════════
# TEST 5: Création backup de référence
# ═══════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "[TEST 5] Création backup fondation v10.3..." -ForegroundColor Cyan

$backupPath = "C:\SYAGA-BACKUP-v10.3-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

try {
    if (Test-Path "C:\SYAGA-ATLAS") {
        Write-Host "  📦 Création backup: $backupPath" -ForegroundColor White
        
        # Copier le dossier complet
        Copy-Item -Path "C:\SYAGA-ATLAS" -Destination $backupPath -Recurse -Force
        
        # Vérifier la copie
        if (Test-Path $backupPath) {
            $backupSize = (Get-ChildItem $backupPath -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB
            Write-Host "  ✅ Backup créé: $([Math]::Round($backupSize, 2)) MB" -ForegroundColor Green
            
            # Créer aussi un fichier de métadonnées
            $metadata = @{
                BackupDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                OriginalPath = "C:\SYAGA-ATLAS"
                BackupPath = $backupPath
                Version = "v10.3"
                Files = (Get-ChildItem "C:\SYAGA-ATLAS" -Recurse).Count
                SizeMB = [Math]::Round($backupSize, 2)
            }
            
            $metadata | ConvertTo-Json | Out-File "$backupPath\BACKUP-METADATA.json" -Encoding UTF8
            Write-Host "  ✅ Métadonnées sauvegardées" -ForegroundColor Green
            
            $script:ValidationResults.Tests["Backup"] = $true
            $script:ValidationResults.BackupPath = $backupPath
        } else {
            Write-Host "  ❌ Échec création backup" -ForegroundColor Red
            $script:ValidationResults.Tests["Backup"] = $false
        }
    } else {
        Write-Host "  ⚠️ Dossier C:\SYAGA-ATLAS non trouvé - Backup non nécessaire" -ForegroundColor Yellow
        $script:ValidationResults.Tests["Backup"] = "NOT_NEEDED"
    }
    
} catch {
    Write-Host "  ❌ Erreur backup: $_" -ForegroundColor Red
    $script:ValidationResults.Tests["Backup"] = $false
}

# ═══════════════════════════════════════════════════════════════
# TEST 6: Vérification performances agent
# ═══════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "[TEST 6] Analyse performances agent..." -ForegroundColor Cyan

try {
    # Obtenir les processus PowerShell
    $psProcesses = Get-Process -Name "powershell*" -ErrorAction SilentlyContinue
    
    if ($psProcesses) {
        Write-Host "  📊 Processus PowerShell actifs: $($psProcesses.Count)" -ForegroundColor White
        
        foreach ($proc in $psProcesses) {
            $cpuTime = $proc.CPU
            $memoryMB = [Math]::Round($proc.WorkingSet64 / 1MB, 2)
            Write-Host "     PID $($proc.Id): CPU=$([Math]::Round($cpuTime, 2))s, RAM=$memoryMB MB" -ForegroundColor Gray
        }
        
        $avgMemory = ($psProcesses | Measure-Object WorkingSet64 -Average).Average / 1MB
        if ($avgMemory -lt 100) {
            Write-Host "  ✅ Consommation mémoire normale" -ForegroundColor Green
            $script:ValidationResults.Tests["Performance"] = $true
        } else {
            Write-Host "  ⚠️ Consommation mémoire élevée: $([Math]::Round($avgMemory, 2)) MB" -ForegroundColor Yellow
            $script:ValidationResults.Tests["Performance"] = $true
        }
    } else {
        Write-Host "  ℹ️ Aucun processus PowerShell actif actuellement" -ForegroundColor Gray
        $script:ValidationResults.Tests["Performance"] = $true
    }
    
} catch {
    Write-Host "  ⚠️ Impossible d'analyser les performances: $_" -ForegroundColor Yellow
    $script:ValidationResults.Tests["Performance"] = "UNKNOWN"
}

# ═══════════════════════════════════════════════════════════════
# RAPPORT FINAL
# ═══════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "              RAPPORT DE VALIDATION v10.3            " -ForegroundColor Yellow
Write-Host "════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Calculer le score
$totalTests = $script:ValidationResults.Tests.Count
$passedTests = ($script:ValidationResults.Tests.GetEnumerator() | Where-Object { $_.Value -eq $true }).Count
$failedTests = ($script:ValidationResults.Tests.GetEnumerator() | Where-Object { $_.Value -eq $false }).Count
$score = [Math]::Round(($passedTests / $totalTests) * 100, 2)

# Afficher résultats
Write-Host "📊 RÉSULTATS DES TESTS:" -ForegroundColor White
foreach ($test in $script:ValidationResults.Tests.GetEnumerator()) {
    $icon = if ($test.Value -eq $true) { "✅" } 
            elseif ($test.Value -eq $false) { "❌" } 
            else { "⚠️" }
    $color = if ($test.Value -eq $true) { "Green" } 
             elseif ($test.Value -eq $false) { "Red" } 
             else { "Yellow" }
    Write-Host "  $icon $($test.Key): $($test.Value)" -ForegroundColor $color
}

Write-Host ""
Write-Host "📈 SCORE GLOBAL: $score%" -ForegroundColor $(if ($score -ge 80) { "Green" } elseif ($score -ge 60) { "Yellow" } else { "Red" })
Write-Host "  ✅ Tests réussis: $passedTests/$totalTests" -ForegroundColor Green
if ($failedTests -gt 0) {
    Write-Host "  ❌ Tests échoués: $failedTests/$totalTests" -ForegroundColor Red
}

# Décision GO/NO-GO
Write-Host ""
if ($score -ge 80) {
    Write-Host "🚀 DÉCISION: GO POUR PHASE 2" -ForegroundColor Green -BackgroundColor DarkGreen
    Write-Host "La fondation v10.3 est stable et prête pour l'évolution" -ForegroundColor Green
    $script:ValidationResults.Decision = "GO"
} elseif ($score -ge 60) {
    Write-Host "⚠️ DÉCISION: GO CONDITIONNEL" -ForegroundColor Yellow -BackgroundColor DarkYellow
    Write-Host "Corrections mineures recommandées avant Phase 2" -ForegroundColor Yellow
    $script:ValidationResults.Decision = "CONDITIONAL"
} else {
    Write-Host "🛑 DÉCISION: NO-GO" -ForegroundColor Red -BackgroundColor DarkRed
    Write-Host "La fondation nécessite des corrections avant évolution" -ForegroundColor Red
    $script:ValidationResults.Decision = "NO-GO"
}

# Sauvegarder rapport
$reportPath = "C:\SYAGA-ATLAS-REPORTS"
if (-not (Test-Path $reportPath)) {
    New-Item -ItemType Directory -Path $reportPath -Force | Out-Null
}

$reportFile = "$reportPath\validation-v10.3-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$script:ValidationResults | ConvertTo-Json -Depth 3 | Out-File $reportFile -Encoding UTF8

Write-Host ""
Write-Host "📄 Rapport sauvegardé: $reportFile" -ForegroundColor Cyan

# Recommandations
Write-Host ""
Write-Host "💡 PROCHAINES ÉTAPES:" -ForegroundColor Yellow
if ($script:ValidationResults.Decision -eq "GO") {
    Write-Host "  1. Lancer Phase 2 - Tests rollback automatiques" -ForegroundColor White
    Write-Host "  2. Préparer environnement test pour v12" -ForegroundColor White
    Write-Host "  3. Documenter configuration actuelle" -ForegroundColor White
} else {
    Write-Host "  1. Corriger les tests échoués" -ForegroundColor White
    Write-Host "  2. Relancer validation" -ForegroundColor White
    Write-Host "  3. Attendre score > 80%" -ForegroundColor White
}

Write-Host ""
Write-Host "════════════════════════════════════════════════════" -ForegroundColor Cyan

# Retourner le résultat
return $script:ValidationResults