#!/bin/bash

# Script de déploiement automatique vers Azure Static Web App
# ATLAS Dashboard v0.23

echo "🚀 DÉPLOIEMENT ATLAS DASHBOARD SUR AZURE STATIC WEB APP"
echo "=================================================="

# Configuration
RESOURCE_GROUP="rg-syaga-atlas"
APP_NAME="syaga-atlas-dashboard"

# Vérifier connexion Azure
echo "📌 Vérification connexion Azure..."
if ! az account show &>/dev/null; then
    echo "❌ Non connecté à Azure. Connexion..."
    az login
fi

# Afficher le compte actuel
echo "✅ Connecté en tant que:"
az account show --query "[name, user.name]" -o tsv

# Créer un dossier de déploiement propre
echo "📁 Préparation des fichiers..."
rm -rf ./deploy-dist
mkdir -p ./deploy-dist

# Copier tous les fichiers HTML
cp *.html ./deploy-dist/
cp -r css ./deploy-dist/ 2>/dev/null || true
cp -r js ./deploy-dist/ 2>/dev/null || true
cp -r assets ./deploy-dist/ 2>/dev/null || true

# Créer un index.html qui redirige vers le dashboard unifié
cat > ./deploy-dist/index.html << 'EOF'
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="refresh" content="0; url=dashboard-atlas-unified.html">
    <title>ATLAS Dashboard - Redirection</title>
</head>
<body>
    <p>Redirection vers <a href="dashboard-atlas-unified.html">ATLAS Dashboard</a>...</p>
</body>
</html>
EOF

# Lister les fichiers à déployer
echo "📋 Fichiers à déployer:"
ls -la ./deploy-dist/*.html | head -20

# Déployer avec Azure CLI
echo "🌐 Déploiement sur Azure Static Web App..."
echo "   App: $APP_NAME"
echo "   Resource Group: $RESOURCE_GROUP"

# Option 1: Si SWA CLI est installé
if command -v swa &> /dev/null; then
    echo "📦 Utilisation de SWA CLI..."
    swa deploy ./deploy-dist --deployment-token $(az staticwebapp secrets list --name $APP_NAME --resource-group $RESOURCE_GROUP --query "properties.apiKey" -o tsv)
else
    # Option 2: Utiliser GitHub Actions ou méthode directe
    echo "📦 Déploiement via Azure CLI..."
    
    # Récupérer le token de déploiement
    DEPLOYMENT_TOKEN=$(az staticwebapp secrets list \
        --name $APP_NAME \
        --resource-group $RESOURCE_GROUP \
        --query "properties.apiKey" -o tsv)
    
    if [ -z "$DEPLOYMENT_TOKEN" ]; then
        echo "❌ Impossible de récupérer le token de déploiement"
        echo "Essayez: az staticwebapp secrets list --name $APP_NAME --resource-group $RESOURCE_GROUP"
        exit 1
    fi
    
    echo "✅ Token récupéré"
    
    # Créer un zip pour le déploiement
    cd deploy-dist
    zip -r ../deploy.zip .
    cd ..
    
    echo "📤 Upload en cours..."
    
    # Utiliser l'API de déploiement
    curl -X POST \
        "https://${APP_NAME}.azurestaticapps.net/api/zipdeploy" \
        -H "Authorization: Bearer $DEPLOYMENT_TOKEN" \
        -H "Content-Type: application/zip" \
        --data-binary @deploy.zip \
        --max-time 300
fi

# Afficher l'URL
echo ""
echo "✅ DÉPLOIEMENT TERMINÉ!"
echo "=================================================="
echo "🌐 URL de l'application:"
echo "   https://white-river-053fc6703.2.azurestaticapps.net"
echo "   https://white-river-053fc6703.2.azurestaticapps.net/dashboard-atlas-unified.html"
echo ""
echo "📊 Dashboards disponibles:"
echo "   - dashboard-atlas-unified.html (Principal)"
echo "   - dashboard-v0.23-connected.html (Infrastructure)"
echo "   - dashboard-hyperv.html (Hyper-V)"
echo "   - dashboard-windowsupdate.html (Windows Update)"
echo "   - dashboard-veeam.html (Veeam B&R)"
echo ""

# Nettoyage
rm -f deploy.zip
rm -rf deploy-dist

echo "🧹 Nettoyage terminé"