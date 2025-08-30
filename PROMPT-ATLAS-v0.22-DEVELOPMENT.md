# 🚀 PROMPT POUR SESSION CLAUDE - DÉVELOPPEMENT ATLAS v0.22

## INSTRUCTIONS POUR COPIER-COLLER DANS L'AUTRE SESSION CLAUDE

---

**DÉBUT DU PROMPT À COPIER:**

Je suis Sébastien. Tu travailles sur le dashboard ATLAS v0.22. 

Lis d'abord ces 3 documents CRITIQUES dans l'ordre :
1. `/home/sq/SYAGA-CONSULTING/SYAGA-ATLAS-DASHBOARD/ATLAS-v0.22-CONCEPT-SYNTHESE.md` - Vision complète
2. `/home/sq/SYAGA-CONSULTING/SYAGA-ATLAS-DASHBOARD/ORCHESTRATION-OPTIMISATION.md` - Architecture multi-client
3. `/home/sq/SYAGA-CONSULTING/SYAGA-ATLAS-DASHBOARD/ORCHESTRATION-SYNTHESE.md` - Workflow orchestration

## 🎯 CONTEXTE CRITIQUE

ATLAS v0.22 est un **ORCHESTRATEUR UNIQUE AU MONDE** - AUCUN concurrent n'existe (vérifié aujourd'hui).

### CE QU'ON FAIT QU'AUCUN AUTRE NE PEUT:
1. **Pseudo-CAU sans cluster** : Haute dispo via réplication (pas besoin de cluster Windows)
2. **Orchestration triptyque** : Windows Update + Hyper-V + Veeam INTÉGRÉS
3. **Migration multi-sites auto** : Déplace VMs entre datacenters avec changement IP
4. **Agent auto-adaptatif** : Plans IP de secours, conscience réseau
5. **MSP multi-tenant** : 1000 serveurs en 7.5h (au lieu de 31 jours)

## 📋 PRIORITÉS DÉVELOPPEMENT v0.22

### PHASE 1 - Dashboard (Interface Web)
1. **Vue grille multi-clients** : Afficher 100 clients × 10 serveurs en grille interactive
2. **Contrôles orchestration** :
   - Bouton "START ORCHESTRATION" global
   - Boutons "PAUSE/RESUME" par client
   - "EMERGENCY STOP" global
3. **Monitoring temps réel** :
   - Progress bars par client
   - État current : "CLIENT001: SERVER03 (45% - Installing updates)"
   - Temps restant estimé global et par client

### PHASE 2 - Agent PowerShell v0.22
1. **Logique orchestration** :
   ```powershell
   # Vérifier si c'est mon tour
   $myTurn = Check-OrchestrationQueue -Client $clientName -Server $hostname
   if ($myTurn) {
       Start-SafeWindowsUpdate
   }
   ```

2. **Pseudo-CAU Implementation** :
   ```powershell
   # Failover préventif avant update
   Move-VMToReplicaHost -VM $vmName -Temporary $true
   Install-WindowsUpdate
   Move-VMBack -VM $vmName
   ```

3. **Agent auto-adaptatif** :
   ```powershell
   # Si pas d'accès réseau, tester configs de secours
   if (-not (Test-Connection SharePoint)) {
       Try-AlternateIPConfigs
   }
   ```

### PHASE 3 - Listes SharePoint
Créer ces 3 nouvelles listes :

1. **ATLAS-Orchestration**
   - ClientName, ServerName, UpdateOrder, UpdateStatus, UpdateLocked

2. **ATLAS-ClientConfig**  
   - ClientName, MaxParallelServers (default: 1), MaintenanceWindow

3. **ATLAS-GlobalStatus**
   - RingName, Status, ServersTotal, ServersCompleted

## ⚠️ RÈGLES ABSOLUES

1. **JAMAIS GitHub pour runtime** - Toujours SharePoint pour données/config
2. **PowerShell natif** - Pas de Python, pas de modules tiers
3. **Un serveur à la fois PAR CLIENT** - Mais tous les clients en parallèle
4. **Snapshots AVANT update** - Rollback automatique si échec
5. **Agent v0.21 compatible** - Migration progressive

## 🔧 ARCHITECTURE TECHNIQUE

```
SharePoint Lists (CCC)
    ↓ HTTPS
Dashboard v0.22 (Azure Static Web Apps)
    ↓ Orchestration
Agents v0.22 (PowerShell natif)
    ↓ Cmdlets natives
├── Windows Update (Get-WindowsUpdate)
├── Hyper-V (Checkpoint-VM, Move-VM)
├── Veeam (Get-VBRJob, Disable-VBRJob)
└── Certificats WORKGROUP
```

## 💡 INNOVATIONS À IMPLÉMENTER

1. **Ring Deployment** : SYAGA → Pilotes → Standards → Critiques
2. **Verrouillage par client** : Un seul "InProgress" par client
3. **Détection pattern hostname** : CLIENT-SITE-ROLE-XX
4. **Cache local 5 min** : Réduire appels SharePoint
5. **Batch updates** : Grouper les écritures SharePoint

## 📊 MÉTRIQUES CIBLES

- 1000 serveurs en < 8 heures
- Downtime < 5 minutes par serveur  
- Rollback < 2 minutes si problème
- Dashboard responsive avec 1000 serveurs

## 🚫 NE PAS FAIRE

- ❌ Réinventer Ansible/Puppet - On fait DIFFÉRENT
- ❌ Complexifier inutilement - Rester simple et robuste
- ❌ Oublier la compatibilité v0.21 - Migration progressive
- ❌ Utiliser WinRM - Toujours PowerShell direct
- ❌ Créer de nouvelles dépendances - Natif only

## ✅ COMMENCER PAR

1. Lire les 3 documents de référence
2. Vérifier l'état actuel du dashboard (`index.html`)
3. Proposer un plan d'implémentation en phases
4. Commencer par la vue grille multi-clients

**Questions ?** Les documents contiennent TOUT le contexte nécessaire. ATLAS v0.22 va révolutionner la gestion d'infrastructure MSP Windows !

**FIN DU PROMPT À COPIER**

---

## 📝 NOTE POUR SÉBASTIEN

Ce prompt contient toutes les instructions nécessaires pour que l'autre session Claude comprenne :
- Le concept unique d'ATLAS (pas de concurrent)
- Les priorités de développement
- L'architecture technique
- Les innovations clés
- Les règles à respecter

Copiez tout entre "DÉBUT DU PROMPT" et "FIN DU PROMPT" dans l'autre session.