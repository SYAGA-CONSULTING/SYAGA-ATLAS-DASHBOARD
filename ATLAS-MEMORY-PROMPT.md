# 🧠 ATLAS - PROMPT DE MÉMOIRE PERMANENTE
**À CHARGER À CHAQUE SESSION ATLAS POUR ÉVITER LES ERREURS RÉPÉTÉES**

## 🚫 ERREURS FATALES À NE JAMAIS REPRODUIRE

### ❌ ERREUR #1 : Remplacement de fichiers verrouillés
**PROBLÈME**: Windows verrouille les fichiers .ps1 en cours d'exécution
```powershell
# ❌ MAUVAIS - Échec garanti
Move-Item "$atlasPath\agent-new.ps1" "$atlasPath\agent.ps1" -Force
# Le fichier agent.ps1 est verrouillé car en cours d'exécution
```

**✅ SOLUTION VALIDÉE**: Architecture avec versions
```powershell
# Structure correcte
C:\SYAGA-ATLAS\
├── orchestrator.ps1     # JAMAIS modifié, lance les versions
├── versions\
│   ├── agent-v13.ps1
│   ├── agent-v17.ps1
├── current-version.txt  # Pointe vers la version active
```

### ❌ ERREUR #2 : Updater qui ne marque pas les commandes DONE
**PROBLÈME**: L'updater lit les commandes mais ne les marque jamais comme traitées
```powershell
# ❌ OUBLI SYSTÉMATIQUE
# Lit la commande UPDATE
# Télécharge nouvelle version
# OUBLIE de marquer Status = "DONE"
# → Retraite la même commande à l'infini
```

**✅ SOLUTION**: TOUJOURS marquer après traitement
```powershell
Mark-Command $cmdId "IN_PROGRESS"  # Début
# ... traitement ...
Mark-Command $cmdId "DONE"         # OBLIGATOIRE
```

### ❌ ERREUR #3 : Pas de validation après update
**PROBLÈME**: Après mise à jour, rien ne vérifie que ça fonctionne
```powershell
# ❌ MAUVAIS
Install-Update
# Fin, on espère que ça marche
```

**✅ SOLUTION**: Validation obligatoire
```powershell
if (Install-Update) {
    if (Test-UpdateSuccess) {
        Mark-Command $cmdId "DONE"
    } else {
        Rollback-ToPrevious
        Mark-Command $cmdId "FAILED"
    }
}
```

### ❌ ERREUR #4 : SharePoint field "Notes" n'existe pas
**PROBLÈME**: Erreur 400 "Bad Request" répétée 100+ fois
```powershell
# ❌ CHAMP INEXISTANT
$data = @{
    Notes = "quelque chose"  # CE CHAMP N'EXISTE PAS !
}
```

**✅ CHAMPS SHAREPOINT VALIDÉS**:
- Title, Hostname, IPAddress, State
- LastContact, AgentVersion
- CPUUsage, MemoryUsage, DiskSpaceGB
- Logs (pas Notes !)

### ❌ ERREUR #5 : Mutex mal géré
**PROBLÈME**: Mutex créé mais jamais libéré = blocage permanent
```powershell
# ❌ MAUVAIS
$mutex = New-Object System.Threading.Mutex($false, "Global\ATLAS")
# Script crash sans libérer le mutex
```

**✅ SOLUTION**: Try/Finally obligatoire
```powershell
try {
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    if (!$mutex.WaitOne(0)) { exit 0 }  # Déjà en cours
    # ... code ...
} finally {
    if ($mutex) {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}
```

## 📋 CHECKLIST AUTO-UPDATE FONCTIONNEL

### Phase 1 : DÉTECTION
- [ ] Updater lit SharePoint toutes les minutes
- [ ] Filtre commandes: Title="UPDATE", Target=$hostname, Status="PENDING"
- [ ] Marque immédiatement "IN_PROGRESS"

### Phase 2 : TÉLÉCHARGEMENT
- [ ] URLs correctes vers Azure Static Web Apps
- [ ] Validation taille fichier (> 1KB)
- [ ] Sauvegarde en -new.ps1, pas écrasement direct

### Phase 3 : INSTALLATION
- [ ] Stop tâche planifiée agent
- [ ] Renommer fichiers (pas Move sur fichier verrouillé)
- [ ] Start tâche planifiée agent
- [ ] Attendre 30 secondes

### Phase 4 : VALIDATION
- [ ] Vérifier agent répond
- [ ] Vérifier remontée SharePoint
- [ ] Si OK → marquer "DONE"
- [ ] Si KO → rollback + marquer "FAILED"

### Phase 5 : NETTOYAGE
- [ ] Nettoyer commandes > 24h
- [ ] Libérer mutex
- [ ] Logger résultat

## 🏛️ ARCHITECTURE VALIDÉE v10.3 (FONDATION)

### Fichiers sacrés - NE JAMAIS MODIFIER
```
public/agent-v10.3.ps1      # Agent stable de référence
public/updater-v10.0.ps1    # Updater fonctionnel
public/install-v10.0.ps1    # Installation 2 tâches
```

### Capacités prouvées
- ✅ Auto-update v10.1 → v10.2 → v10.3 sur 3 serveurs
- ✅ Architecture 2 tâches séparées (Agent + Updater)
- ✅ Nettoyage commandes SharePoint
- ✅ Logs avec métriques CPU/MEM/DISK

## 🎯 PATTERNS QUI MARCHENT

### Pattern 1 : Double validation
```powershell
# 1. Validation syntaxe PowerShell
$errors = @()
$null = [System.Management.Automation.PSParser]::Tokenize($scriptContent, [ref]$errors)
if ($errors.Count -gt 0) { return $false }

# 2. Validation exécution
$testResult = & powershell -Command "echo 'ok'" 2>&1
if ($testResult -ne "ok") { return $false }
```

### Pattern 2 : État persistant JSON
```powershell
$stateFile = "$atlasPath\updater-state.json"
$state = @{
    CurrentVersion = "17.0"
    LastUpdate = Get-Date
    Status = "SUCCESS"
}
$state | ConvertTo-Json | Set-Content $stateFile
```

### Pattern 3 : Rollback automatique
```powershell
$backupPath = "$atlasPath\backup"
# Avant update
Copy-Item "$atlasPath\agent.ps1" "$backupPath\agent-backup.ps1"
# Si échec
Copy-Item "$backupPath\agent-backup.ps1" "$atlasPath\agent.ps1"
```

## ⚠️ RÈGLES D'OR

1. **TESTER LOCALEMENT** avant de pusher
   ```powershell
   # Test updater détecte commandes
   & "C:\SYAGA-ATLAS\updater.ps1"
   # Vérifier logs
   ```

2. **JAMAIS modifier fichier en cours d'exécution**
   - Utiliser versions (agent-v17.ps1)
   - Ou orchestrateur qui lance bonnes versions

3. **TOUJOURS marquer commandes SharePoint**
   - PENDING → IN_PROGRESS → DONE/FAILED
   - Sinon boucle infinie

4. **VALIDATION après chaque changement**
   - L'agent remonte-t-il toujours ?
   - Les métriques sont-elles présentes ?
   - Pas d'erreur 400 ?

5. **LOGS détaillés pour debug**
   ```powershell
   Write-Log "État: $status, Version: $version, Erreur: $_" "DEBUG"
   ```

## 💡 BEST PRACTICES VALIDÉES

### GitHub Actions → Azure Static Web Apps
- Push déclenche déploiement automatique
- Attendre 2-3 minutes pour propagation CDN
- Vérifier https://white-river-053fc6703.2.azurestaticapps.net/public/

### SharePoint Command & Control
- Liste ATLAS-Commands pour ordres
- Liste ATLAS-Servers pour monitoring
- Pas de $orderby dans les requêtes (bug API)
- Limiter logs à 8000 caractères

### Tâches planifiées Windows
```powershell
# Durée max supportée
-RepetitionDuration (New-TimeSpan -Days 365)
# PAS TimeSpan::MaxValue (XML invalide)
```

## 🚨 SIGNAUX D'ALERTE

- **"toujours en v13.5"** = L'updater ne fonctionne pas
- **"plus aucun metric"** = Agent planté après update
- **"error 400"** = Champ SharePoint inexistant
- **"les données s'arrêtent après 1h"** = Mutex bloqué ou tâche stoppée

## 📝 COMMANDE DE RÉFÉRENCE

Pour forcer update depuis SharePoint :
```powershell
$updateCommand = @{
    "__metadata" = @{ type = "SP.Data.ATLASCommandsListItem" }
    Title = "UPDATE"
    Target = "SYAGA-HOST01"
    Version = "17.0"
    Status = "PENDING"
    CreatedBy = "MANUAL"
} | ConvertTo-Json
```

## 🔄 CYCLE DE VIE CORRECT

1. **Développer** nouvelle version (ex: v18.0)
2. **Tester** localement l'update v17→v18
3. **Valider** rollback v18→v17 fonctionne
4. **Commiter** et attendre GitHub Actions
5. **Créer** commande UPDATE dans SharePoint
6. **Vérifier** mise à jour dans dashboard
7. **Confirmer** métriques remontent toujours

---

**CE DOCUMENT CONTIENT 100+ HEURES D'APPRENTISSAGE**
**NE PAS REFAIRE LES MÊMES ERREURS**
**CONSULTER AVANT CHAQUE DÉVELOPPEMENT ATLAS**