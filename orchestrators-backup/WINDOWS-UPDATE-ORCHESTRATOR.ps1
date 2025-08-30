# WINDOWS UPDATE ORCHESTRATOR v1.0
# Gestion intelligente des dépendances Hyper-V et Veeam

param(
    [Parameter(Mandatory=$false)]
    [string]$Action = "Analyze",  # Analyze | Plan | Execute | Status
    [string]$TargetServer = $env:COMPUTERNAME
)

$VERSION = "v1.0"
Write-Host "🎯 WINDOWS UPDATE ORCHESTRATOR $VERSION" -ForegroundColor Cyan
Write-Host "=" * 60

# Configuration
$SharePointConfig = @{
    TenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
    ClientId = "f66a8c6c-1037-41b8-be3c-4f6e67c1f49e"
    ClientSecret = "[REDACTED]"  # Remplacer par le vrai secret
    SiteId = "syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8"
    ListId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"
}

# Fonction pour obtenir token
function Get-GraphToken {
    $tokenUrl = "https://login.microsoftonline.com/$($SharePointConfig.TenantId)/oauth2/v2.0/token"
    $body = @{
        client_id = $SharePointConfig.ClientId
        client_secret = $SharePointConfig.ClientSecret
        scope = "https://graph.microsoft.com/.default"
        grant_type = "client_credentials"
    }
    return (Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body).access_token
}

# Fonction pour obtenir l'infrastructure depuis SharePoint
function Get-Infrastructure {
    Write-Host "📊 Récupération infrastructure depuis SharePoint..." -ForegroundColor Yellow
    
    $token = Get-GraphToken
    $headers = @{Authorization = "Bearer $token"}
    $listUrl = "https://graph.microsoft.com/v1.0/sites/$($SharePointConfig.SiteId)/lists/$($SharePointConfig.ListId)/items?`$expand=fields"
    
    $items = Invoke-RestMethod -Uri $listUrl -Headers $headers
    
    $infrastructure = @{
        HyperVHosts = @()
        VMs = @()
        VeeamServers = @()
        StandaloneServers = @()
    }
    
    foreach ($item in $items.value) {
        $server = $item.fields
        
        # Identifier les hôtes Hyper-V
        if ($server.HyperVStatus -and $server.HyperVStatus -like "*VM*") {
            $vmCount = 0
            if ($server.HyperVStatus -match "(\d+)") {
                $vmCount = [int]$Matches[1]
            }
            
            $infrastructure.HyperVHosts += @{
                Name = $server.Hostname
                VMCount = $vmCount
                VeeamStatus = $server.VeeamStatus
                LastContact = $server.LastContact
                WindowsUpdateStatus = $server.WindowsUpdateStatus
            }
        }
        
        # Identifier les serveurs Veeam
        if ($server.VeeamStatus -and $server.VeeamStatus -like "*Installed*") {
            $infrastructure.VeeamServers += $server.Hostname
        }
        
        # TODO: Déterminer quels serveurs sont des VMs (nécessite enrichissement des données)
    }
    
    return $infrastructure
}

# Fonction pour analyser les dépendances
function Analyze-Dependencies {
    param($Infrastructure)
    
    Write-Host "`n🔍 ANALYSE DES DÉPENDANCES" -ForegroundColor Green
    Write-Host "-" * 40
    
    # Hôtes Hyper-V
    Write-Host "`n📌 Hôtes Hyper-V détectés:" -ForegroundColor Cyan
    foreach ($host in $Infrastructure.HyperVHosts) {
        Write-Host "  • $($host.Name) - $($host.VMCount) VMs" -ForegroundColor White
        if ($host.VeeamStatus) {
            Write-Host "    └─ Veeam: $($host.VeeamStatus)" -ForegroundColor Gray
        }
    }
    
    # Serveurs Veeam
    Write-Host "`n📌 Serveurs Veeam:" -ForegroundColor Cyan
    foreach ($veeam in $Infrastructure.VeeamServers) {
        Write-Host "  • $veeam" -ForegroundColor White
    }
    
    # Règles d'orchestration
    Write-Host "`n⚙️ RÈGLES D'ORCHESTRATION" -ForegroundColor Yellow
    Write-Host "1. Les VMs doivent être mises à jour AVANT leur hôte Hyper-V"
    Write-Host "2. Les sauvegardes Veeam doivent être suspendues pendant les updates"
    Write-Host "3. Un seul hôte Hyper-V à la fois pour maintenir la disponibilité"
    Write-Host "4. Attendre que les VMs redémarrent après reboot de l'hôte"
    
    return @{
        Rules = @(
            "VMs before Hosts"
            "Pause Veeam during updates"
            "One Hyper-V host at a time"
            "Wait for VM recovery after host reboot"
        )
        Dependencies = $Infrastructure
    }
}

# Fonction pour créer un plan d'orchestration
function Create-UpdatePlan {
    param($Infrastructure)
    
    Write-Host "`n📝 CRÉATION DU PLAN D'ORCHESTRATION" -ForegroundColor Green
    Write-Host "-" * 40
    
    $plan = @{
        Phases = @()
        EstimatedDuration = 0
    }
    
    # Phase 1: Préparer Veeam
    $plan.Phases += @{
        Order = 1
        Name = "Suspension Veeam"
        Actions = @(
            "Suspendre tous les jobs Veeam"
            "Attendre fin des jobs en cours"
        )
        Duration = 15
        Servers = $Infrastructure.VeeamServers
    }
    
    # Phase 2: Update des VMs (si identifiées)
    $plan.Phases += @{
        Order = 2
        Name = "Update VMs"
        Actions = @(
            "Windows Update sur toutes les VMs"
            "Reboot si nécessaire"
            "Vérifier disponibilité"
        )
        Duration = 60
        Servers = @() # TODO: Lister les VMs
    }
    
    # Phase 3: Update des hôtes Hyper-V (un par un)
    $hostOrder = 1
    foreach ($hvHost in $Infrastructure.HyperVHosts) {
        $plan.Phases += @{
            Order = 2 + $hostOrder
            Name = "Update Hôte $($hvHost.Name)"
            Actions = @(
                "Migrer VMs critiques si possible"
                "Windows Update sur $($hvHost.Name)"
                "Reboot $($hvHost.Name)"
                "Attendre redémarrage des VMs"
                "Vérifier santé des VMs"
            )
            Duration = 45
            Servers = @($hvHost.Name)
        }
        $hostOrder++
    }
    
    # Phase finale: Réactiver Veeam
    $plan.Phases += @{
        Order = 99
        Name = "Réactivation Veeam"
        Actions = @(
            "Réactiver tous les jobs Veeam"
            "Lancer backup de vérification"
        )
        Duration = 10
        Servers = $Infrastructure.VeeamServers
    }
    
    # Calculer durée totale
    $plan.EstimatedDuration = ($plan.Phases | Measure-Object -Property Duration -Sum).Sum
    
    # Afficher le plan
    Write-Host "`n📋 PLAN D'ORCHESTRATION GÉNÉRÉ:" -ForegroundColor Cyan
    foreach ($phase in $plan.Phases | Sort-Object Order) {
        Write-Host "`n🔹 Phase $($phase.Order): $($phase.Name)" -ForegroundColor Yellow
        Write-Host "   Durée estimée: $($phase.Duration) minutes" -ForegroundColor Gray
        Write-Host "   Serveurs: $($phase.Servers -join ', ')" -ForegroundColor Gray
        Write-Host "   Actions:" -ForegroundColor Gray
        foreach ($action in $phase.Actions) {
            Write-Host "     • $action" -ForegroundColor White
        }
    }
    
    Write-Host "`n⏱️ DURÉE TOTALE ESTIMÉE: $($plan.EstimatedDuration) minutes" -ForegroundColor Green
    
    return $plan
}

# Fonction pour suspendre Veeam
function Suspend-VeeamJobs {
    Write-Host "`n⏸️ SUSPENSION DES JOBS VEEAM" -ForegroundColor Yellow
    
    try {
        # Charger le module Veeam si disponible
        if (Get-Module -ListAvailable -Name Veeam.Backup.PowerShell) {
            Import-Module Veeam.Backup.PowerShell
            
            # Obtenir tous les jobs
            $jobs = Get-VBRJob
            
            foreach ($job in $jobs) {
                if ($job.IsScheduleEnabled) {
                    Write-Host "  Suspension: $($job.Name)" -ForegroundColor Gray
                    Disable-VBRJob -Job $job
                }
            }
            
            # Attendre fin des jobs en cours
            $runningJobs = Get-VBRJob | Where-Object {$_.GetLastState() -eq "Working"}
            if ($runningJobs) {
                Write-Host "  ⏳ Attente fin des jobs en cours..." -ForegroundColor Yellow
                while ($runningJobs) {
                    Start-Sleep -Seconds 30
                    $runningJobs = Get-VBRJob | Where-Object {$_.GetLastState() -eq "Working"}
                }
            }
            
            Write-Host "  ✅ Tous les jobs Veeam sont suspendus" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "  ⚠️ Module Veeam non disponible sur ce serveur" -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        Write-Host "  ❌ Erreur suspension Veeam: $_" -ForegroundColor Red
        return $false
    }
}

# Fonction pour réactiver Veeam
function Resume-VeeamJobs {
    Write-Host "`n▶️ RÉACTIVATION DES JOBS VEEAM" -ForegroundColor Yellow
    
    try {
        if (Get-Module -ListAvailable -Name Veeam.Backup.PowerShell) {
            Import-Module Veeam.Backup.PowerShell
            
            $jobs = Get-VBRJob
            foreach ($job in $jobs) {
                Write-Host "  Réactivation: $($job.Name)" -ForegroundColor Gray
                Enable-VBRJob -Job $job
            }
            
            Write-Host "  ✅ Tous les jobs Veeam sont réactivés" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "  ⚠️ Module Veeam non disponible" -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        Write-Host "  ❌ Erreur réactivation Veeam: $_" -ForegroundColor Red
        return $false
    }
}

# Fonction pour exécuter Windows Update
function Execute-WindowsUpdate {
    param([string]$ServerName)
    
    Write-Host "`n🔄 WINDOWS UPDATE sur $ServerName" -ForegroundColor Cyan
    
    if ($ServerName -eq $env:COMPUTERNAME) {
        # Exécution locale
        try {
            # Installer le module PSWindowsUpdate si nécessaire
            if (!(Get-Module -ListAvailable -Name PSWindowsUpdate)) {
                Write-Host "  Installation module PSWindowsUpdate..." -ForegroundColor Gray
                Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser
            }
            
            Import-Module PSWindowsUpdate
            
            # Rechercher les mises à jour
            Write-Host "  🔍 Recherche des mises à jour..." -ForegroundColor Yellow
            $updates = Get-WindowsUpdate
            
            if ($updates) {
                Write-Host "  📦 $($updates.Count) mises à jour trouvées" -ForegroundColor Cyan
                
                # Installer les mises à jour
                Write-Host "  ⬇️ Installation en cours..." -ForegroundColor Yellow
                Install-WindowsUpdate -AcceptAll -AutoReboot:$false
                
                # Vérifier si reboot nécessaire
                if (Get-WURebootStatus -Silent) {
                    Write-Host "  🔄 Redémarrage nécessaire" -ForegroundColor Yellow
                    return @{
                        Success = $true
                        RebootRequired = $true
                        UpdateCount = $updates.Count
                    }
                }
                else {
                    Write-Host "  ✅ Mises à jour installées" -ForegroundColor Green
                    return @{
                        Success = $true
                        RebootRequired = $false
                        UpdateCount = $updates.Count
                    }
                }
            }
            else {
                Write-Host "  ✅ Système déjà à jour" -ForegroundColor Green
                return @{
                    Success = $true
                    RebootRequired = $false
                    UpdateCount = 0
                }
            }
        }
        catch {
            Write-Host "  ❌ Erreur: $_" -ForegroundColor Red
            return @{
                Success = $false
                Error = $_.ToString()
            }
        }
    }
    else {
        # Exécution distante
        Write-Host "  🔗 Connexion distante à $ServerName..." -ForegroundColor Gray
        # TODO: Implémenter l'exécution distante via Invoke-Command
    }
}

# Programme principal
switch ($Action) {
    "Analyze" {
        $infrastructure = Get-Infrastructure
        $dependencies = Analyze-Dependencies -Infrastructure $infrastructure
        
        # Sauvegarder l'analyse dans SharePoint
        Write-Host "`n💾 Sauvegarde de l'analyse dans SharePoint..." -ForegroundColor Gray
    }
    
    "Plan" {
        $infrastructure = Get-Infrastructure
        $plan = Create-UpdatePlan -Infrastructure $infrastructure
        
        Write-Host "`n🎯 PROCHAINES ÉTAPES:" -ForegroundColor Green
        Write-Host "1. Vérifier le plan ci-dessus"
        Write-Host "2. Exécuter: .\WINDOWS-UPDATE-ORCHESTRATOR.ps1 -Action Execute"
        Write-Host "3. Surveiller: .\WINDOWS-UPDATE-ORCHESTRATOR.ps1 -Action Status"
    }
    
    "Execute" {
        Write-Host "⚠️ DÉBUT DE L'ORCHESTRATION" -ForegroundColor Yellow
        Write-Host "Cette opération va:"
        Write-Host "  • Suspendre les sauvegardes Veeam"
        Write-Host "  • Installer les Windows Updates"
        Write-Host "  • Redémarrer les serveurs si nécessaire"
        Write-Host "  • Réactiver les sauvegardes"
        
        $confirm = Read-Host "`nConfirmer l'exécution? (O/N)"
        if ($confirm -eq "O") {
            # TODO: Implémenter l'exécution complète
            Write-Host "🚀 Exécution en cours..." -ForegroundColor Green
        }
        else {
            Write-Host "❌ Exécution annulée" -ForegroundColor Red
        }
    }
    
    "Status" {
        Write-Host "📊 STATUT DE L'ORCHESTRATION" -ForegroundColor Cyan
        # TODO: Récupérer et afficher le statut depuis SharePoint
    }
    
    default {
        Write-Host "❌ Action non reconnue: $Action" -ForegroundColor Red
        Write-Host "Actions disponibles: Analyze | Plan | Execute | Status"
    }
}

Write-Host "`n✅ Orchestrator terminé" -ForegroundColor Green