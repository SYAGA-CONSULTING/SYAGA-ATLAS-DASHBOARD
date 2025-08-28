# 🎯 CONSIGNE PERMANENTE - AUTOTEST OBLIGATOIRE

## 📋 RÈGLES STRICTES À RESPECTER TOUJOURS

### 1. 🔍 AUTOTEST CHROME RÉEL (JAMAIS HEADLESS)
- **OBLIGATOIRE** : Tester TOUJOURS avec Chrome visible
- **SCREENSHOTS** : Prendre des captures d'écran systématiques
- **VÉRIFICATION VISUELLE** : Voir exactement ce que l'utilisateur voit

### 2. 🌐 ENCODAGE UTF-8
- **TOUJOURS** vérifier l'affichage des accents français
- **DÉTECTER** automatiquement les problèmes d'encodage
- **CORRIGER** immédiatement les `charset=UTF-8` manquants

### 3. ⏰ GESTION HORAIRE GMT+2
- **CONVERTIR** automatiquement GMT vers GMT+2 
- **AFFICHER** clairement les fuseaux horaires
- **TESTER** les timestamps en conditions réelles

### 4. 📸 SCREENSHOTS OBLIGATOIRES
```bash
# Template de script autotest
export DISPLAY=:0
google-chrome --new-window $URL &
sleep 3
gnome-screenshot -w -f /tmp/test_$(date +%s).png
echo "Screenshot: /tmp/test_$(date +%s).png"
```

### 5. 🧪 VALIDATION AUTOMATIQUE
- Tester chaque fonctionnalité après déploiement
- Vérifier l'UTF-8 sur tous les textes français
- Contrôler les timestamps GMT+2
- Prendre des screenshots de preuve

## ⚠️ DÉTECTION AUTOMATIQUE OBLIGATOIRE

### Signaux d'alerte à détecter :
- `Ã©` au lieu de `é` = problème UTF-8
- `ð` au lieu d'emoji = problème encodage
- Heures en GMT au lieu de GMT+2
- Texte illisible = charset manquant

### Action immédiate :
1. **ARRÊTER** et corriger l'encodage
2. **TESTER** avec Chrome réel
3. **SCREENSHOT** pour validation
4. **CONTINUER** seulement si parfait

## 🎯 OBJECTIF
L'utilisateur doit voir EXACTEMENT ce que je teste - zero différence entre mon test et son expérience.