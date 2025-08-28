#!/bin/bash
echo "🧪 TEST NAVIGATEUR RÉEL - $(date +%H:%M)"
echo "================================================"

# Test avec curl en mode navigateur
echo -e "\n📊 TEST 1: Accès sans auth"
response=$(curl -s -I "https://white-river-053fc6703.2.azurestaticapps.net" \
  -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0" \
  -H "Accept: text/html,application/xhtml+xml")

echo "$response" | grep "HTTP"
echo "$response" | grep -i "location"

echo -e "\n🔐 TEST 2: Contenu de la page"
content=$(curl -s "https://white-river-053fc6703.2.azurestaticapps.net" \
  -H "User-Agent: Mozilla/5.0 Chrome/120.0.0.0")

if echo "$content" | grep -q "v20h20"; then
  echo "✅ Version v20h20 trouvée"
else
  echo "❌ Version v20h20 PAS trouvée"
fi

if echo "$content" | grep -q "msalInstance.initialize"; then
  echo "✅ Code MSAL présent"
else  
  echo "❌ Code MSAL absent"
fi

if echo "$content" | grep -q "signIn()"; then
  echo "✅ Fonction signIn() présente"
else
  echo "❌ Fonction signIn() absente"  
fi

echo -e "\n📝 RÉSUMÉ:"
echo "Le dashboard a le code d'auth mais nécessite JavaScript pour s'exécuter."
echo "Ouvre https://white-river-053fc6703.2.azurestaticapps.net dans Edge pour voir le popup de login."