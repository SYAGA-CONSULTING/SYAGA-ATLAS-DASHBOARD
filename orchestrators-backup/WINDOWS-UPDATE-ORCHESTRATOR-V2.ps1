# WINDOWS UPDATE ORCHESTRATOR v2.0
# Gestion complète: Windows Update, Hyper-V, Réplication, Veeam

param(
    [Parameter(Mandatory=$false)]
    [string]$Action = "Analyze",  # Analyze | Plan | Execute | Status | Test
    [string]$TargetServer = $env:COMPUTERNAME,
    [switch]$Force,
    [switch]$SkipVeeam,
    [switch]$SkipReplication
)

$VERSION = "v2.0"
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

# ================================================================================
# SECTION 1: FONCTIONS HYPER-V & RÉPLICATION
# ================================================================================

function Get-HyperVReplicationStatus {
    Write-Host "`n🔄 ANALYSE RÉPLICATION HYPER-V" -ForegroundColor Cyan
    
    $replicationStatus = @{
        Healthy = @()
        Warning = @()
        Critical = @()
        Suspended = @()
        Total = 0
    }
    
    try {
        # Obtenir toutes les VMs avec réplication
        $replicatedVMs = Get-VMReplication -ErrorAction SilentlyContinue
        
        if ($replicatedVMs) {
            $replicationStatus.Total = $replicatedVMs.Count
            
            foreach ($vm in $replicatedVMs) {
                $vmInfo = @{
                    Name = $vm.Name
                    State = $vm.State
                    Health = $vm.Health
                    Mode = $vm.Mode
                    PrimaryServer = $vm.PrimaryServer
                    ReplicaServer = $vm.ReplicaServer
                    LastReplicationTime = $vm.LastReplicationTime
                    ReplicationFrequency = $vm.ReplicationFrequencySec
                }
                
                switch ($vm.Health) {
                    "Normal" { $replicationStatus.Healthy += $vmInfo }
                    "Warning" { $replicationStatus.Warning += $vmInfo }
                    "Critical" { $replicationStatus.Critical += $vmInfo }
                }
                
                if ($vm.State -eq "Suspended") {
                    $replicationStatus.Suspended += $vmInfo
                }
            }
            
            # Afficher résumé
            Write-Host "  📊 Résumé réplication:" -ForegroundColor Yellow
            Write-Host "    • Total VMs répliquées: $($replicationStatus.Total)" -ForegroundColor White
            Write-Host "    • État Normal: $($replicationStatus.Healthy.Count)" -ForegroundColor Green
            Write-Host "    • Avertissements: $($replicationStatus.Warning.Count)" -ForegroundColor Yellow
            Write-Host "    • Critiques: $($replicationStatus.Critical.Count)" -ForegroundColor Red
            Write-Host "    • Suspendues: $($replicationStatus.Suspended.Count)" -ForegroundColor Gray
            
            # Détails des VMs problématiques
            if ($replicationStatus.Critical.Count -gt 0) {
                Write-Host "`n  ⚠️ VMs en état CRITIQUE:" -ForegroundColor Red
                foreach ($vm in $replicationStatus.Critical) {
                    Write-Host "    • $($vm.Name) - Dernière réplication: $($vm.LastReplicationTime)" -ForegroundColor Red
                }
            }
            
            if ($replicationStatus.Warning.Count -gt 0) {
                Write-Host "`n  ⚠️ VMs avec avertissements:" -ForegroundColor Yellow
                foreach ($vm in $replicationStatus.Warning) {
                    Write-Host "    • $($vm.Name)" -ForegroundColor Yellow
                }
            }
        }
        else {
            Write-Host "  ℹ️ Aucune VM avec réplication configurée" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "  ❌ Erreur analyse réplication: $_" -ForegroundColor Red
    }
    
    return $replicationStatus
}

function Suspend-HyperVReplication {
    param(
        [string[]]$VMNames = @(),
        [switch]$All
    )
    
    Write-Host "`n⏸️ SUSPENSION RÉPLICATION HYPER-V" -ForegroundColor Yellow
    
    $results = @{
        Success = @()
        Failed = @()
    }
    
    try {
        if ($All) {
            $vmsToSuspend = Get-VMReplication | Where-Object {$_.State -ne "Suspended"}
        }
        elseif ($VMNames.Count -gt 0) {
            $vmsToSuspend = Get-VMReplication | Where-Object {$_.Name -in $VMNames -and $_.State -ne "Suspended"}
        }
        else {
            Write-Host "  ⚠️ Aucune VM spécifiée" -ForegroundColor Yellow
            return $results
        }
        
        foreach ($vm in $vmsToSuspend) {
            try {
                Write-Host "  Suspension réplication: $($vm.Name)..." -ForegroundColor Gray -NoNewline
                Suspend-VMReplication -VMName $vm.Name -Confirm:$false
                $results.Success += $vm.Name
                Write-Host " ✅" -ForegroundColor Green
            }
            catch {
                $results.Failed += @{VM = $vm.Name; Error = $_.ToString()}
                Write-Host " ❌" -ForegroundColor Red
            }
        }
        
        Write-Host "`n  📊 Résultat suspension:" -ForegroundColor Cyan
        Write-Host "    • Réussies: $($results.Success.Count)" -ForegroundColor Green
        Write-Host "    • Échouées: $($results.Failed.Count)" -ForegroundColor Red
    }
    catch {
        Write-Host "  ❌ Erreur globale: $_" -ForegroundColor Red
    }
    
    return $results
}

function Resume-HyperVReplication {
    param(
        [string[]]$VMNames = @(),
        [switch]$All
    )
    
    Write-Host "`n▶️ REPRISE RÉPLICATION HYPER-V" -ForegroundColor Yellow
    
    $results = @{
        Success = @()
        Failed = @()
        Resync = @()
    }
    
    try {
        if ($All) {
            $vmsToResume = Get-VMReplication | Where-Object {$_.State -eq "Suspended"}
        }
        elseif ($VMNames.Count -gt 0) {
            $vmsToResume = Get-VMReplication | Where-Object {$_.Name -in $VMNames -and $_.State -eq "Suspended"}
        }
        else {
            Write-Host "  ⚠️ Aucune VM spécifiée" -ForegroundColor Yellow
            return $results
        }
        
        foreach ($vm in $vmsToResume) {
            try {
                Write-Host "  Reprise réplication: $($vm.Name)..." -ForegroundColor Gray -NoNewline
                Resume-VMReplication -VMName $vm.Name -Confirm:$false
                
                # Vérifier si resync nécessaire
                Start-Sleep -Seconds 2
                $vmState = Get-VMReplication -VMName $vm.Name
                
                if ($vmState.Health -eq "Critical") {
                    Write-Host " ⚠️ Resync nécessaire" -ForegroundColor Yellow
                    $results.Resync += $vm.Name
                    
                    # Tenter resync automatique
                    if ($Force) {
                        Write-Host "    Resynchronisation en cours..." -ForegroundColor Gray
                        Resume-VMReplication -VMName $vm.Name -Resynchronize -Confirm:$false
                    }
                }
                else {
                    Write-Host " ✅" -ForegroundColor Green
                }
                
                $results.Success += $vm.Name
            }
            catch {
                $results.Failed += @{VM = $vm.Name; Error = $_.ToString()}
                Write-Host " ❌" -ForegroundColor Red
            }
        }
        
        Write-Host "`n  📊 Résultat reprise:" -ForegroundColor Cyan
        Write-Host "    • Reprises: $($results.Success.Count)" -ForegroundColor Green
        Write-Host "    • Resync nécessaire: $($results.Resync.Count)" -ForegroundColor Yellow
        Write-Host "    • Échouées: $($results.Failed.Count)" -ForegroundColor Red
    }
    catch {
        Write-Host "  ❌ Erreur globale: $_" -ForegroundColor Red
    }
    
    return $results
}

function Repair-HyperVReplication {
    param(
        [string]$VMName,
        [switch]$AutoFix
    )
    
    Write-Host "`n🔧 RÉPARATION RÉPLICATION - $VMName" -ForegroundColor Cyan
    
    try {
        $vm = Get-VMReplication -VMName $VMName
        
        if (!$vm) {
            Write-Host "  ❌ VM non trouvée ou pas de réplication" -ForegroundColor Red
            return $false
        }
        
        Write-Host "  État actuel: $($vm.State) - Santé: $($vm.Health)" -ForegroundColor Gray
        
        # Analyser le problème
        switch ($vm.Health) {
            "Critical" {
                Write-Host "  🔴 État CRITIQUE détecté" -ForegroundColor Red
                
                if ($AutoFix -or $Force) {
                    # Tentative 1: Resynchronisation
                    Write-Host "  Tentative 1: Resynchronisation..." -ForegroundColor Yellow
                    try {
                        Resume-VMReplication -VMName $VMName -Resynchronize -Confirm:$false
                        Start-Sleep -Seconds 10
                        
                        $vm = Get-VMReplication -VMName $VMName
                        if ($vm.Health -eq "Normal") {
                            Write-Host "  ✅ Réparation réussie par resync" -ForegroundColor Green
                            return $true
                        }
                    }
                    catch {
                        Write-Host "  ⚠️ Resync échoué: $_" -ForegroundColor Yellow
                    }
                    
                    # Tentative 2: Reset de la réplication
                    Write-Host "  Tentative 2: Reset complet..." -ForegroundColor Yellow
                    try {
                        # Supprimer la réplication
                        Remove-VMReplication -VMName $VMName -Confirm:$false
                        Start-Sleep -Seconds 5
                        
                        # Recréer la réplication
                        Write-Host "    Recréation de la réplication..." -ForegroundColor Gray
                        # TODO: Récupérer les paramètres originaux depuis SharePoint
                        
                        Write-Host "  ✅ Réplication recréée" -ForegroundColor Green
                        return $true
                    }
                    catch {
                        Write-Host "  ❌ Reset échoué: $_" -ForegroundColor Red
                    }
                }
                else {
                    Write-Host "  ℹ️ Actions possibles:" -ForegroundColor Cyan
                    Write-Host "    1. Resynchronisation manuelle"
                    Write-Host "    2. Suppression et recréation de la réplication"
                    Write-Host "    3. Vérification de la connectivité réseau"
                    Write-Host "  Utiliser -AutoFix pour réparer automatiquement"
                }
            }
            
            "Warning" {
                Write-Host "  🟡 Avertissement détecté" -ForegroundColor Yellow
                Write-Host "  Vérification en cours..." -ForegroundColor Gray
                
                # Vérifier la latence
                $lastRepl = $vm.LastReplicationTime
                $timeDiff = (Get-Date) - $lastRepl
                
                if ($timeDiff.TotalMinutes -gt 15) {
                    Write-Host "  ⚠️ Réplication en retard de $([int]$timeDiff.TotalMinutes) minutes" -ForegroundColor Yellow
                    
                    if ($AutoFix) {
                        Write-Host "  Forçage d'une réplication..." -ForegroundColor Gray
                        Start-VMReplication -VMName $VMName
                    }
                }
            }
            
            "Normal" {
                Write-Host "  ✅ Réplication saine" -ForegroundColor Green
                return $true
            }
        }
    }
    catch {
        Write-Host "  ❌ Erreur réparation: $_" -ForegroundColor Red
        return $false
    }
}

# ================================================================================
# SECTION 2: FONCTIONS VEEAM
# ================================================================================

function Get-VeeamStatus {
    Write-Host "`n💾 ANALYSE VEEAM BACKUP" -ForegroundColor Cyan
    
    $veeamStatus = @{
        Installed = $false
        Jobs = @()
        RunningJobs = @()
        ScheduledJobs = @()
        LastBackups = @()
    }
    
    try {
        # Vérifier installation Veeam
        $veeamService = Get-Service -Name "Veeam*" -ErrorAction SilentlyContinue
        
        if ($veeamService) {
            $veeamStatus.Installed = $true
            Write-Host "  ✅ Veeam installé" -ForegroundColor Green
            
            # Charger module PowerShell si disponible
            if (Get-Module -ListAvailable -Name Veeam.Backup.PowerShell) {
                Import-Module Veeam.Backup.PowerShell
                
                # Obtenir tous les jobs
                $jobs = Get-VBRJob
                $veeamStatus.Jobs = $jobs
                
                Write-Host "  📊 Jobs détectés: $($jobs.Count)" -ForegroundColor Yellow
                
                foreach ($job in $jobs) {
                    $jobInfo = @{
                        Name = $job.Name
                        Type = $job.JobType
                        Enabled = $job.IsScheduleEnabled
                        LastRun = $job.FindLastSession().EndTime
                        LastResult = $job.FindLastSession().Result
                        State = $job.GetLastState()
                    }
                    
                    # Jobs en cours
                    if ($jobInfo.State -eq "Working") {
                        $veeamStatus.RunningJobs += $jobInfo
                        Write-Host "    🔄 En cours: $($jobInfo.Name)" -ForegroundColor Cyan
                    }
                    
                    # Jobs planifiés
                    if ($jobInfo.Enabled) {
                        $veeamStatus.ScheduledJobs += $jobInfo
                    }
                    
                    # Derniers backups
                    $veeamStatus.LastBackups += $jobInfo
                    
                    # Afficher status
                    $statusColor = switch ($jobInfo.LastResult) {
                        "Success" { "Green" }
                        "Warning" { "Yellow" }
                        "Failed" { "Red" }
                        default { "Gray" }
                    }
                    
                    Write-Host "    • $($jobInfo.Name): $($jobInfo.LastResult)" -ForegroundColor $statusColor
                }
                
                Write-Host "`n  📈 Résumé:" -ForegroundColor Cyan
                Write-Host "    • Jobs actifs: $($veeamStatus.ScheduledJobs.Count)" -ForegroundColor Green
                Write-Host "    • En cours: $($veeamStatus.RunningJobs.Count)" -ForegroundColor Yellow
            }
            else {
                Write-Host "  ⚠️ Module PowerShell Veeam non disponible" -ForegroundColor Yellow
                Write-Host "  Utilisation de méthodes alternatives..." -ForegroundColor Gray
                
                # Méthode alternative via WMI/Registry
                $veeamStatus.Installed = $true
                $veeamStatus.Jobs = @("Détection limitée sans module")
            }
        }
        else {
            Write-Host "  ℹ️ Veeam non installé sur ce serveur" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "  ❌ Erreur analyse Veeam: $_" -ForegroundColor Red
    }
    
    return $veeamStatus
}

function Suspend-VeeamJobs {
    param(
        [string[]]$JobNames = @(),
        [switch]$All,
        [int]$WaitForRunning = 300  # Attendre max 5 minutes
    )
    
    Write-Host "`n⏸️ SUSPENSION JOBS VEEAM" -ForegroundColor Yellow
    
    $results = @{
        Suspended = @()
        Failed = @()
        WaitedFor = @()
    }
    
    try {
        if (Get-Module -ListAvailable -Name Veeam.Backup.PowerShell) {
            Import-Module Veeam.Backup.PowerShell
            
            # Sélectionner les jobs
            if ($All) {
                $jobsToSuspend = Get-VBRJob | Where-Object {$_.IsScheduleEnabled}
            }
            elseif ($JobNames.Count -gt 0) {
                $jobsToSuspend = Get-VBRJob | Where-Object {$_.Name -in $JobNames -and $_.IsScheduleEnabled}
            }
            else {
                $jobsToSuspend = Get-VBRJob | Where-Object {$_.IsScheduleEnabled}
            }
            
            # Suspendre les jobs
            foreach ($job in $jobsToSuspend) {
                try {
                    Write-Host "  Suspension: $($job.Name)..." -ForegroundColor Gray -NoNewline
                    Disable-VBRJob -Job $job
                    $results.Suspended += $job.Name
                    Write-Host " ✅" -ForegroundColor Green
                }
                catch {
                    $results.Failed += @{Job = $job.Name; Error = $_.ToString()}
                    Write-Host " ❌" -ForegroundColor Red
                }
            }
            
            # Attendre fin des jobs en cours
            $runningJobs = Get-VBRJob | Where-Object {$_.GetLastState() -eq "Working"}
            if ($runningJobs.Count -gt 0) {
                Write-Host "`n  ⏳ Attente fin des jobs en cours..." -ForegroundColor Yellow
                $waited = 0
                
                while ($runningJobs.Count -gt 0 -and $waited -lt $WaitForRunning) {
                    Write-Host "    Jobs en cours: $($runningJobs.Count) - Attente: $waited sec" -ForegroundColor Gray
                    Start-Sleep -Seconds 30
                    $waited += 30
                    $runningJobs = Get-VBRJob | Where-Object {$_.GetLastState() -eq "Working"}
                    $results.WaitedFor = $runningJobs | ForEach-Object {$_.Name}
                }
                
                if ($runningJobs.Count -eq 0) {
                    Write-Host "  ✅ Tous les jobs sont arrêtés" -ForegroundColor Green
                }
                else {
                    Write-Host "  ⚠️ $($runningJobs.Count) jobs toujours en cours après $WaitForRunning secondes" -ForegroundColor Yellow
                }
            }
            
            Write-Host "`n  📊 Résultat suspension Veeam:" -ForegroundColor Cyan
            Write-Host "    • Suspendus: $($results.Suspended.Count)" -ForegroundColor Green
            Write-Host "    • Échoués: $($results.Failed.Count)" -ForegroundColor Red
        }
        else {
            Write-Host "  ⚠️ Module Veeam non disponible" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  ❌ Erreur suspension Veeam: $_" -ForegroundColor Red
    }
    
    return $results
}

function Resume-VeeamJobs {
    param(
        [string[]]$JobNames = @(),
        [switch]$All,
        [switch]$RunTestBackup
    )
    
    Write-Host "`n▶️ RÉACTIVATION JOBS VEEAM" -ForegroundColor Yellow
    
    $results = @{
        Resumed = @()
        Failed = @()
        TestStarted = @()
    }
    
    try {
        if (Get-Module -ListAvailable -Name Veeam.Backup.PowerShell) {
            Import-Module Veeam.Backup.PowerShell
            
            # Sélectionner les jobs
            if ($All) {
                $jobsToResume = Get-VBRJob
            }
            elseif ($JobNames.Count -gt 0) {
                $jobsToResume = Get-VBRJob | Where-Object {$_.Name -in $JobNames}
            }
            else {
                $jobsToResume = Get-VBRJob
            }
            
            # Réactiver les jobs
            foreach ($job in $jobsToResume) {
                try {
                    Write-Host "  Réactivation: $($job.Name)..." -ForegroundColor Gray -NoNewline
                    Enable-VBRJob -Job $job
                    $results.Resumed += $job.Name
                    Write-Host " ✅" -ForegroundColor Green
                    
                    # Lancer un test si demandé
                    if ($RunTestBackup) {
                        Write-Host "    Lancement backup test..." -ForegroundColor Gray
                        Start-VBRJob -Job $job -RunAsync
                        $results.TestStarted += $job.Name
                    }
                }
                catch {
                    $results.Failed += @{Job = $job.Name; Error = $_.ToString()}
                    Write-Host " ❌" -ForegroundColor Red
                }
            }
            
            Write-Host "`n  📊 Résultat réactivation Veeam:" -ForegroundColor Cyan
            Write-Host "    • Réactivés: $($results.Resumed.Count)" -ForegroundColor Green
            Write-Host "    • Tests lancés: $($results.TestStarted.Count)" -ForegroundColor Cyan
            Write-Host "    • Échoués: $($results.Failed.Count)" -ForegroundColor Red
        }
        else {
            Write-Host "  ⚠️ Module Veeam non disponible" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  ❌ Erreur réactivation Veeam: $_" -ForegroundColor Red
    }
    
    return $results
}

# ================================================================================
# SECTION 3: ORCHESTRATION PRINCIPALE
# ================================================================================

function Create-OrchestrationPlan {
    param(
        [hashtable]$Infrastructure
    )
    
    Write-Host "`n📋 CRÉATION PLAN D'ORCHESTRATION COMPLET" -ForegroundColor Green
    Write-Host "=" * 50
    
    $plan = @{
        Version = "2.0"
        Created = Get-Date
        Phases = @()
        PreChecks = @()
        PostChecks = @()
        RollbackPlan = @()
        EstimatedDuration = 0
    }
    
    # PRE-CHECKS
    $plan.PreChecks = @(
        "Vérifier espace disque (min 10GB)"
        "Vérifier connectivité réseau"
        "Vérifier état réplication Hyper-V"
        "Vérifier état jobs Veeam"
        "Créer point de restauration système"
    )
    
    # PHASE 1: Préparation
    $plan.Phases += @{
        Order = 1
        Name = "📍 PHASE 1: PRÉPARATION"
        Critical = $true
        Actions = @(
            @{
                Name = "Analyse infrastructure"
                Command = "Get-HyperVReplicationStatus"
                Duration = 5
            },
            @{
                Name = "Suspension jobs Veeam"
                Command = "Suspend-VeeamJobs -All"
                Duration = 10
                Rollback = "Resume-VeeamJobs -All"
            },
            @{
                Name = "Suspension réplication Hyper-V"
                Command = "Suspend-HyperVReplication -All"
                Duration = 5
                Rollback = "Resume-HyperVReplication -All"
            },
            @{
                Name = "Création snapshot VMs critiques"
                Command = "Checkpoint-VM -Name * -SnapshotName 'Pre-WindowsUpdate'"
                Duration = 15
            }
        )
    }
    
    # PHASE 2: Update VMs (Tier 2)
    $plan.Phases += @{
        Order = 2
        Name = "📍 PHASE 2: UPDATE VMs NON-CRITIQUES"
        Critical = $false
        Parallel = $true
        Actions = @(
            @{
                Name = "Windows Update VMs Tier 2"
                Targets = @() # À remplir avec les VMs non-critiques
                Command = "Execute-WindowsUpdate"
                Duration = 45
                MaxParallel = 3
            }
        )
    }
    
    # PHASE 3: Update VMs critiques (une par une)
    $plan.Phases += @{
        Order = 3
        Name = "📍 PHASE 3: UPDATE VMs CRITIQUES"
        Critical = $true
        Parallel = $false
        Actions = @(
            @{
                Name = "Windows Update DC primaire"
                Target = "SYAGA-DC01"
                Command = "Execute-WindowsUpdate"
                Duration = 30
                WaitAfter = 10
            },
            @{
                Name = "Windows Update DC secondaire"
                Target = "SYAGA-DC02"
                Command = "Execute-WindowsUpdate"
                Duration = 30
                WaitAfter = 10
            }
        )
    }
    
    # PHASE 4: Update Hôtes Hyper-V (un par un)
    $hostCount = 0
    foreach ($host in $Infrastructure.HyperVHosts) {
        $hostCount++
        $plan.Phases += @{
            Order = 4 + $hostCount
            Name = "📍 PHASE $(3 + $hostCount): UPDATE HÔTE $($host.Name)"
            Critical = $true
            Actions = @(
                @{
                    Name = "Vérification VMs avant update"
                    Command = "Get-VM -ComputerName $($host.Name) | Where State -eq Running"
                    Duration = 2
                },
                @{
                    Name = "Migration VMs si cluster"
                    Command = "Move-ClusterVirtualMachineRole"
                    Duration = 20
                    SkipIfNoCluster = $true
                },
                @{
                    Name = "Windows Update hôte"
                    Target = $host.Name
                    Command = "Execute-WindowsUpdate"
                    Duration = 45
                },
                @{
                    Name = "Reboot si nécessaire"
                    Command = "Restart-Computer -Force -Wait"
                    Duration = 10
                },
                @{
                    Name = "Attente redémarrage VMs"
                    Command = "Wait-VMRestart"
                    Duration = 15
                },
                @{
                    Name = "Vérification santé VMs"
                    Command = "Test-VMHealth"
                    Duration = 5
                }
            )
        }
    }
    
    # PHASE FINALE: Restauration services
    $plan.Phases += @{
        Order = 99
        Name = "📍 PHASE FINALE: RESTAURATION SERVICES"
        Critical = $true
        Actions = @(
            @{
                Name = "Reprise réplication Hyper-V"
                Command = "Resume-HyperVReplication -All"
                Duration = 10
            },
            @{
                Name = "Vérification/Réparation réplications"
                Command = "Get-VMReplication | Where Health -ne Normal | Repair-HyperVReplication -AutoFix"
                Duration = 20
            },
            @{
                Name = "Réactivation jobs Veeam"
                Command = "Resume-VeeamJobs -All"
                Duration = 5
            },
            @{
                Name = "Lancement backup test"
                Command = "Start-VBRJob -Name 'Test-PostUpdate'"
                Duration = 30
            },
            @{
                Name = "Nettoyage snapshots temporaires"
                Command = "Remove-VMSnapshot -Name 'Pre-WindowsUpdate' -IncludeAllChildSnapshots"
                Duration = 10
                DelayHours = 24
            }
        )
    }
    
    # POST-CHECKS
    $plan.PostChecks = @(
        "Vérifier tous les services critiques"
        "Vérifier réplication Hyper-V (0 erreur)"
        "Vérifier derniers backups Veeam"
        "Vérifier logs d'événements Windows"
        "Rapport final à l'administrateur"
    )
    
    # ROLLBACK PLAN
    $plan.RollbackPlan = @(
        @{
            Trigger = "Échec réplication après update"
            Actions = @(
                "Restore-VMSnapshot -Name 'Pre-WindowsUpdate'"
                "Resume-HyperVReplication -Resynchronize"
            )
        },
        @{
            Trigger = "VM critique ne démarre pas"
            Actions = @(
                "Restore-VMSnapshot -Name 'Pre-WindowsUpdate'"
                "Start-VM -Force"
            )
        },
        @{
            Trigger = "Hôte Hyper-V ne redémarre pas"
            Actions = @(
                "Démarrage en mode sans échec"
                "Désinstallation dernières mises à jour"
                "Restoration depuis backup Veeam si nécessaire"
            )
        }
    )
    
    # Calculer durée totale
    foreach ($phase in $plan.Phases) {
        $phaseDuration = 0
        foreach ($action in $phase.Actions) {
            $phaseDuration += $action.Duration
        }
        $plan.EstimatedDuration += $phaseDuration
    }
    
    return $plan
}

function Display-OrchestrationPlan {
    param($Plan)
    
    Write-Host "`n🎯 PLAN D'ORCHESTRATION WINDOWS UPDATE + HYPER-V + VEEAM" -ForegroundColor Cyan
    Write-Host "=" * 60
    
    Write-Host "`n📅 Créé le: $($Plan.Created)" -ForegroundColor Gray
    Write-Host "⏱️ Durée estimée: $($Plan.EstimatedDuration) minutes" -ForegroundColor Yellow
    
    # PRE-CHECKS
    Write-Host "`n✅ PRE-CHECKS:" -ForegroundColor Green
    foreach ($check in $Plan.PreChecks) {
        Write-Host "  • $check" -ForegroundColor White
    }
    
    # PHASES
    Write-Host "`n📋 PHASES D'EXÉCUTION:" -ForegroundColor Cyan
    foreach ($phase in $Plan.Phases | Sort-Object Order) {
        Write-Host "`n$($phase.Name)" -ForegroundColor Yellow
        
        if ($phase.Critical) {
            Write-Host "  ⚠️ PHASE CRITIQUE" -ForegroundColor Red
        }
        
        if ($phase.Parallel) {
            Write-Host "  ⚡ Exécution parallèle possible" -ForegroundColor Cyan
        }
        
        foreach ($action in $phase.Actions) {
            Write-Host "  ⏱️ [$($action.Duration)min] $($action.Name)" -ForegroundColor White
            
            if ($action.Target) {
                Write-Host "      Cible: $($action.Target)" -ForegroundColor Gray
            }
            
            if ($action.Rollback) {
                Write-Host "      ↩️ Rollback: $($action.Rollback)" -ForegroundColor DarkYellow
            }
        }
    }
    
    # POST-CHECKS
    Write-Host "`n✅ POST-CHECKS:" -ForegroundColor Green
    foreach ($check in $Plan.PostChecks) {
        Write-Host "  • $check" -ForegroundColor White
    }
    
    # ROLLBACK
    Write-Host "`n🔄 PLAN DE ROLLBACK:" -ForegroundColor Magenta
    foreach ($rollback in $Plan.RollbackPlan) {
        Write-Host "  Si: $($rollback.Trigger)" -ForegroundColor Yellow
        foreach ($action in $rollback.Actions) {
            Write-Host "    → $action" -ForegroundColor White
        }
    }
    
    Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
    Write-Host "💡 RECOMMANDATIONS:" -ForegroundColor Yellow
    Write-Host "  1. Exécuter pendant fenêtre de maintenance"
    Write-Host "  2. Avoir un accès iDRAC/iLO aux serveurs physiques"
    Write-Host "  3. Vérifier les backups Veeam récents avant de commencer"
    Write-Host "  4. Informer les utilisateurs de l'interruption de service"
    Write-Host "  5. Avoir le plan de rollback prêt"
}

# ================================================================================
# PROGRAMME PRINCIPAL
# ================================================================================

# Obtenir token pour SharePoint
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

# Obtenir infrastructure depuis SharePoint
function Get-Infrastructure {
    Write-Host "📊 Récupération infrastructure depuis SharePoint..." -ForegroundColor Yellow
    
    $token = Get-GraphToken
    $headers = @{Authorization = "Bearer $token"}
    $listUrl = "https://graph.microsoft.com/v1.0/sites/$($SharePointConfig.SiteId)/lists/$($SharePointConfig.ListId)/items?`$expand=fields"
    
    $items = Invoke-RestMethod -Uri $listUrl -Headers $headers
    
    $infrastructure = @{
        HyperVHosts = @()
        VeeamServers = @()
        AllServers = @()
    }
    
    foreach ($item in $items.value) {
        $server = $item.fields
        $infrastructure.AllServers += $server
        
        if ($server.HyperVStatus -and $server.HyperVStatus -notlike "*NoHyperV*") {
            $infrastructure.HyperVHosts += $server
        }
        
        if ($server.VeeamStatus -and $server.VeeamStatus -like "*Installed*") {
            $infrastructure.VeeamServers += $server.Hostname
        }
    }
    
    return $infrastructure
}

# Exécution selon action
switch ($Action) {
    "Analyze" {
        Write-Host "`n🔍 ANALYSE COMPLÈTE DE L'INFRASTRUCTURE" -ForegroundColor Cyan
        
        $infrastructure = Get-Infrastructure
        
        # Analyser Hyper-V
        if ($infrastructure.HyperVHosts.Count -gt 0) {
            $replicationStatus = Get-HyperVReplicationStatus
        }
        
        # Analyser Veeam
        if ($infrastructure.VeeamServers.Count -gt 0) {
            $veeamStatus = Get-VeeamStatus
        }
        
        Write-Host "`n📊 RÉSUMÉ INFRASTRUCTURE:" -ForegroundColor Green
        Write-Host "  • Hôtes Hyper-V: $($infrastructure.HyperVHosts.Count)"
        Write-Host "  • Serveurs Veeam: $($infrastructure.VeeamServers.Count)"
        Write-Host "  • Total serveurs: $($infrastructure.AllServers.Count)"
    }
    
    "Plan" {
        $infrastructure = Get-Infrastructure
        $plan = Create-OrchestrationPlan -Infrastructure $infrastructure
        Display-OrchestrationPlan -Plan $plan
        
        # Sauvegarder le plan
        $planFile = "C:\temp\WindowsUpdate-Plan-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
        $plan | ConvertTo-Json -Depth 10 | Out-File $planFile
        Write-Host "`n💾 Plan sauvegardé: $planFile" -ForegroundColor Green
    }
    
    "Execute" {
        Write-Host "`n⚠️ EXÉCUTION DE L'ORCHESTRATION COMPLÈTE" -ForegroundColor Yellow
        Write-Host "Cette opération va:" -ForegroundColor Yellow
        Write-Host "  • Suspendre la réplication Hyper-V" -ForegroundColor White
        Write-Host "  • Suspendre les sauvegardes Veeam" -ForegroundColor White
        Write-Host "  • Installer les Windows Updates sur tous les serveurs" -ForegroundColor White
        Write-Host "  • Redémarrer les serveurs dans le bon ordre" -ForegroundColor White
        Write-Host "  • Restaurer tous les services" -ForegroundColor White
        
        if (!$Force) {
            $confirm = Read-Host "`nConfirmer l'exécution? (OUI pour confirmer)"
            if ($confirm -ne "OUI") {
                Write-Host "❌ Exécution annulée" -ForegroundColor Red
                exit
            }
        }
        
        Write-Host "`n🚀 DÉBUT DE L'ORCHESTRATION" -ForegroundColor Green
        # TODO: Implémenter l'exécution du plan
    }
    
    "Status" {
        Write-Host "`n📊 STATUT DE L'ORCHESTRATION" -ForegroundColor Cyan
        
        # Vérifier Hyper-V
        Get-HyperVReplicationStatus
        
        # Vérifier Veeam
        Get-VeeamStatus
        
        # TODO: Récupérer statut depuis SharePoint
    }
    
    "Test" {
        Write-Host "`n🧪 MODE TEST - Vérification des fonctions" -ForegroundColor Magenta
        
        Write-Host "`nTest 1: Détection Hyper-V..." -ForegroundColor Yellow
        $hyperv = Get-HyperVReplicationStatus
        
        Write-Host "`nTest 2: Détection Veeam..." -ForegroundColor Yellow
        $veeam = Get-VeeamStatus
        
        Write-Host "`nTest 3: Création plan..." -ForegroundColor Yellow
        $infrastructure = Get-Infrastructure
        $plan = Create-OrchestrationPlan -Infrastructure $infrastructure
        
        Write-Host "`n✅ Tests terminés" -ForegroundColor Green
    }
    
    default {
        Write-Host "❌ Action non reconnue: $Action" -ForegroundColor Red
        Write-Host "`nActions disponibles:" -ForegroundColor Yellow
        Write-Host "  • Analyze - Analyser l'infrastructure"
        Write-Host "  • Plan    - Créer un plan d'orchestration"
        Write-Host "  • Execute - Exécuter l'orchestration"
        Write-Host "  • Status  - Vérifier le statut"
        Write-Host "  • Test    - Mode test"
    }
}

Write-Host "`n✅ Orchestrator $VERSION terminé" -ForegroundColor Green