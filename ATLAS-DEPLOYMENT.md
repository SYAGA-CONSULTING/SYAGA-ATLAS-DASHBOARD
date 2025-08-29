# ATLAS DEPLOYMENT - Guide Complet

## 🚀 VERSION ACTUELLE: v0.21

### Architecture
```
Dashboard (Azure Static Web Apps) → SharePoint Lists → Agents (Windows)
                                         ↑
                                   UPDATE-ATLAS.ps1
                                         ↓
                            SharePoint Documents/ATLAS/atlas-agent-current.ps1
```

## 📦 Déploiement Agent

### Sur un nouveau serveur:
```powershell
# 1. Télécharger UPDATE-ATLAS.ps1 (une seule fois)
iwr https://1drv.ms/u/s!Av5nCvM7YaFfgb1234567890 -UseBasicParsing -OutFile C:\Windows\UPDATE-ATLAS.ps1

# 2. Exécuter UPDATE-ATLAS pour télécharger l'agent
C:\Windows\UPDATE-ATLAS.ps1

# 3. Installer l'agent
C:\temp\agent-latest.ps1 -Install
```

### Mise à jour agent existant:
```powershell
# UPDATE-ATLAS télécharge automatiquement la dernière version
C:\Windows\UPDATE-ATLAS.ps1
```

## 🔧 Configuration

### Credentials (dans l'agent)
```powershell
client_id = 'f66a8c6c-1037-41b8-be3c-4f6e67c1f49e'
client_secret = '[REDACTED - voir ~/.azure_config]'
tenant_id = '6027d81c-ad9b-48f5-9da6-96f1bad11429'
```

### SharePoint Lists
- **URL:** `https://syagacons.sharepoint.com/Lists/ATLASServers`
- **List ID:** `94dc7ad4-740f-4c1f-b99c-107e01c8f70b`
- **Site ID:** `syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8`

### Champs SharePoint
- `Hostname` - Nom du serveur
- `AgentVersion` - Version de l'agent (v0.21)
- `LastContact` - Dernier contact UTC
- `State` - État (OK/Warning/Error)
- `CPUUsage` - Utilisation CPU %
- `MemoryUsage` - Utilisation RAM %
- `DiskSpaceGB` - Espace disque libre
- `IPAddress` - Adresse IP
- `HyperVStatus` - État Hyper-V
- `VeeamStatus` - État Veeam

## 📊 Dashboard

### URL Production
https://syaga-atlas.azurestaticapps.net

### Fonctionnalités
- Vue temps réel des serveurs
- Métriques détaillées
- Auto-update des agents
- Déploiement OneDrive

## 🔄 Auto-Update Workflow

1. **Upload nouvelle version:**
```python
python3 upload-agent-vXXX.py
```

2. **Agent vérifie toutes les 2 minutes:**
- Télécharge depuis SharePoint Documents/ATLAS/atlas-agent-current.ps1
- Compare version
- Se met à jour si nécessaire

## 📝 Historique Versions

### v0.21 (Actuelle)
- Ultra simple et robuste
- Gestion compteurs FR/EN
- UTF-8 partout
- Installation avec -Install

### v0.20
- Installation automatique
- Tâche planifiée SYAGA-ATLAS-Agent
- Dossier C:\SYAGA-ATLAS

### v0.19
- Version unifiée HOST01/VEEAM01
- Auth permanente
- UTC timestamps

### v0.18
- Détection Veeam Backup
- Jobs backup status
- Taille backups

### v0.17
- Hyper-V détaillé
- État des VMs
- Réplication status

### v0.16
- Vraies métriques CPU/RAM/Disk
- Fin des valeurs hardcodées

### v0.15
- Première version auto-update
- Base SharePoint

## ⚠️ RÈGLES IMPORTANTES

### JAMAIS MODIFIER UPDATE-ATLAS.ps1
- Ce fichier reste identique pour l'éternité
- Cherche TOUJOURS dans SharePoint Documents/ATLAS/atlas-agent-current.ps1
- S'adapte à ce qu'UPDATE-ATLAS attend

### UTF-8 OBLIGATOIRE
- Content-Type: application/json; charset=utf-8
- Encoding UTF8 pour tous les fichiers

### Gestion Erreurs
- Compteurs performance FR: "\Processeur(_Total)\% temps processeur"
- Compteurs performance EN: "\Processor(_Total)\% Processor Time"
- Toujours try/catch pour les métriques

## 🚨 Troubleshooting

### Agent ne remonte pas les données
1. Vérifier avec `C:\temp\test-simple.ps1`
2. Vérifier tâche planifiée: `Get-ScheduledTask | Where TaskName -like "*ATLAS*"`
3. Vérifier logs: `Get-EventLog -LogName Application -Source "SYAGA-ATLAS" -Newest 10`

### Erreur 400 SharePoint
- Ne pas utiliser $filter sur champs non-indexés
- Récupérer tous les items puis filtrer localement

### Version ne se met pas à jour
1. Forcer update: `C:\Windows\UPDATE-ATLAS.ps1`
2. Vérifier contenu: `Get-Content C:\SYAGA-ATLAS\agent.ps1 | Select-String VERSION`

## 📌 Serveurs Actuels
- **SYAGA-HOST01** - Serveur principal
- **SYAGA-VEEAM01** - Serveur backup