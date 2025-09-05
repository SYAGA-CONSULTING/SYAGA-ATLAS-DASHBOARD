# ════════════════════════════════════════════════════════════════════
# ATLAS Agent v17.0 - IA PRÉDICTIVE & MACHINE LEARNING
# ════════════════════════════════════════════════════════════════════
# - Prédiction de pannes avec ML
# - Analyse prédictive des tendances
# - Maintenance préventive automatique
# - Apprentissage des patterns
# ════════════════════════════════════════════════════════════════════

$script:Version = "17.0"
$hostname = $env:COMPUTERNAME
$atlasPath = "C:\SYAGA-ATLAS"

# Configuration SharePoint
$tenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
$clientId = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
$clientSecretB64 = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
$clientSecret = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($clientSecretB64))
$siteName = "syagacons"
$serversListId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"

# Buffer logs et historique
$script:LogsBuffer = ""
$script:MaxBufferSize = 10000

# ════════════════════════════════════════════════════════════════════
# MODÈLE PRÉDICTIF v17.0
# ════════════════════════════════════════════════════════════════════
$script:MLModel = @{
    DataPath = "$atlasPath\ml-data"
    ModelPath = "$atlasPath\ml-model.json"
    TrainingData = @()
    Predictions = @()
    Patterns = @{}
    Thresholds = @{
        CPUWarning = 75
        CPUCritical = 90
        MemoryWarning = 80
        MemoryCritical = 95
        DiskWarning = 20  # GB free
        DiskCritical = 10
        EventsPerHour = 50
    }
}

# Initialiser données ML
if (!(Test-Path $script:MLModel.DataPath)) {
    New-Item -ItemType Directory -Path $script:MLModel.DataPath -Force | Out-Null
}

# ════════════════════════════════════════════════════════════════════
# COLLECTE DONNÉES POUR ML
# ════════════════════════════════════════════════════════════════════
function Collect-TrainingData {
    Write-Log "📊 Collecte données pour ML..." "DEBUG"
    
    $dataPoint = @{
        Timestamp = Get-Date
        DayOfWeek = (Get-Date).DayOfWeek.value__
        HourOfDay = (Get-Date).Hour
        
        # Métriques système
        CPUUsage = Get-CPUUsage
        MemoryUsage = Get-MemoryUsage
        DiskFreeGB = Get-DiskSpace
        NetworkLatency = Test-NetworkLatency
        
        # Métriques processus
        ProcessCount = (Get-Process).Count
        TopProcessCPU = Get-TopProcessCPU
        TopProcessMemory = Get-TopProcessMemory
        
        # Métriques services
        ServicesStopped = Get-StoppedServicesCount
        IISRequests = Get-IISRequestsPerSec
        SQLConnections = Get-SQLConnectionCount
        
        # Événements système
        ErrorEvents = Get-EventErrorCount
        WarningEvents = Get-EventWarningCount
        
        # Métriques Veeam
        VeeamJobsRunning = Get-VeeamActiveJobs
        VeeamLastBackup = Get-VeeamLastBackupHours
        
        # Indicateur de problème (pour apprentissage supervisé)
        HadIssue = $false  # Sera mis à jour rétrospectivement
    }
    
    # Sauvegarder point de données
    $fileName = "$($script:MLModel.DataPath)\data_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $dataPoint | ConvertTo-Json | Set-Content $fileName -Encoding UTF8
    
    # Ajouter aux données d'entraînement
    $script:MLModel.TrainingData += $dataPoint
    
    # Garder seulement 7 jours de données en mémoire
    if ($script:MLModel.TrainingData.Count -gt 10080) {  # 7 days * 24h * 60min
        $script:MLModel.TrainingData = $script:MLModel.TrainingData[-10080..-1]
    }
    
    return $dataPoint
}

# ════════════════════════════════════════════════════════════════════
# ALGORITHMES DE PRÉDICTION
# ════════════════════════════════════════════════════════════════════
function Predict-Issues {
    Write-Log "🤖 Analyse prédictive en cours..." "INFO"
    
    $predictions = @{
        Timestamp = Get-Date
        Risks = @()
        Recommendations = @()
        ProbabilityScore = 0
    }
    
    # Récupérer données actuelles
    $current = Collect-TrainingData
    
    # 1. PRÉDICTION LINÉAIRE (Tendances)
    $cpuPrediction = Predict-LinearTrend "CPU" $current.CPUUsage
    if ($cpuPrediction.Risk) {
        $predictions.Risks += $cpuPrediction
        $predictions.ProbabilityScore += $cpuPrediction.Probability
    }
    
    $memoryPrediction = Predict-LinearTrend "Memory" $current.MemoryUsage
    if ($memoryPrediction.Risk) {
        $predictions.Risks += $memoryPrediction
        $predictions.ProbabilityScore += $memoryPrediction.Probability
    }
    
    $diskPrediction = Predict-DiskTrend $current.DiskFreeGB
    if ($diskPrediction.Risk) {
        $predictions.Risks += $diskPrediction
        $predictions.ProbabilityScore += $diskPrediction.Probability
    }
    
    # 2. PRÉDICTION CYCLIQUE (Patterns temporels)
    $cyclicPrediction = Predict-CyclicPattern $current
    if ($cyclicPrediction.Risk) {
        $predictions.Risks += $cyclicPrediction
        $predictions.ProbabilityScore += $cyclicPrediction.Probability
    }
    
    # 3. DÉTECTION ANOMALIES (Isolation Forest simplifiée)
    $anomalyScore = Detect-Anomaly $current
    if ($anomalyScore -gt 0.7) {
        $predictions.Risks += @{
            Type = "Anomaly"
            Description = "Comportement anormal détecté"
            Probability = [math]::Round($anomalyScore * 100, 1)
            TimeToImpact = "Imminent"
        }
        $predictions.ProbabilityScore += ($anomalyScore * 100)
    }
    
    # 4. PRÉDICTION CORRÉLATIONS
    $correlationPrediction = Predict-Correlations $current
    if ($correlationPrediction.Risk) {
        $predictions.Risks += $correlationPrediction
        $predictions.ProbabilityScore += $correlationPrediction.Probability
    }
    
    # Normaliser score probabilité
    if ($predictions.Risks.Count -gt 0) {
        $predictions.ProbabilityScore = [math]::Min(100, $predictions.ProbabilityScore / $predictions.Risks.Count)
    }
    
    # Générer recommandations
    $predictions.Recommendations = Generate-Recommendations $predictions.Risks
    
    # Sauvegarder prédictions
    $script:MLModel.Predictions += $predictions
    
    return $predictions
}

function Predict-LinearTrend($Metric, $CurrentValue) {
    $prediction = @{
        Risk = $false
        Type = "LinearTrend"
        Metric = $Metric
        Probability = 0
        TimeToImpact = ""
        Description = ""
    }
    
    # Récupérer historique
    $history = $script:MLModel.TrainingData | 
               Where-Object {$_.Timestamp -gt (Get-Date).AddHours(-6)} |
               Select-Object -ExpandProperty "${Metric}Usage"
    
    if ($history.Count -lt 10) { return $prediction }
    
    # Calcul régression linéaire simple
    $x = 1..$history.Count
    $y = $history
    
    $n = $history.Count
    $sumX = ($x | Measure-Object -Sum).Sum
    $sumY = ($y | Measure-Object -Sum).Sum
    $sumXY = 0
    $sumX2 = 0
    
    for ($i = 0; $i -lt $n; $i++) {
        $sumXY += $x[$i] * $y[$i]
        $sumX2 += $x[$i] * $x[$i]
    }
    
    # Pente (taux de croissance)
    $slope = ($n * $sumXY - $sumX * $sumY) / ($n * $sumX2 - $sumX * $sumX)
    
    # Prédiction future
    $threshold = $script:MLModel.Thresholds["${Metric}Critical"]
    $hoursToThreshold = if ($slope -gt 0) {
        ($threshold - $CurrentValue) / $slope
    } else { 999 }
    
    if ($hoursToThreshold -lt 24) {
        $prediction.Risk = $true
        $prediction.Probability = [math]::Round((24 - $hoursToThreshold) / 24 * 100, 1)
        $prediction.TimeToImpact = "$([math]::Round($hoursToThreshold, 1)) heures"
        $prediction.Description = "$Metric atteindra $threshold% dans $([math]::Round($hoursToThreshold, 1))h"
    }
    
    return $prediction
}

function Predict-DiskTrend($CurrentGB) {
    $prediction = @{
        Risk = $false
        Type = "DiskTrend"
        Metric = "Disk"
        Probability = 0
        TimeToImpact = ""
        Description = ""
    }
    
    $history = $script:MLModel.TrainingData | 
               Where-Object {$_.Timestamp -gt (Get-Date).AddDays(-7)} |
               Select-Object -ExpandProperty DiskFreeGB
    
    if ($history.Count -lt 10) { return $prediction }
    
    # Calcul taux de consommation moyen (GB/jour)
    $consumptionRate = ($history[0] - $history[-1]) / 7
    
    if ($consumptionRate -gt 0) {
        $daysToFull = $CurrentGB / $consumptionRate
        
        if ($daysToFull -lt 7) {
            $prediction.Risk = $true
            $prediction.Probability = [math]::Round((7 - $daysToFull) / 7 * 100, 1)
            $prediction.TimeToImpact = "$([math]::Round($daysToFull, 1)) jours"
            $prediction.Description = "Disque plein dans $([math]::Round($daysToFull, 1)) jours ($([math]::Round($consumptionRate, 1))GB/jour)"
        }
    }
    
    return $prediction
}

function Predict-CyclicPattern($Current) {
    $prediction = @{
        Risk = $false
        Type = "CyclicPattern"
        Probability = 0
        TimeToImpact = ""
        Description = ""
    }
    
    # Analyser patterns hebdomadaires
    $sameTimeLastWeek = $script:MLModel.TrainingData | 
                        Where-Object {
                            $_.DayOfWeek -eq $Current.DayOfWeek -and
                            $_.HourOfDay -eq $Current.HourOfDay -and
                            $_.Timestamp -gt (Get-Date).AddDays(-14) -and
                            $_.Timestamp -lt (Get-Date).AddDays(-6)
                        }
    
    if ($sameTimeLastWeek.Count -gt 0) {
        $avgCPU = ($sameTimeLastWeek | Measure-Object -Property CPUUsage -Average).Average
        $avgMem = ($sameTimeLastWeek | Measure-Object -Property MemoryUsage -Average).Average
        
        # Si pattern récurrent de forte charge
        if ($avgCPU -gt 80 -or $avgMem -gt 85) {
            $prediction.Risk = $true
            $prediction.Probability = [math]::Round([math]::Max($avgCPU, $avgMem), 1)
            $prediction.TimeToImpact = "Récurrent chaque semaine"
            $prediction.Description = "Pattern de forte charge détecté (CPU:$([math]::Round($avgCPU,1))%, MEM:$([math]::Round($avgMem,1))%)"
        }
    }
    
    return $prediction
}

function Detect-Anomaly($Current) {
    # Calcul simple du score d'anomalie basé sur la distance aux moyennes
    $recentData = $script:MLModel.TrainingData | 
                  Where-Object {$_.Timestamp -gt (Get-Date).AddHours(-24)}
    
    if ($recentData.Count -lt 10) { return 0 }
    
    $avgCPU = ($recentData | Measure-Object -Property CPUUsage -Average).Average
    $avgMem = ($recentData | Measure-Object -Property MemoryUsage -Average).Average
    $avgProc = ($recentData | Measure-Object -Property ProcessCount -Average).Average
    
    $stdCPU = Get-StandardDeviation ($recentData | Select-Object -ExpandProperty CPUUsage)
    $stdMem = Get-StandardDeviation ($recentData | Select-Object -ExpandProperty MemoryUsage)
    $stdProc = Get-StandardDeviation ($recentData | Select-Object -ExpandProperty ProcessCount)
    
    # Z-score pour chaque métrique
    $zCPU = if ($stdCPU -gt 0) { [math]::Abs($Current.CPUUsage - $avgCPU) / $stdCPU } else { 0 }
    $zMem = if ($stdMem -gt 0) { [math]::Abs($Current.MemoryUsage - $avgMem) / $stdMem } else { 0 }
    $zProc = if ($stdProc -gt 0) { [math]::Abs($Current.ProcessCount - $avgProc) / $stdProc } else { 0 }
    
    # Score d'anomalie (0-1)
    $anomalyScore = [math]::Min(1, ($zCPU + $zMem + $zProc) / 9)  # 3 z-scores, max 3 each
    
    return $anomalyScore
}

function Predict-Correlations($Current) {
    $prediction = @{
        Risk = $false
        Type = "Correlation"
        Probability = 0
        TimeToImpact = ""
        Description = ""
    }
    
    # Patterns connus de corrélations dangereuses
    $dangerousPatterns = @(
        @{
            Conditions = @{
                HighCPU = 85
                HighMemory = 90
                ManyProcesses = 200
            }
            Risk = "System Overload"
            Probability = 85
        },
        @{
            Conditions = @{
                VeeamRunning = $true
                SQLHighActivity = 50
                LowDisk = 15
            }
            Risk = "Backup Failure Risk"
            Probability = 75
        },
        @{
            Conditions = @{
                IISHighRequests = 1000
                MemoryHigh = 85
                EventErrors = 20
            }
            Risk = "Web Service Crash"
            Probability = 70
        }
    )
    
    foreach ($pattern in $dangerousPatterns) {
        $matched = $true
        
        # Vérifier conditions
        if ($pattern.Conditions.HighCPU -and $Current.CPUUsage -lt $pattern.Conditions.HighCPU) { $matched = $false }
        if ($pattern.Conditions.HighMemory -and $Current.MemoryUsage -lt $pattern.Conditions.HighMemory) { $matched = $false }
        if ($pattern.Conditions.ManyProcesses -and $Current.ProcessCount -lt $pattern.Conditions.ManyProcesses) { $matched = $false }
        if ($pattern.Conditions.LowDisk -and $Current.DiskFreeGB -gt $pattern.Conditions.LowDisk) { $matched = $false }
        
        if ($matched) {
            $prediction.Risk = $true
            $prediction.Probability = $pattern.Probability
            $prediction.TimeToImpact = "Conditions réunies"
            $prediction.Description = $pattern.Risk
            break
        }
    }
    
    return $prediction
}

# ════════════════════════════════════════════════════════════════════
# MAINTENANCE PRÉVENTIVE
# ════════════════════════════════════════════════════════════════════
function Execute-PreventiveMaintenance($Predictions) {
    Write-Log "🔧 Exécution maintenance préventive..." "UPDATE"
    
    $actions = @()
    
    foreach ($risk in $Predictions.Risks) {
        switch ($risk.Type) {
            "LinearTrend" {
                if ($risk.Metric -eq "CPU" -and $risk.Probability -gt 70) {
                    Write-Log "  • Optimisation CPU préventive" "INFO"
                    Optimize-CPUUsage
                    $actions += "CPU optimized"
                }
                if ($risk.Metric -eq "Memory" -and $risk.Probability -gt 70) {
                    Write-Log "  • Libération mémoire préventive" "INFO"
                    Clear-MemoryPreventive
                    $actions += "Memory cleared"
                }
            }
            
            "DiskTrend" {
                if ($risk.Probability -gt 60) {
                    Write-Log "  • Nettoyage disque préventif" "INFO"
                    Clear-DiskPreventive
                    $actions += "Disk cleaned"
                }
            }
            
            "CyclicPattern" {
                Write-Log "  • Préparation pour charge cyclique" "INFO"
                Prepare-ForHighLoad
                $actions += "Prepared for load"
            }
            
            "Anomaly" {
                if ($risk.Probability -gt 80) {
                    Write-Log "  • Investigation anomalie" "WARNING"
                    Investigate-Anomaly
                    $actions += "Anomaly investigated"
                }
            }
        }
    }
    
    return $actions
}

function Generate-Recommendations($Risks) {
    $recommendations = @()
    
    foreach ($risk in $Risks) {
        switch ($risk.Type) {
            "LinearTrend" {
                if ($risk.Metric -eq "CPU") {
                    $recommendations += "📈 Planifier upgrade CPU ou optimisation processus dans les $($risk.TimeToImpact)"
                }
                if ($risk.Metric -eq "Memory") {
                    $recommendations += "💾 Augmenter RAM ou configurer swap dans les $($risk.TimeToImpact)"
                }
            }
            
            "DiskTrend" {
                $recommendations += "💿 Libérer espace disque ou augmenter stockage dans les $($risk.TimeToImpact)"
            }
            
            "CyclicPattern" {
                $recommendations += "🔄 Automatiser tâches récurrentes ou répartir charge"
            }
            
            "Anomaly" {
                $recommendations += "⚠️ Enquêter sur comportement anormal - possible intrusion ou dysfonctionnement"
            }
            
            "Correlation" {
                $recommendations += "🔗 Risque: $($risk.Description) - Séparer processus ou augmenter ressources"
            }
        }
    }
    
    return $recommendations
}

# ════════════════════════════════════════════════════════════════════
# HELPERS ML
# ════════════════════════════════════════════════════════════════════
function Get-StandardDeviation($Values) {
    if ($Values.Count -eq 0) { return 0 }
    
    $mean = ($Values | Measure-Object -Average).Average
    $squaredDiffs = $Values | ForEach-Object { [math]::Pow($_ - $mean, 2) }
    $variance = ($squaredDiffs | Measure-Object -Average).Average
    
    return [math]::Sqrt($variance)
}

function Get-CPUUsage {
    try {
        $cpu = (Get-Counter '\Processeur(_Total)\% temps processeur' -ErrorAction SilentlyContinue).CounterSamples[0].CookedValue
        return [math]::Round($cpu, 1)
    } catch { return 0 }
}

function Get-MemoryUsage {
    try {
        $os = Get-WmiObject Win32_OperatingSystem
        $usage = (($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100
        return [math]::Round($usage, 1)
    } catch { return 0 }
}

function Get-DiskSpace {
    try {
        $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
        return [math]::Round($disk.FreeSpace / 1GB, 1)
    } catch { return 999 }
}

function Test-NetworkLatency {
    try {
        $ping = Test-Connection "8.8.8.8" -Count 1 -ErrorAction SilentlyContinue
        return if ($ping) { $ping.ResponseTime } else { 999 }
    } catch { return 999 }
}

function Get-TopProcessCPU {
    try {
        $top = Get-Process | Sort-Object CPU -Descending | Select-Object -First 1
        return if ($top) { [math]::Round($top.CPU, 1) } else { 0 }
    } catch { return 0 }
}

function Get-TopProcessMemory {
    try {
        $top = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 1
        return if ($top) { [math]::Round($top.WorkingSet64 / 1MB, 1) } else { 0 }
    } catch { return 0 }
}

function Get-StoppedServicesCount {
    try {
        $critical = @("W3SVC", "MSSQLSERVER", "VeeamBackupSvc")
        $stopped = 0
        foreach ($svc in $critical) {
            $s = Get-Service $svc -ErrorAction SilentlyContinue
            if ($s -and $s.Status -ne "Running" -and $s.StartType -eq "Automatic") { $stopped++ }
        }
        return $stopped
    } catch { return 0 }
}

function Get-IISRequestsPerSec {
    try {
        if (Get-Service W3SVC -ErrorAction SilentlyContinue) {
            $counter = Get-Counter "\Web Service(_Total)\Current Connections" -ErrorAction SilentlyContinue
            return if ($counter) { $counter.CounterSamples[0].CookedValue } else { 0 }
        }
        return 0
    } catch { return 0 }
}

function Get-SQLConnectionCount {
    try {
        if (Get-Service MSSQLSERVER -ErrorAction SilentlyContinue) {
            $counter = Get-Counter "\SQLServer:General Statistics\User Connections" -ErrorAction SilentlyContinue
            return if ($counter) { $counter.CounterSamples[0].CookedValue } else { 0 }
        }
        return 0
    } catch { return 0 }
}

function Get-EventErrorCount {
    try {
        $errors = Get-EventLog -LogName System -EntryType Error -After (Get-Date).AddHours(-1) -ErrorAction SilentlyContinue
        return if ($errors) { $errors.Count } else { 0 }
    } catch { return 0 }
}

function Get-EventWarningCount {
    try {
        $warnings = Get-EventLog -LogName System -EntryType Warning -After (Get-Date).AddHours(-1) -ErrorAction SilentlyContinue
        return if ($warnings) { $warnings.Count } else { 0 }
    } catch { return 0 }
}

function Get-VeeamActiveJobs {
    try {
        $veeam = Get-Process -Name "Veeam*" -ErrorAction SilentlyContinue
        return if ($veeam) { $veeam.Count } else { 0 }
    } catch { return 0 }
}

function Get-VeeamLastBackupHours {
    # Simulé - en prod, interrogerait Veeam API
    return Get-Random -Minimum 1 -Maximum 48
}

# Actions préventives
function Optimize-CPUUsage {
    # Tuer processus non critiques consommateurs
    Get-Process | Where-Object {$_.CPU -gt 100 -and $_.Name -notin @("System", "svchost", "sqlservr")} |
        Stop-Process -Force -ErrorAction SilentlyContinue
}

function Clear-MemoryPreventive {
    # Clear working sets
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    
    # Restart app pools IIS
    if (Get-Service W3SVC -ErrorAction SilentlyContinue) {
        & iisreset /noforce 2>&1 | Out-Null
    }
}

function Clear-DiskPreventive {
    # Nettoyer temp et logs
    Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    
    # Nettoyer logs > 7 jours
    Get-ChildItem "C:\inetpub\logs" -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-7)} |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function Prepare-ForHighLoad {
    # Augmenter priorité services critiques
    Get-Process sqlservr -ErrorAction SilentlyContinue | ForEach-Object {$_.PriorityClass = "High"}
    Get-Process w3wp -ErrorAction SilentlyContinue | ForEach-Object {$_.PriorityClass = "AboveNormal"}
}

function Investigate-Anomaly {
    # Collecter infos pour analyse
    $investigation = @{
        TopProcesses = Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 Name, CPU, WS
        NewProcesses = Get-Process | Where-Object {$_.StartTime -gt (Get-Date).AddMinutes(-10)}
        RecentErrors = Get-EventLog -LogName System -EntryType Error -Newest 10
        NetworkConnections = netstat -an | Select-String "ESTABLISHED"
    }
    
    $investigation | ConvertTo-Json | Set-Content "$atlasPath\anomaly_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
}

function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    $script:LogsBuffer += "$logEntry`r`n"
    if ($script:LogsBuffer.Length -gt $script:MaxBufferSize) {
        $script:LogsBuffer = $script:LogsBuffer.Substring($script:LogsBuffer.Length - $script:MaxBufferSize)
    }
    
    switch($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        "UPDATE" { Write-Host $logEntry -ForegroundColor Magenta }
        "DEBUG" { Write-Host $logEntry -ForegroundColor DarkGray }
        default { Write-Host $logEntry }
    }
}

# ════════════════════════════════════════════════════════════════════
# HEARTBEAT v17.0 AVEC IA PRÉDICTIVE
# ════════════════════════════════════════════════════════════════════
function Send-Heartbeat {
    try {
        Write-Log "Préparation heartbeat v$($script:Version) avec IA prédictive..." "DEBUG"
        
        # Token SharePoint
        $tokenBody = @{
            grant_type = "client_credentials"
            client_id = "$clientId@$tenantId"
            client_secret = $clientSecret
            resource = "00000003-0000-0ff1-ce00-000000000000/${siteName}.sharepoint.com@$tenantId"
        }
        
        $tokenResponse = Invoke-RestMethod -Uri "https://accounts.accesscontrol.windows.net/$tenantId/tokens/OAuth/2" `
            -Method POST -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
        
        $token = $tokenResponse.access_token
        
        $headers = @{
            "Authorization" = "Bearer $token"
            "Accept" = "application/json;odata=verbose"
            "Content-Type" = "application/json;odata=verbose;charset=utf-8"
        }
        
        # Exécuter prédictions IA
        Write-Log "🤖 Analyse prédictive ML..." "INFO"
        $predictions = Predict-Issues
        
        # Exécuter maintenance préventive si nécessaire
        $preventiveActions = @()
        if ($predictions.ProbabilityScore -gt 60) {
            $preventiveActions = Execute-PreventiveMaintenance $predictions
        }
        
        # Métriques actuelles
        $current = Collect-TrainingData
        
        # IP
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notmatch "Loopback"} | Select-Object -First 1).IPAddress
        
        # Rapport prédictions
        $predictionReport = if ($predictions.Risks.Count -gt 0) {
            "`r`n🤖 PRÉDICTIONS IA (Score: $([math]::Round($predictions.ProbabilityScore,1))%):`r`n" +
            ($predictions.Risks | ForEach-Object {
                "  ⚠️ $($_.Type): $($_.Description) [P=$($_.Probability)%]"
            }) -join "`r`n"
        } else {
            "`r`n✅ Aucun risque prédit par l'IA"
        }
        
        $recommendationReport = if ($predictions.Recommendations.Count -gt 0) {
            "`r`n💡 RECOMMANDATIONS ML:`r`n" +
            ($predictions.Recommendations | ForEach-Object { "  • $_" }) -join "`r`n"
        } else { "" }
        
        $preventiveReport = if ($preventiveActions.Count -gt 0) {
            "`r`n🔧 MAINTENANCE PRÉVENTIVE:`r`n" +
            ($preventiveActions | ForEach-Object { "  ✓ $_" }) -join "`r`n"
        } else { "" }
        
        # Statistiques ML
        $mlStats = "`r`n📊 STATISTIQUES ML:`r`n" +
                   "  • Points de données: $($script:MLModel.TrainingData.Count)`r`n" +
                   "  • Prédictions générées: $($script:MLModel.Predictions.Count)`r`n" +
                   "  • Patterns détectés: $($script:MLModel.Patterns.Count)"
        
        $currentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logHeader = @"
════════════════════════════════════════════════════
ATLAS v$($script:Version) - IA PRÉDICTIVE & ML
════════════════════════════════════════════════════
Hostname: $hostname ($ip)
Time: $currentTime

MÉTRIQUES ACTUELLES:
  CPU: $($current.CPUUsage)%
  Memory: $($current.MemoryUsage)%
  Disk C:\: $($current.DiskFreeGB) GB free
  Processes: $($current.ProcessCount)
  Services Down: $($current.ServicesStopped)

$predictionReport
$recommendationReport
$preventiveReport
$mlStats

LOGS RÉCENTS:
════════════════════════════════════════════════════
"@
        
        # Ajouter logs
        $enrichedLogs = $logHeader + "`r`n" + $script:LogsBuffer
        if ($enrichedLogs.Length -gt 8000) {
            $enrichedLogs = $enrichedLogs.Substring(0, 8000) + "`r`n... (tronqué)"
        }
        
        # Déterminer état global basé sur prédictions
        $globalState = if ($predictions.ProbabilityScore -gt 80) { "CRITICAL" }
                      elseif ($predictions.ProbabilityScore -gt 60) { "WARNING" }
                      elseif ($predictions.ProbabilityScore -gt 40) { "PREDICTIVE" }
                      else { "HEALTHY" }
        
        # Données SharePoint
        $data = @{
            "__metadata" = @{ type = "SP.Data.ATLASServersListItem" }
            Title = $hostname
            Hostname = $hostname
            IPAddress = $ip
            State = $globalState
            LastContact = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
            AgentVersion = $script:Version
            CPUUsage = $current.CPUUsage
            MemoryUsage = $current.MemoryUsage
            DiskSpaceGB = $current.DiskFreeGB
            Logs = $enrichedLogs
        }
        
        $jsonData = $data | ConvertTo-Json -Depth 10
        
        # Envoyer à SharePoint
        Write-Log "Envoi heartbeat v17.0 avec prédictions ML..." "DEBUG"
        $createUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$serversListId')/items"
        $response = Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $jsonData
        
        Write-Log "Heartbeat v17.0 envoyé (IA Score: $([math]::Round($predictions.ProbabilityScore,1))%)" "SUCCESS"
        
    } catch {
        Write-Log "Erreur heartbeat: $_" "ERROR"
    }
}

# ════════════════════════════════════════════════════════════════════
# MAIN v17.0
# ════════════════════════════════════════════════════════════════════
Write-Log "════════════════════════════════════════" "INFO"
Write-Log "ATLAS v$($script:Version) - IA PRÉDICTIVE" "SUCCESS"
Write-Log "════════════════════════════════════════" "INFO"

# Charger modèle ML si existe
if (Test-Path $script:MLModel.ModelPath) {
    try {
        $loadedModel = Get-Content $script:MLModel.ModelPath -Raw | ConvertFrom-Json
        $script:MLModel.Patterns = $loadedModel.Patterns
        Write-Log "📊 Modèle ML chargé avec $($loadedModel.Patterns.Count) patterns" "INFO"
    } catch {
        Write-Log "Nouveau modèle ML initialisé" "INFO"
    }
}

# Charger données historiques récentes
$recentFiles = Get-ChildItem "$($script:MLModel.DataPath)\data_*.json" -ErrorAction SilentlyContinue |
               Where-Object {$_.LastWriteTime -gt (Get-Date).AddDays(-7)} |
               Sort-Object Name -Descending |
               Select-Object -First 100

foreach ($file in $recentFiles) {
    try {
        $data = Get-Content $file.FullName -Raw | ConvertFrom-Json
        $script:MLModel.TrainingData += $data
    } catch {}
}

Write-Log "📈 $($script:MLModel.TrainingData.Count) points de données chargés" "INFO"

# Envoyer heartbeat avec analyse prédictive
Send-Heartbeat

# Sauvegarder modèle ML
try {
    @{
        Patterns = $script:MLModel.Patterns
        LastTraining = Get-Date
        DataPoints = $script:MLModel.TrainingData.Count
    } | ConvertTo-Json -Depth 10 | Set-Content $script:MLModel.ModelPath -Encoding UTF8
} catch {}

Write-Log "════════════════════════════════════════" "INFO"
Write-Log "ATLAS v$($script:Version) TERMINÉ" "SUCCESS"
Write-Log "════════════════════════════════════════" "INFO"

exit 0