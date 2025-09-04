#!/usr/bin/env python3
"""
Créer commande UPDATE_ALL vers v6.4 et surveiller les logs
"""
import json
import requests
import base64
from datetime import datetime
import time

# Config SharePoint
tenant_id = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
client_id = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
client_secret_b64 = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
client_secret = base64.b64decode(client_secret_b64).decode('utf-8')

def get_token():
    """Obtenir token OAuth"""
    token_url = f"https://accounts.accesscontrol.windows.net/{tenant_id}/tokens/OAuth/2"
    token_body = {
        "grant_type": "client_credentials",
        "client_id": f"{client_id}@{tenant_id}",
        "client_secret": client_secret,
        "resource": f"00000003-0000-0ff1-ce00-000000000000/syagacons.sharepoint.com@{tenant_id}"
    }
    
    response = requests.post(token_url, data=token_body)
    if response.status_code != 200:
        print(f"❌ Erreur obtention token: {response.text}")
        return None
    
    return response.json()["access_token"]

def create_update_command(token):
    """Créer commande UPDATE_ALL"""
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json;odata=verbose",
        "Content-Type": "application/json;odata=verbose"
    }
    
    # Liste ATLAS-Servers
    list_id = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"
    
    # Créer commande UPDATE_ALL
    command_data = {
        "__metadata": {"type": "SP.Data.ATLASServersListItem"},
        "Title": "UPDATE_ALL",
        "AgentVersion": "6.4",
        "State": "UPDATE_COMMAND",
        "VeeamStatus": f"TEST UPDATE_ALL v6.4 - {datetime.now().strftime('%H:%M:%S')}"
    }
    
    create_url = f"https://syagacons.sharepoint.com/_api/web/lists(guid'{list_id}')/items"
    
    print("📤 Création commande UPDATE_ALL vers v6.4...")
    response = requests.post(create_url, headers=headers, json=command_data)
    
    if response.status_code in [200, 201]:
        result = response.json()
        print("✅ Commande UPDATE_ALL créée avec succès")
        print(f"🆔 ID: {result['d']['Id']}")
        print(f"🔄 Version cible: v{result['d']['AgentVersion']}")
        print(f"⏰ Heure: {datetime.now().strftime('%H:%M:%S')}")
        return True
    else:
        print(f"❌ Erreur création commande: {response.status_code}")
        print(response.text)
        return False

def check_servers_status(token):
    """Vérifier l'état des serveurs"""
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json;odata=verbose"
    }
    
    list_id = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"
    
    # Récupérer les serveurs
    search_url = f"https://syagacons.sharepoint.com/_api/web/lists(guid'{list_id}')/items?$filter=Hostname ne null&$select=Hostname,AgentVersion,State,VeeamStatus,Modified&$orderby=Modified desc&$top=50"
    response = requests.get(search_url, headers=headers)
    
    if response.status_code == 200:
        items = response.json()["d"]["results"]
        
        # Grouper par hostname pour avoir la dernière version
        servers = {}
        for item in items:
            hostname = item.get("Hostname", "")
            if hostname and hostname not in ["UPDATE_ALL", "UPDATE_CONFIG", "CONFIG"]:
                if hostname not in servers or item["Modified"] > servers[hostname]["Modified"]:
                    servers[hostname] = item
        
        return servers
    return {}

# MAIN
print("=" * 70)
print("🚀 TEST UPDATE_ALL + LOGS + ROLLBACK")
print("=" * 70)

# Obtenir token
print("\n🔐 Authentification...")
token = get_token()
if not token:
    exit(1)
print("✅ Token obtenu")

# État initial
print("\n📊 ÉTAT INITIAL DES SERVEURS:")
print("-" * 70)
initial_servers = check_servers_status(token)
for hostname, info in sorted(initial_servers.items()):
    version = info.get("AgentVersion", "?")
    status = info.get("VeeamStatus", "")
    print(f"• {hostname}: v{version}")

# Créer commande UPDATE_ALL
print("\n" + "=" * 70)
if create_update_command(token):
    print("\n⏳ Surveillance des mises à jour (5 minutes)...")
    print("=" * 70)
    
    # Surveiller pendant 5 minutes
    start_time = time.time()
    check_interval = 30  # Vérifier toutes les 30 secondes
    max_duration = 300  # 5 minutes max
    
    updates_detected = set()
    rollbacks_detected = set()
    
    while time.time() - start_time < max_duration:
        elapsed = int(time.time() - start_time)
        print(f"\n⏰ T+{elapsed}s - Vérification...")
        
        current_servers = check_servers_status(token)
        
        for hostname, info in current_servers.items():
            if hostname not in initial_servers:
                continue
                
            old_version = initial_servers[hostname].get("AgentVersion", "?")
            new_version = info.get("AgentVersion", "?")
            status = info.get("VeeamStatus", "")
            
            # Détecter mise à jour
            if new_version != old_version and hostname not in updates_detected:
                if new_version == "6.4":
                    print(f"  ✅ {hostname}: UPDATE RÉUSSI v{old_version} → v{new_version}")
                    updates_detected.add(hostname)
                else:
                    print(f"  ⚠️ {hostname}: Version changée v{old_version} → v{new_version}")
            
            # Détecter rollback
            if "ROLLBACK" in status and hostname not in rollbacks_detected:
                print(f"  🔄 {hostname}: ROLLBACK DÉTECTÉ - {status}")
                rollbacks_detected.add(hostname)
            
            # Afficher status si contient UPDATE ou ERROR
            if ("UPDATE" in status or "ERROR" in status) and hostname in initial_servers:
                print(f"  📝 {hostname}: {status[:80]}")
        
        # Si tous ont été mis à jour, arrêter
        if len(updates_detected) >= len(initial_servers):
            print("\n🎉 TOUS LES SERVEURS MIS À JOUR!")
            break
        
        # Attendre avant prochaine vérification
        if time.time() - start_time < max_duration:
            time.sleep(check_interval)
    
    # Rapport final
    print("\n" + "=" * 70)
    print("📊 RAPPORT FINAL")
    print("=" * 70)
    
    final_servers = check_servers_status(token)
    
    print("\n📈 État final des serveurs:")
    for hostname, info in sorted(final_servers.items()):
        if hostname in initial_servers:
            old_v = initial_servers[hostname].get("AgentVersion", "?")
            new_v = info.get("AgentVersion", "?")
            status = info.get("VeeamStatus", "N/A")[:50]
            
            if new_v == "6.4":
                icon = "✅"
            elif new_v != old_v:
                icon = "⚠️"
            else:
                icon = "❌"
            
            print(f"{icon} {hostname}: v{old_v} → v{new_v}")
            if "ROLLBACK" in info.get("VeeamStatus", ""):
                print(f"   └─ ROLLBACK: {status}")
    
    print(f"\n📊 Résumé:")
    print(f"  • Serveurs mis à jour: {len(updates_detected)}/{len(initial_servers)}")
    print(f"  • Rollbacks détectés: {len(rollbacks_detected)}")
    
    if len(updates_detected) == len(initial_servers):
        print("\n✅ TEST RÉUSSI: UPDATE_ALL a fonctionné sur tous les serveurs!")
    elif len(rollbacks_detected) > 0:
        print("\n⚠️ TEST PARTIEL: Des rollbacks ont été détectés")
    else:
        print("\n❌ TEST ÉCHOUÉ: Tous les serveurs n'ont pas été mis à jour")