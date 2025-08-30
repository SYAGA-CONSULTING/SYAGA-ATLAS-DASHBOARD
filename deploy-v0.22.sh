#!/bin/bash

# Script de déploiement ATLAS Dashboard v0.22
# Avec orchestration avancée et agent compatible

echo "🚀 ATLAS Dashboard v0.22 - Déploiement"
echo "======================================"

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
DASHBOARD_FILE="index-v0.22.html"
AGENT_FILE="/mnt/c/temp/AGENT-V0.22-ORCHESTRATION.ps1"
AZURE_STATIC_APP="https://white-river-053fc6703.2.azurestaticapps.net"

echo -e "${BLUE}📋 Vérification des fichiers...${NC}"

# Vérifier que les fichiers existent
if [ ! -f "$DASHBOARD_FILE" ]; then
    echo -e "${RED}❌ Fichier dashboard non trouvé: $DASHBOARD_FILE${NC}"
    exit 1
fi

if [ ! -f "$AGENT_FILE" ]; then
    echo -e "${RED}❌ Fichier agent non trouvé: $AGENT_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Fichiers trouvés${NC}"

# Créer le package de déploiement
echo -e "${BLUE}📦 Création du package de déploiement...${NC}"

# Copier le dashboard comme index.html pour le déploiement
cp $DASHBOARD_FILE index.html

# Créer l'archive pour Azure Static Web Apps
tar -czf dashboard-v0.22.tar.gz index.html staticwebapp.config.json package.json

echo -e "${GREEN}✅ Package créé: dashboard-v0.22.tar.gz${NC}"

# Instructions de déploiement
echo ""
echo -e "${YELLOW}📝 INSTRUCTIONS DE DÉPLOIEMENT${NC}"
echo "================================"
echo ""
echo -e "${BLUE}1. DÉPLOIEMENT DU DASHBOARD:${NC}"
echo "   - Aller sur Azure Portal"
echo "   - Static Web Apps > SYAGA-ATLAS"
echo "   - Déployer le fichier index.html"
echo "   - URL: $AZURE_STATIC_APP"
echo ""
echo -e "${BLUE}2. DÉPLOIEMENT DE L'AGENT:${NC}"
echo "   - Copier l'agent sur chaque serveur:"
echo -e "${GREEN}   C:\\temp\\AGENT-V0.22-ORCHESTRATION.ps1${NC}"
echo ""
echo "   - Installer l'agent:"
echo -e "${GREEN}   .\\AGENT-V0.22-ORCHESTRATION.ps1 -Install${NC}"
echo ""
echo -e "${BLUE}3. VÉRIFICATION:${NC}"
echo "   - Ouvrir le dashboard: $AZURE_STATIC_APP"
echo "   - Vérifier que les serveurs apparaissent"
echo "   - Tester l'orchestration avec un serveur test"
echo ""
echo -e "${YELLOW}⚠️  NOUVELLES FONCTIONNALITÉS v0.22:${NC}"
echo "   ✨ Orchestration intelligente des MAJ"
echo "   ✨ Timeline visuelle de progression"
echo "   ✨ Arrêt d'urgence global"
echo "   ✨ Planification des MAJ"
echo "   ✨ Console de logs améliorée"
echo "   ✨ Support des commandes bidirectionnelles"
echo ""
echo -e "${GREEN}✅ Script de déploiement terminé${NC}"
echo ""
echo -e "${YELLOW}📌 Fichiers prêts:${NC}"
echo "   - Dashboard: index-v0.22.html"
echo "   - Agent: /mnt/c/temp/AGENT-V0.22-ORCHESTRATION.ps1"
echo "   - Package: dashboard-v0.22.tar.gz"