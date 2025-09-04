# 🛡️ ATLAS v11 - ARCHITECTURE SÉCURISÉE MFA

**Date**: 4 septembre 2025  
**Mission**: Sécurisation MFA sans casser fondation v10.3  
**Concept**: "Temporary Elevated Token via MFA"

## 🏛️ RESPECT FONDATION v10.3

### RÈGLES ABSOLUES
- ✅ **v10.3 = SACRÉE** - Jamais toucher aux fichiers fondation
- ✅ **Cohabitation** - v11 doit fonctionner AVEC v10.3
- ✅ **Rollback** - Retour v10.3 si échec v11
- ✅ **Tests autonomes** - Validation avant déploiement

### FICHIERS FONDATION INTOUCHABLES
```
public/agent-v10.3.ps1       → NE PAS MODIFIER
public/updater-v10.0.ps1     → NE PAS MODIFIER  
public/install-v10.0.ps1     → NE PAS MODIFIER
public/install-latest.ps1    → NE PAS MODIFIER
```

## 🎯 WORKFLOW v11 EXACT

```
1. Dashboard → Génère token élevé temporaire (15 min)
   URL: https://install.syaga.fr/atlas?server=LAA-DC01&token=ELEV_ABC123_15MIN

2. Admin RDP → PowerShell admin
   .\install-v11.ps1 -Url "https://install.syaga.fr/atlas?server=LAA-DC01&token=ELEV_ABC123_15MIN"

3. Script PowerShell → QR Code console + boucle attente
   [QR CODE ASCII ART]
   "⏳ En attente validation MFA..."

4. Admin téléphone → Flash QR Code → Azure AD MFA → Validation

5. Token activé → Installation sécurisée 15 min
   - Certificats 4096 bits
   - Tâches planifiées
   - Verrouillage sécurisé
```

## 🛠️ COMPOSANTS CRITIQUES v11

### 1️⃣ DASHBOARD TOKEN GENERATOR (CRITIQUE)
**Fichier**: `dashboard/token-generator-v11.js`
```javascript
// Génère tokens élevés temporaires
function generateElevatedToken(serverName, adminEmail) {
    const token = `ELEV_${randomString(12)}_15MIN`;
    // Stockage SharePoint avec expiration
    // Retour URL sécurisée
}
```

### 2️⃣ POWERSHELL QR DISPLAY (CRITIQUE)  
**Fichier**: `public/install-v11-qr.ps1`
```powershell
# Affiche QR Code ASCII + boucle attente
function Show-QRCode($url) {
    # ASCII QR Code
    # Boucle attente validation MFA
}
```

### 3️⃣ MFA VALIDATION BACKEND (CRITIQUE)
**Fichier**: `api/mfa-validation-v11.js`  
```javascript
// Gère activation tokens après MFA
function validateMFAToken(qrToken) {
    // Vérification Azure AD MFA
    // Activation token élevé
}
```

## 📁 STRUCTURE FICHIERS v11

```
public/
├── agent-v10.3.ps1           ← FONDATION (NE PAS TOUCHER)
├── install-latest.ps1         ← FONDATION (NE PAS TOUCHER)
├── install-v11-secure.ps1     ← NOUVEAU - Installation MFA
├── install-v11-qr.ps1         ← NOUVEAU - QR Code display
└── agent-v11.0.ps1            ← NOUVEAU - Agent avec certificats

dashboard/
├── token-generator-v11.js     ← NOUVEAU - Génération tokens
└── mfa-validation-v11.js      ← NOUVEAU - Validation MFA

rollback/
└── rollback-v11-to-v10.3.ps1  ← NOUVEAU - Rollback sécurisé
```

## 🔒 SÉCURITÉ v11

### Token Management
- **Expiration**: 15 minutes automatique
- **Révocation**: Depuis Dashboard
- **Chiffrement**: Azure AD intégré
- **Usage unique**: Token consumé après installation

### MFA Flow
```
1. Génération token → SharePoint (Status: WAITING_MFA)
2. QR Code → Lien validation Azure AD
3. MFA réussi → Token Status: ELEVATED (15 min)
4. Installation → Token Status: CONSUMED
5. Expiration → Token Status: EXPIRED
```

### Certificats 4096 bits
- Génération via Azure Key Vault
- Stockage sécurisé local
- Rotation automatique

## 🔄 ROLLBACK STRATEGY

### Détection Échec
- Timeout installation > 20 minutes
- Erreurs critiques logs
- Perte de communication agent
- Commande manuelle ROLLBACK_v11_TO_v10.3

### Process Rollback
1. Arrêt tâches v11
2. Restauration agent-v10.3.ps1
3. Redémarrage tâches v10.3
4. Nettoyage certificats v11
5. Notification admin

## 🧪 TESTS AUTONOMES

### Scénarios Test
1. **Installation normale** - Token valide + MFA
2. **Token expiré** - Rejet installation
3. **MFA échoué** - Pas d'élévation
4. **Rollback forcé** - Retour v10.3
5. **Cohabitation** - v11 + v10.3 ensemble

### Scripts Test
```
test-v11-complete.py      → Test complet workflow
test-v11-rollback.py      → Test rollback v10.3
test-v11-cohabitation.py  → Test v11 + v10.3
```

---

**OBJECTIF**: Sécurisation MFA complète tout en préservant la stabilité v10.3