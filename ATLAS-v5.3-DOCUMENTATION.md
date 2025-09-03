# ATLAS v5.3 - Documentation Complète
**Date:** 3 Septembre 2025  
**Version:** 5.3  
**État:** Production

## 📋 Vue d'ensemble

ATLAS v5.3 est un système de monitoring et contrôle d'infrastructure avec agent auto-update et sécurité maximale.

### Composants
- **Dashboard Web** : Interface de contrôle centralisée (Azure Static Web Apps)
- **Agents PowerShell** : Collecteurs de métriques avec auto-update
- **SharePoint** : Stockage des données et commandes
- **Générateur de liens** : Création de liens d'installation sécurisés

## 🔒 Sécurité

### Chiffrement des liens
- **Clé** : Nom du serveur cible
- **Format** : `BASE64(SERVERNAME|BASE64(params))`
- **Validation** : Le lien ne fonctionne QUE sur le serveur cible
- **Token** : 15 minutes de validité avec auto-suppression

### Protection contre
- ✅ Réutilisation sur un autre serveur
- ✅ Déchiffrement sans être sur le bon serveur
- ✅ Installation après expiration (15 min)
- ✅ Modification des paramètres

## 🚀 Installation

### Via Dashboard (Recommandé)
1. Accéder au dashboard : https://white-river-053fc6703.2.azurestaticapps.net
2. Onglet "Déploiement"
3. Remplir : Nom serveur, Type (VM/Host/Physical), Client
4. Copier le lien généré
5. Exécuter sur le serveur cible

### Exemple de lien généré
```powershell
$env:ATLAS_PARAMS='U1lBR0EtSE9TVDAxfGV5SnpaWEoyWlhJaU9pSlRXVUZIUVMxSVQxTlVNREVpTENKMGVYQmxJam9pU0c5emRDSXNJbU5zYVdWdWRDSTZJbE5aUVVkQkluMD0='; irm https://white-river-053fc6703.2.azurestaticapps.net/public/install-latest.ps1 | iex
```

## 📊 Métriques collectées

### Système
- CPU Usage (%)
- Memory Usage (%)
- Disk Space (GB)
- Pending Windows Updates
- Uptime (jours)

### Services
- SQL Server
- Veeam Backup
- Hyper-V
- IIS
- Exchange

### Exemple de statut
```
v5.3 | Up:15.2d | SQL | Veeam | IIS
```

## 🔄 Auto-Update

### Mécanisme
1. Agent vérifie SharePoint chaque minute
2. Cherche `UPDATE_COMMAND_[HOSTNAME]` ou `UPDATE_ALL`
3. Télécharge nouvelle version si trouvée
4. Sauvegarde ancienne version
5. Redémarre avec nouvelle version
6. Supprime commande UPDATE
7. Logue la mise à jour dans SharePoint

### Commandes Dashboard
- **Update individuel** : Bouton "Update" sur chaque serveur
- **Update global** : Bouton "📦 Mettre à jour Agents"

## 📁 Structure des fichiers

### Azure Static Web Apps
```
/
├── index.html                    # Dashboard principal
├── public/
│   ├── install-latest.ps1       # Point d'entrée installation (v5.3)
│   ├── agent-v5.1.ps1          # Agent v5.1 (peut upgrader vers v5.3)
│   ├── agent-v5.2.ps1          # Agent v5.2 (peut upgrader vers v5.3)
│   └── agent-v5.3.ps1          # Agent v5.3 actuel
```

### Sur les serveurs
```
C:\SYAGA-ATLAS\
├── agent.ps1                    # Agent en cours d'exécution
├── agent.backup.ps1            # Backup avant update
├── agent.log                   # Logs de l'agent
├── config.json                 # Configuration (serveur, type, client)
└── metrics.json                # Dernières métriques collectées
```

### Scripts temporaires Windows (C:\temp\)
```
C:\temp\
├── check-update-commands.ps1   # Vérifier commandes UPDATE dans SharePoint
├── create-update-command.ps1   # Créer commande UPDATE manuellement
├── force-update-to-5.2.ps1    # Forcer update vers v5.2
├── install-5.3-direct.ps1     # Installation directe v5.3
└── upgrade-to-v5.1.ps1        # Upgrade manuel vers v5.1
```

## 🔧 Troubleshooting

### L'agent ne se met pas à jour
1. Vérifier avec `.\check-update-commands.ps1`
2. Créer commande avec `.\create-update-command.ps1`
3. Forcer avec `.\force-update-to-5.2.ps1`

### Erreur "Lien invalide pour ce serveur"
- Le lien a été généré pour un autre serveur
- Régénérer depuis le dashboard avec le bon nom

### Token expiré
- Le lien a plus de 15 minutes
- Régénérer un nouveau lien depuis le dashboard

### Agent ne remonte pas les données
1. Vérifier tâche planifiée : `Get-ScheduledTask SYAGA-ATLAS-Agent`
2. Vérifier logs : `Get-Content C:\SYAGA-ATLAS\agent.log -Tail 50`
3. Tester manuellement : `powershell C:\SYAGA-ATLAS\agent.ps1`

## 📈 Évolutions v5.3

### Nouvelles fonctionnalités
- 🔐 Chiffrement avec nom du serveur comme clé
- 📊 Détection services étendus (IIS, Exchange)
- ⏰ Affichage uptime en jours
- 💾 Backup automatique avant update
- 🎯 Version cible dynamique dans commandes UPDATE

### Améliorations
- Messages colorés par version (v53 en magenta)
- Logs d'update détaillés dans SharePoint
- Meilleure gestion des erreurs
- Statut enrichi avec tous les services

## 🔐 Credentials SharePoint

```powershell
$tenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
$clientId = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
$clientSecret = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
$listId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"
```

## 📝 Workflow de mise à jour

### Pour déployer v5.4 (futur)
1. Créer `public/agent-v5.4.ps1`
2. Modifier `$LATEST_VERSION = "5.4"` dans `install-latest.ps1`
3. Commit et push
4. Les nouvelles installations auront v5.4
5. Les anciens agents peuvent upgrader via dashboard

## ⚡ Commandes utiles

### PowerShell (sur serveur)
```powershell
# Voir version agent
Get-Content C:\SYAGA-ATLAS\config.json | ConvertFrom-Json

# Voir dernières métriques
Get-Content C:\SYAGA-ATLAS\metrics.json | ConvertFrom-Json

# Voir logs
Get-Content C:\SYAGA-ATLAS\agent.log -Tail 20

# Forcer exécution
& powershell C:\SYAGA-ATLAS\agent.ps1

# Voir tâche planifiée
Get-ScheduledTask SYAGA-ATLAS-Agent | fl
```

### GitHub Actions
```bash
# Voir déploiements
gh run list --limit 5

# Voir workflow
gh workflow view "Azure Static Web Apps CI/CD"
```

## 🌐 URLs importantes

- **Dashboard** : https://white-river-053fc6703.2.azurestaticapps.net
- **GitHub** : https://github.com/SYAGA-CONSULTING/SYAGA-ATLAS-DASHBOARD
- **SharePoint** : https://syagacons.sharepoint.com (Liste: ATLAS-Servers)

## 📞 Support

Pour toute question ou problème :
1. Vérifier cette documentation
2. Consulter les logs de l'agent
3. Utiliser les scripts de diagnostic dans C:\temp\

---

*Documentation ATLAS v5.3 - Septembre 2025*