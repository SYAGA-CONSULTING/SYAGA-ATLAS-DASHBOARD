# 🔐 Configuration Azure AD pour ATLAS Dashboard

## ⚠️ URGENT - URLs de redirection à ajouter

Pour que l'authentification fonctionne, vous devez ajouter ces URLs dans Azure AD :

### 1. Ouvrir Azure Portal
1. Aller sur https://portal.azure.com
2. Azure Active Directory → App registrations
3. Chercher l'application : `f66a8c6c-1037-41b8-be3c-4f6e67c1f49e`
4. Cliquer sur "Authentication" dans le menu de gauche

### 2. URLs de redirection à ajouter (Type: SPA)

**Production (Azure Static Web Apps) :**
```
https://white-river-053fc6703.2.azurestaticapps.net/
https://white-river-053fc6703.2.azurestaticapps.net/index.html
https://white-river-053fc6703.2.azurestaticapps.net/dashboard-v0.23-connected.html
https://white-river-053fc6703.2.azurestaticapps.net/dashboard-v0.23-honeycomb-live.html
```

**Développement local (optionnel) :**
```
http://localhost:3000/
http://localhost:5000/
http://127.0.0.1:5500/
```

### 3. Configuration recommandée

Dans la section "Authentication" :

✅ **Redirect URIs** : Ajouter toutes les URLs ci-dessus comme type "SPA"
✅ **Implicit grant** : Cocher "Access tokens" et "ID tokens"
✅ **Supported account types** : "Accounts in this organizational directory only"
✅ **Allow public client flows** : "No"

### 4. Permissions API

Dans "API permissions", vérifier que ces permissions sont accordées :
- Microsoft Graph:
  - `User.Read` (Delegated)
  - `Sites.Read.All` (Delegated)
  - `Sites.ReadWrite.All` (Delegated) - si modification nécessaire

### 5. Solution alternative rapide

Si vous ne pouvez pas modifier l'App Registration, utilisez la version avec l'ancien redirectUri :

```javascript
// Dans dashboard-v0.23-connected.html, remplacer :
redirectUri: window.location.origin + '/'

// Par :
redirectUri: 'http://localhost:3000/'  // Si c'est configuré
```

## 📝 Notes importantes

- **Client ID actuel** : `f66a8c6c-1037-41b8-be3c-4f6e67c1f49e`
- **Tenant ID** : `6027d81c-ad9b-48f5-9da6-96f1bad11429`
- **SharePoint Site** : `https://syagaconsulting.sharepoint.com/sites/SERVEUR-UPDATE`

## 🚨 Erreur actuelle

```
AADSTS50011: The redirect URI 'https://white-river-053fc6703.2.azurestaticapps.net/dashboard-v0.23-connected.html' 
specified in the request does not match the redirect URIs configured for the application
```

Cette erreur disparaîtra une fois les URLs ajoutées dans Azure AD.

## 🔧 Test après configuration

1. Vider le cache du navigateur (Ctrl+Shift+Delete)
2. Ouvrir : https://white-river-053fc6703.2.azurestaticapps.net/dashboard-v0.23-connected.html
3. Se connecter avec votre compte Azure AD
4. Accepter les permissions si demandé

---

**Contact support :** sebastien.questier@syaga.fr