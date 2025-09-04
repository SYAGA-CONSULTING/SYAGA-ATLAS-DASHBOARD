#!/usr/bin/env python3
"""
VÉRIFICATION FINALE - Compter EXACTEMENT ce qui reste
"""
import requests
import base64

# Config SharePoint
tenant_id = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
client_id = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
client_secret_b64 = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
client_secret = base64.b64decode(client_secret_b64).decode('utf-8')

print("✅ VÉRIFICATION FINALE - ÉTAT RÉEL DES COMMANDES")
print("="*60)

# Token
token_url = f"https://accounts.accesscontrol.windows.net/{tenant_id}/tokens/OAuth/2"
token_body = {
    "grant_type": "client_credentials",
    "client_id": f"{client_id}@{tenant_id}",
    "client_secret": client_secret,
    "resource": f"00000003-0000-0ff1-ce00-000000000000/syagacons.sharepoint.com@{tenant_id}"
}

response = requests.post(token_url, data=token_body)
token = response.json()["access_token"]

headers = {"Authorization": f"Bearer {token}", "Accept": "application/json;odata=nometadata"}

commands_list_id = "ce76b316-0d45-42e3-9eda-58b90b3ca4c5"

print("1️⃣ COMMANDES PENDING (ce que l'updater va voir):")
print("-"*50)

# Compter les PENDING
pending_url = f"https://syagacons.sharepoint.com/_api/web/lists(guid'{commands_list_id}')/items?$filter=Status eq 'PENDING'&$select=Id,Title,TargetVersion,Status"

response = requests.get(pending_url, headers=headers)

if response.status_code == 200:
    pending_items = response.json().get("value", [])
    
    print(f"📊 TOTAL PENDING: {len(pending_items)}")
    
    if len(pending_items) == 0:
        print("🔴 ERREUR: AUCUNE COMMANDE PENDING - L'AUTO-UPDATE NE FONCTIONNERA PAS")
    else:
        v10_2_count = 0
        other_count = 0
        
        for item in pending_items:
            version = item.get('TargetVersion', 'unknown')
            if version == "10.2":
                v10_2_count += 1
                print(f"  ✅ {item['Title']} - v{version} - ID {item['Id']}")
            else:
                other_count += 1
                print(f"  ❌ {item['Title']} - v{version} - ID {item['Id']} - PROBLÈME!")
        
        print(f"\n📈 ANALYSE:")
        print(f"   ✅ Commandes v10.2: {v10_2_count}")
        print(f"   ❌ Autres versions: {other_count}")
        
        if other_count == 0 and v10_2_count > 0:
            print("🎯 PARFAIT ! Seules les v10.2 restent PENDING")
        elif other_count > 0:
            print("⚠️ PROBLÈME ! Il reste des anciennes versions")
        else:
            print("🔴 PROBLÈME ! Aucune v10.2 PENDING")

else:
    print(f"❌ Erreur récupération PENDING: {response.status_code}")

print("\n2️⃣ TOUTES LES COMMANDES (pour contrôle):")
print("-"*50)

# Compter TOUT
all_url = f"https://syagacons.sharepoint.com/_api/web/lists(guid'{commands_list_id}')/items?$select=Id,Status&$top=100"

response = requests.get(all_url, headers=headers)

if response.status_code == 200:
    all_items = response.json().get("value", [])
    
    pending_total = sum(1 for item in all_items if item.get('Status') == 'PENDING')
    cancelled_total = sum(1 for item in all_items if item.get('Status') == 'CANCELLED')
    executed_total = sum(1 for item in all_items if item.get('Status') == 'EXECUTED')
    
    print(f"📊 RÉPARTITION COMPLÈTE:")
    print(f"   ⏳ PENDING: {pending_total}")
    print(f"   ❌ CANCELLED: {cancelled_total}")
    print(f"   ✅ EXECUTED: {executed_total}")
    print(f"   📋 TOTAL: {len(all_items)}")

print("\n" + "="*60)

# CONCLUSION FINALE
if 'pending_items' in locals():
    if len(pending_items) > 0 and all(item.get('TargetVersion') == '10.2' for item in pending_items):
        print("🎊 SUCCÈS TOTAL !")
        print("   ✅ Nettoyage réussi")
        print("   ✅ Seules les v10.2 restent PENDING")
        print("   ✅ L'auto-update peut maintenant fonctionner")
        print("   🚀 Les agents vont passer en v10.2 automatiquement !")
    else:
        print("⚠️ PROBLÈME DÉTECTÉ")
        print("   Il faut encore nettoyer ou créer de nouvelles commandes v10.2")
else:
    print("❌ ÉCHEC VÉRIFICATION")

print("="*60)