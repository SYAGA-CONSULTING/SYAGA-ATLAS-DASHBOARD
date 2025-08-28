#!/usr/bin/env python3
import os
import subprocess
from datetime import datetime

print(f"\n🧪 AUTOTEST COMPLET AVEC SCREENSHOTS - {datetime.now().strftime('%H:%M')}")
print("="*60)

# 1. Capture screenshot du dashboard
print("\n📸 CAPTURE SCREENSHOT DASHBOARD...")
screenshot_path = f"/tmp/dashboard_{datetime.now().strftime('%H%M%S')}.png"
cmd = f'wkhtmltoimage --width 1920 --height 1080 --javascript-delay 5000 "https://white-river-053fc6703.2.azurestaticapps.net" "{screenshot_path}"'
result = subprocess.run(cmd, shell=True, capture_output=True, text=True)

if os.path.exists(screenshot_path):
    print(f"   ✅ Screenshot sauvé: {screenshot_path}")
    # Copier vers Windows pour visualisation
    win_path = f"/mnt/c/temp/dashboard_{datetime.now().strftime('%H%M%S')}.png"
    subprocess.run(f"cp {screenshot_path} {win_path}", shell=True)
    print(f"   📁 Copié vers Windows: {win_path}")
else:
    print("   ❌ Échec capture screenshot")

# 2. Test avec curl pour vérifier auth
print("\n🔐 TEST AUTHENTIFICATION...")
import requests

# Test page principale
resp = requests.get("https://white-river-053fc6703.2.azurestaticapps.net", allow_redirects=False)
print(f"   Page principale: HTTP {resp.status_code}")

if resp.status_code == 200:
    print("   ❌ PAS D'AUTH - Dashboard accessible sans login!")
    # Chercher indices d'auth dans HTML
    if 'signIn' in resp.text or 'login' in resp.text:
        print("   ⚠️ Code de login présent mais pas actif")
    if '/.auth/' in resp.text:
        print("   ⚠️ Routes auth Azure présentes mais pas forcées")
elif resp.status_code == 302:
    print(f"   ✅ Redirection auth vers: {resp.headers.get('Location')}")
else:
    print(f"   ⚠️ Code inattendu: {resp.status_code}")

# Test API
resp_api = requests.get("https://white-river-053fc6703.2.azurestaticapps.net/api/sharepoint-data", allow_redirects=False)
print(f"   API /api/sharepoint-data: HTTP {resp_api.status_code}")

if resp_api.status_code == 200:
    print("   ❌ API NON PROTÉGÉE - Données accessibles!")
    print(f"   Données exposées: {resp_api.text[:100]}...")
elif resp_api.status_code in [401, 302]:
    print("   ✅ API protégée correctement")

print("\n" + "="*60)
print("📊 RÉSULTAT FINAL:")
if resp.status_code == 200:
    print("❌❌❌ AUCUNE AUTHENTIFICATION - DASHBOARD PUBLIC ❌❌❌")
else:
    print("✅ Auth configurée")
    
print(f"\n🖼️ Screenshot disponible: C:\\temp\\dashboard_*.png")