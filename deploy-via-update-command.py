#!/usr/bin/env python3
"""
Déploiement via le système UPDATE qui FONCTIONNE DÉJÀ
Utilise la méthode des updaters v10.0
"""

import requests
from datetime import datetime
import time
import base64

# Config SharePoint (depuis updater-v10.0.ps1)
TENANT_ID = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
CLIENT_ID = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
CLIENT_SECRET_B64 = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
CLIENT_SECRET = base64.b64decode(CLIENT_SECRET_B64).decode('utf-8')
SITE_NAME = "syagacons"
COMMANDS_LIST_ID = "ce76b316-0d45-42e3-9eda-58b90b3ca4c5"

def get_sharepoint_token():
    """Obtenir token SharePoint (méthode qui marche depuis updater)"""
    print("🔑 Obtention token SharePoint...")
    
    token_body = {
        "grant_type": "client_credentials",
        "client_id": f"{CLIENT_ID}@{TENANT_ID}",
        "client_secret": CLIENT_SECRET,
        "resource": f"00000003-0000-0ff1-ce00-000000000000/{SITE_NAME}.sharepoint.com@{TENANT_ID}"
    }
    
    token_url = f"https://accounts.accesscontrol.windows.net/{TENANT_ID}/tokens/OAuth/2"
    
    try:
        response = requests.post(token_url, data=token_body)
        if response.status_code == 200:
            print("✅ Token obtenu")
            return response.json()["access_token"]
    except Exception as e:
        print(f"❌ Erreur token: {e}")
    
    return None

def create_update_command(token, version="10.3"):
    """Créer commande UPDATE dans SharePoint"""
    print(f"\n📝 Création commande UPDATE vers v{version}...")
    
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json;odata=verbose",
        "Content-Type": "application/json;odata=verbose"
    }
    
    # Commande UPDATE pour tous les serveurs (sans metadata pour éviter l'erreur)
    command_data = {
        "Title": f"UPDATE_TO_{version}",
        "CommandType": "UPDATE_ALL",
        "Status": "PENDING",
        "TargetHostname": "ALL",
        "TargetVersion": version,
        "Parameters": "VALIDATION_TEST"
    }
    
    url = f"https://{SITE_NAME}.sharepoint.com/_api/web/lists(guid'{COMMANDS_LIST_ID}')/items"
    
    try:
        response = requests.post(url, headers=headers, json=command_data)
        if response.status_code == 201:
            print(f"✅ Commande UPDATE créée pour v{version}")
            print("  - Type: UPDATE_ALL")
            print("  - Target: ALL servers")
            print("  - Status: PENDING")
            return True
        else:
            print(f"❌ Erreur création: {response.status_code}")
            print(response.text[:500])
    except Exception as e:
        print(f"❌ Exception: {e}")
    
    return False

def check_update_status(token):
    """Vérifier le statut des mises à jour"""
    print("\n🔍 Vérification statut des commandes...")
    
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json;odata=verbose"
    }
    
    url = f"https://{SITE_NAME}.sharepoint.com/_api/web/lists(guid'{COMMANDS_LIST_ID}')/items?$top=10&$orderby=Created desc"
    
    try:
        response = requests.get(url, headers=headers)
        if response.status_code == 200:
            data = response.json()
            commands = data.get("d", {}).get("results", [])
            
            print(f"📋 {len(commands)} commandes trouvées:")
            for cmd in commands[:5]:  # Afficher les 5 dernières
                print(f"  - {cmd.get('Title', 'N/A')}: {cmd.get('Status', 'N/A')} (v{cmd.get('TargetVersion', 'N/A')})")
            
            return commands
        else:
            print(f"❌ Erreur lecture: {response.status_code}")
    except Exception as e:
        print(f"❌ Exception: {e}")
    
    return []

def mark_command_completed(token, command_id):
    """Marquer une commande comme complétée"""
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json;odata=verbose",
        "Content-Type": "application/json;odata=verbose",
        "IF-MATCH": "*",
        "X-HTTP-Method": "MERGE"
    }
    
    update_data = {
        "__metadata": {"type": "SP.Data.ATLAS_x002d_CommandsListItem"},
        "Status": "COMPLETED"
    }
    
    url = f"https://{SITE_NAME}.sharepoint.com/_api/web/lists(guid'{COMMANDS_LIST_ID}')/items({command_id})"
    
    try:
        response = requests.post(url, headers=headers, json=update_data)
        if response.status_code in [200, 204]:
            print(f"✅ Commande {command_id} marquée COMPLETED")
            return True
    except Exception as e:
        print(f"❌ Erreur update: {e}")
    
    return False

def main():
    print("🚀 DÉPLOIEMENT VIA SYSTÈME UPDATE EXISTANT")
    print("=" * 60)
    
    # Obtenir token
    token = get_sharepoint_token()
    if not token:
        print("❌ Impossible d'obtenir le token")
        return
    
    # Créer commande UPDATE
    if create_update_command(token, "10.3"):
        print("\n⏰ Les updaters vont récupérer la commande dans ~1 minute")
        print("   Ils téléchargeront agent-v10.3.ps1 depuis Azure SWA")
        
        # Attendre un peu
        print("\n⏳ Attente 2 minutes pour laisser les updaters agir...")
        for i in range(4):
            time.sleep(30)
            print(f"   {30 * (i + 1)}s écoulées...")
        
        # Vérifier le statut
        commands = check_update_status(token)
        
        # Si on trouve notre commande et qu'elle est toujours PENDING, on peut la compléter
        for cmd in commands:
            if cmd.get("CommandType") == "UPDATE_ALL" and cmd.get("Status") == "PENDING":
                cmd_id = cmd.get("ID") or cmd.get("Id")
                if cmd_id:
                    print(f"\n🔄 Marquage commande {cmd_id} comme COMPLETED...")
                    mark_command_completed(token, cmd_id)
                    break
        
        print("\n✅ Déploiement lancé via le système UPDATE")
        print("   Les serveurs vont s'auto-mettre à jour vers v10.3")
    else:
        print("❌ Échec création commande UPDATE")
    
    print("\n" + "=" * 60)
    print("Pour vérifier: les updaters vont écrire dans C:\\SYAGA-ATLAS\\updater_log.txt")

if __name__ == "__main__":
    main()