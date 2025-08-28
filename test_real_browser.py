#!/usr/bin/env python3
import requests
from datetime import datetime

print(f"\n🧪 TEST RÉEL DASHBOARD - {datetime.now().strftime('%H:%M')}")
print("="*60)

# Test 1: Page principale
print("\n1️⃣ TEST PAGE PRINCIPALE")
response = requests.get("https://white-river-053fc6703.2.azurestaticapps.net", allow_redirects=False)
print(f"   Code HTTP: {response.status_code}")
if response.status_code == 302:
    print(f"   Redirection vers: {response.headers.get('Location', 'N/A')}")
else:
    # Chercher auth dans le HTML
    if 'loginPopup' in response.text:
        print("   ✅ Code auth MSAL trouvé")
    else:
        print("   ❌ PAS de code auth MSAL")
    
    if '/.auth/login' in response.text:
        print("   ✅ Auth Azure Static Web Apps trouvée")
    else:
        print("   ❌ PAS d'auth Azure SWA")

# Test 2: API sans auth
print("\n2️⃣ TEST API SANS AUTH")
response = requests.get("https://white-river-053fc6703.2.azurestaticapps.net/api/sharepoint-data", allow_redirects=False)
print(f"   Code HTTP: {response.status_code}")
if response.status_code == 401:
    print("   ✅ API protégée - auth requise")
elif response.status_code == 302:
    print(f"   ✅ Redirection auth: {response.headers.get('Location', 'N/A')}")
elif response.status_code == 200:
    print("   ❌ ERREUR: API NON PROTÉGÉE !")
    print(f"   Données exposées: {response.text[:100]}")

# Test 3: Vérifier version
print("\n3️⃣ VÉRIFICATION VERSION")
response = requests.get("https://white-river-053fc6703.2.azurestaticapps.net")
if 'v20h' in response.text:
    import re
    version = re.search(r'v(\d+h\d+)', response.text)
    if version:
        print(f"   Version trouvée: {version.group(0)}")
else:
    print("   ❌ Pas de version dans la page")

print("\n" + "="*60)
print("📊 RÉSUMÉ:")
print("   Si tout est ✅ = Dashboard sécurisé")
print("   Si des ❌ = Problème de sécurité !")