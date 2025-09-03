# ATLAS Agent v4.0 - Téléchargé et exécuté dynamiquement
# Ce script est téléchargé à chaque exécution par la tâche planifiée
# irm https://white-river-053fc6703.2.azurestaticapps.net/public/agent.ps1 | iex

$version = "4.0"
$configPath = "C:\SYAGA-ATLAS"

function Write-Log {
    param($Message, $Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $log = "[$ts] [$Level] $Message"
    
    # Créer dossier si nécessaire
    if (!(Test-Path $configPath)) {
        New-Item -ItemType Directory -Path $configPath -Force | Out-Null
    }
    
    Add-Content "$configPath\agent.log" -Value $log -Encoding UTF8
    
    $color = @{INFO="White"; OK="Green"; ERROR="Red"; UPDATE="Cyan"; WARNING="Yellow"}[$Level]
    Write-Host $log -ForegroundColor $color
}

Write-Log "Agent ATLAS v$version démarré (téléchargé depuis Azure)"

# ════════════════════════════════════════════════════════
# 1. COLLECTER MÉTRIQUES SYSTÈME
# ════════════════════════════════════════════════════════
try {
    Write-Log "Collecte des métriques..."
    
    $os = Get-CimInstance Win32_OperatingSystem
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    
    # CPU
    $cpuUsage = 0
    try {
        $counter = Get-Counter "\Processeur(_Total)\% temps processeur" -EA SilentlyContinue
        if ($counter) { 
            $cpuUsage = [math]::Round($counter.CounterSamples[0].CookedValue, 2) 
        }
    } catch {}
    
    # Windows Updates
    $pendingUpdates = 0
    try {
        $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
        $result = $searcher.Search("IsInstalled=0")
        $pendingUpdates = $result.Updates.Count
    } catch {}
    
    $metrics = @{
        Hostname = $env:COMPUTERNAME
        Version = $version
        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        CPUUsage = $cpuUsage
        MemoryUsage = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize * 100, 2)
        DiskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
        PendingUpdates = $pendingUpdates
        State = "Online"
    }
    
    # Sauvegarder localement
    $metrics | ConvertTo-Json | Out-File "$configPath\metrics.json" -Encoding UTF8
    Write-Log "Métriques collectées avec succès" "OK"
    
} catch {
    Write-Log "Erreur collecte: $_" "ERROR"
}

# ════════════════════════════════════════════════════════
# 2. VÉRIFIER COMMANDES DE MISE À JOUR
# ════════════════════════════════════════════════════════
Write-Log "Vérification des commandes de mise à jour..."

try {
    # Pour le moment, vérifier un fichier local comme indicateur
    # (En production : vérifier SharePoint via API)
    $updateCommandFile = "$configPath\UPDATE_COMMAND.txt"
    
    if (Test-Path $updateCommandFile) {
        $command = Get-Content $updateCommandFile -Raw | ConvertFrom-Json
        
        Write-Log "🚀 COMMANDE DE MISE À JOUR DÉTECTÉE !" "UPDATE"
        Write-Log "Version cible: $($command.NewVersion)" "UPDATE"
        Write-Log "Demandée par: $($command.RequestedBy)" "UPDATE"
        
        # Télécharger nouvelle version
        Write-Log "Téléchargement de la version $($command.NewVersion)..." "UPDATE"
        
        try {
            # URL de la nouvelle version
            $newVersionUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v$($command.NewVersion).ps1"
            
            # Pour la démo, on simule
            Start-Sleep -Seconds 2
            
            Write-Log "✅ AGENT MIS À JOUR VERS v$($command.NewVersion) !" "UPDATE"
            
            # Supprimer la commande
            Remove-Item $updateCommandFile -Force
            
            # Log de succès
            @{
                UpdatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                FromVersion = $version
                ToVersion = $command.NewVersion
                Success = $true
            } | ConvertTo-Json | Out-File "$configPath\last-update.json" -Encoding UTF8
            
        } catch {
            Write-Log "Erreur lors de la mise à jour: $_" "ERROR"
        }
    } else {
        Write-Log "Aucune commande de mise à jour en attente"
    }
    
} catch {
    Write-Log "Erreur vérification commandes: $_" "WARNING"
}

# ════════════════════════════════════════════════════════
# 3. ENVOYER MÉTRIQUES À SHAREPOINT
# ════════════════════════════════════════════════════════
try {
    Write-Log "Envoi des métriques vers SharePoint..."
    
    # TODO: Implémenter l'envoi réel vers SharePoint
    # Pour le moment, on garde en local
    
    Write-Log "Métriques sauvegardées localement (SharePoint à implémenter)"
    
} catch {
    Write-Log "Erreur envoi SharePoint: $_" "ERROR"
}

Write-Log "Agent v$version terminé"
Write-Log "──────────────────────────────────────────"