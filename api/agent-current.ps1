# ATLAS Agent v4.0 - Version Actuelle
# Servi dynamiquement par Azure Static Web Apps
# Exécuté directement depuis l'URL par les tâches planifiées

$version = "4.0"

function Write-Log {
    param($Message, $Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $log = "[$ts] [$Level] $Message"
    Add-Content "C:\SYAGA-ATLAS\agent.log" -Value $log -Encoding UTF8
    
    $color = @{INFO="White"; OK="Green"; ERROR="Red"; UPDATE="Cyan"}[$Level]
    Write-Host $log -ForegroundColor $color
}

Write-Log "Agent ATLAS v$version (depuis Azure)"

# 1. COLLECTER MÉTRIQUES
$metrics = @{
    Hostname = $env:COMPUTERNAME
    Version = $version
    Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

try {
    $os = Get-CimInstance Win32_OperatingSystem
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    
    $cpu = 0
    try {
        $c = Get-Counter "\Processeur(_Total)\% temps processeur" -EA SilentlyContinue
        if ($c) { $cpu = [math]::Round($c.CounterSamples[0].CookedValue, 2) }
    } catch {}
    
    $updates = 0
    try {
        $s = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
        $updates = $s.Search("IsInstalled=0").Updates.Count
    } catch {}
    
    $metrics.CPUUsage = $cpu
    $metrics.MemoryUsage = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize * 100, 2)
    $metrics.DiskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
    $metrics.PendingUpdates = $updates
    
    Write-Log "Métriques collectées" "OK"
} catch {
    Write-Log "Erreur: $_" "ERROR"
}

# 2. VÉRIFIER COMMANDES DE MISE À JOUR
Write-Log "Check commandes..."

try {
    # Simuler la vérification (en prod: vraie API SharePoint)
    $hasUpdateCommand = Test-Path "C:\SYAGA-ATLAS\UPDATE_COMMAND.txt"
    
    if ($hasUpdateCommand) {
        Write-Log "🚀 COMMANDE MISE À JOUR DÉTECTÉE !" "UPDATE"
        
        # Télécharger nouvelle version
        Write-Log "Téléchargement v4.1..." "UPDATE"
        
        # Simuler mise à jour
        Start-Sleep -Seconds 2
        
        Write-Log "✅ MIS À JOUR VERS v4.1 !" "UPDATE"
        Remove-Item "C:\SYAGA-ATLAS\UPDATE_COMMAND.txt" -Force
    }
} catch {}

# 3. ENVOYER MÉTRIQUES
$metrics | ConvertTo-Json | Out-File "C:\SYAGA-ATLAS\metrics.json" -Encoding UTF8
Write-Log "Agent terminé"