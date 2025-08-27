# Configuration Azure Function - 0€ et Automatique

## ✅ Ce qui est déjà fait automatiquement

1. **Code Azure Function** créé dans `/api/github-proxy/`
2. **GitHub Actions** configuré pour déploiement auto
3. **Dashboard** modifié pour utiliser le proxy sécurisé
4. **Tests automatiques** intégrés

## 🔧 Actions manuelles (une seule fois)

### 1. Créer l'Azure Function App

```bash
# Via Azure CLI (si installé)
az functionapp create \
  --name syaga-atlas-proxy \
  --resource-group rg-syaga \
  --consumption-plan-location westeurope \
  --runtime node \
  --runtime-version 18 \
  --functions-version 4 \
  --storage-account sasygaatlasdata

# OU via le portail Azure :
# 1. Aller sur portal.azure.com
# 2. Créer une ressource > Function App
# 3. Nom: syaga-atlas-proxy
# 4. Runtime: Node.js 18
# 5. Plan: Consumption (gratuit)
```

### 2. Configurer le secret GitHub Token

Dans Azure Function App > Configuration > Application Settings :
```
GITHUB_TOKEN = [VOTRE_TOKEN_GITHUB_ICI]
```

### 3. Récupérer le profil de publication

1. Azure Function > Get publish profile
2. Copier le contenu XML
3. GitHub repo > Settings > Secrets > Actions
4. Créer `AZURE_FUNCTIONAPP_PUBLISH_PROFILE` avec le XML

## 🚀 Déploiement

Une fois les secrets configurés, le push déclenchera automatiquement :

1. **Build** de la fonction
2. **Déploiement** sur Azure
3. **Test** de l'endpoint
4. **Notification** du résultat

## 📊 URLs finales

- **Dashboard** : https://syaga-consulting.github.io/SYAGA-ATLAS-DASHBOARD/
- **API Proxy** : https://syaga-atlas-proxy.azurewebsites.net/api/github-proxy

## 💰 Coût

**0€** - Tout dans les limites gratuites :
- GitHub Pages : Gratuit
- Azure Functions : 1M requêtes/mois gratuit
- GitHub Actions : 2000 minutes/mois gratuit

## 🔒 Sécurité

✅ Token GitHub côté serveur uniquement
✅ CORS configuré pour votre domaine
✅ Authentification Azure AD
✅ Validation des chemins API