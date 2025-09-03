#!/usr/bin/env python3
"""
ATLAS Auto-Update Manager - Gestion autonome des déploiements
Surveille les rollbacks, analyse les erreurs, crée des versions correctives
"""

import requests
import base64
import json
import time
import re
import subprocess
from datetime import datetime, timedelta
from typing import Dict, List, Optional

class ATLASUpdateManager:
    def __init__(self):
        self.tenant_id = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
        self.client_id = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
        self.client_secret = base64.b64decode("Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw==").decode()
        self.list_id = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"
        self.current_version = "5.5"
        self.repo_path = "/home/sq/SYAGA-CONSULTING/SYAGA-ATLAS-DASHBOARD"
        self.token = None
        
    def get_token(self) -> str:
        """Obtenir token OAuth pour SharePoint"""
        if self.token:
            return self.token
            
        body = {
            'grant_type': 'client_credentials',
            'client_id': f'{self.client_id}@{self.tenant_id}',
            'client_secret': self.client_secret,
            'resource': f'00000003-0000-0ff1-ce00-000000000000/syagacons.sharepoint.com@{self.tenant_id}'
        }
        
        response = requests.post(
            f'https://accounts.accesscontrol.windows.net/{self.tenant_id}/tokens/OAuth/2',
            data=body
        )
        
        if response.status_code == 200:
            self.token = response.json()['access_token']
            return self.token
        else:
            raise Exception(f"Auth failed: {response.status_code}")
    
    def get_sharepoint_data(self) -> List[Dict]:
        """Récupérer toutes les données SharePoint"""
        headers = {
            'Authorization': f'Bearer {self.get_token()}',
            'Accept': 'application/json;odata=verbose'
        }
        
        response = requests.get(
            f'https://syagacons.sharepoint.com/_api/web/lists(guid\'{self.list_id}\')/items?$top=500&$orderby=Modified desc',
            headers=headers
        )
        
        if response.status_code == 200:
            return response.json()['d']['results']
        return []
    
    def check_for_rollbacks(self) -> List[Dict]:
        """Vérifier s'il y a eu des rollbacks"""
        data = self.get_sharepoint_data()
        rollbacks = []
        
        for item in data:
            hostname = item.get('Hostname', '') or item.get('Title', '')
            
            # Chercher les rapports de rollback
            if 'ROLLBACK_' in hostname:
                rollbacks.append({
                    'server': hostname.replace('ROLLBACK_', ''),
                    'failed_version': item.get('AgentVersion', '?'),
                    'reason': item.get('VeeamStatus', ''),
                    'timestamp': item.get('Modified', '')
                })
            
            # Chercher les logs d'erreur
            elif 'FAILED_LOGS_' in hostname:
                server = hostname.replace('FAILED_LOGS_', '')
                # Associer aux rollbacks
                for rb in rollbacks:
                    if rb['server'] == server:
                        rb['error_logs'] = item.get('VeeamStatus', '')
                        
        return rollbacks
    
    def analyze_error(self, error_log: str) -> Dict:
        """Analyser les logs d'erreur pour identifier le problème"""
        analysis = {
            'type': 'unknown',
            'details': '',
            'fix_suggestion': ''
        }
        
        # Patterns d'erreurs courants
        if 'Get-WmiObject' in error_log or 'WMI' in error_log:
            analysis['type'] = 'wmi_error'
            analysis['details'] = 'Erreur WMI - Probablement Get-WmiObject obsolète'
            analysis['fix_suggestion'] = 'Remplacer Get-WmiObject par Get-CimInstance'
            
        elif 'access_token' in error_log or 'OAuth' in error_log:
            analysis['type'] = 'auth_error'
            analysis['details'] = 'Erreur authentification SharePoint'
            analysis['fix_suggestion'] = 'Vérifier token et retry avec timeout'
            
        elif 'Invoke-RestMethod' in error_log:
            analysis['type'] = 'network_error'
            analysis['details'] = 'Erreur réseau/API'
            analysis['fix_suggestion'] = 'Ajouter retry et gestion erreurs réseau'
            
        elif 'ConvertFrom-Json' in error_log:
            analysis['type'] = 'json_error'
            analysis['details'] = 'Erreur parsing JSON'
            analysis['fix_suggestion'] = 'Ajouter validation JSON avant parsing'
            
        elif 'ScheduledTask' in error_log:
            analysis['type'] = 'task_error'
            analysis['details'] = 'Erreur tâche planifiée'
            analysis['fix_suggestion'] = 'Vérifier permissions et existence tâche'
            
        return analysis
    
    def create_fixed_version(self, current_version: str, rollback_info: Dict) -> str:
        """Créer une nouvelle version corrigée basée sur l'analyse"""
        # Parser la version
        major, minor = map(int, current_version.split('.'))
        new_version = f"{major}.{minor + 1}"
        
        print(f"\n🔧 Création version corrective v{new_version}")
        print(f"   Basée sur l'analyse de l'échec de v{rollback_info['failed_version']}")
        
        # Lire l'agent actuel
        agent_file = f"{self.repo_path}/public/agent-v{current_version}.ps1"
        with open(agent_file, 'r', encoding='utf-8') as f:
            agent_code = f.read()
        
        # Analyser l'erreur
        error_analysis = self.analyze_error(rollback_info.get('error_logs', ''))
        print(f"   Type d'erreur: {error_analysis['type']}")
        print(f"   Détails: {error_analysis['details']}")
        print(f"   Fix: {error_analysis['fix_suggestion']}")
        
        # Appliquer les corrections
        fixed_code = agent_code.replace(f'$version = "{current_version}"', f'$version = "{new_version}"')
        
        if error_analysis['type'] == 'wmi_error':
            # Remplacer Get-WmiObject par Get-CimInstance
            fixed_code = fixed_code.replace('Get-WmiObject', 'Get-CimInstance')
            fixed_code = fixed_code.replace('Win32_OperatingSystem', 'Win32_OperatingSystem')
            
        elif error_analysis['type'] == 'auth_error':
            # Ajouter retry sur auth
            fixed_code = fixed_code.replace(
                'Invoke-RestMethod -Uri "https://accounts.accesscontrol.windows.net',
                'Invoke-RestMethod -Uri "https://accounts.accesscontrol.windows.net" -TimeoutSec 30'
            )
            
        elif error_analysis['type'] == 'network_error':
            # Ajouter gestion d'erreur réseau
            fixed_code = fixed_code.replace('-EA Stop', '-EA Stop -TimeoutSec 30')
        
        # Ajouter un commentaire sur le fix
        fixed_code = fixed_code.replace(
            f'# ATLAS Agent v{new_version}',
            f'# ATLAS Agent v{new_version} - Auto-fix from v{rollback_info["failed_version"]} rollback\n# Fixed: {error_analysis["type"]}'
        )
        
        # Sauvegarder la nouvelle version
        new_agent_file = f"{self.repo_path}/public/agent-v{new_version}.ps1"
        with open(new_agent_file, 'w', encoding='utf-8') as f:
            f.write(fixed_code)
        
        print(f"   ✅ Version v{new_version} créée avec corrections")
        
        return new_version
    
    def deploy_version(self, version: str):
        """Déployer une nouvelle version"""
        print(f"\n📦 Déploiement v{version}")
        
        # Mettre à jour install-latest.ps1
        install_file = f"{self.repo_path}/public/install-latest.ps1"
        with open(install_file, 'r', encoding='utf-8') as f:
            content = f.read()
        
        content = re.sub(
            r'\$LATEST_VERSION = "[^"]*"',
            f'$LATEST_VERSION = "{version}"',
            content
        )
        
        with open(install_file, 'w', encoding='utf-8') as f:
            f.write(content)
        
        # Git commit et push
        subprocess.run(['git', 'add', '-A'], cwd=self.repo_path)
        subprocess.run([
            'git', 'commit', '-m', 
            f'🤖 AUTO-FIX v{version} - Correction automatique après rollback\n\nVersion générée automatiquement suite à analyse des logs d\'erreur'
        ], cwd=self.repo_path)
        subprocess.run(['git', 'push'], cwd=self.repo_path)
        
        print(f"   ✅ v{version} déployée sur GitHub")
        
        # Créer commande UPDATE_ALL
        self.create_update_command(version)
    
    def create_update_command(self, version: str):
        """Créer commande UPDATE_ALL dans SharePoint"""
        headers = {
            'Authorization': f'Bearer {self.get_token()}',
            'Accept': 'application/json;odata=verbose',
            'Content-Type': 'application/json;odata=verbose'
        }
        
        update_data = {
            '__metadata': {'type': 'SP.Data.ATLASServersListItem'},
            'Title': 'UPDATE_ALL',
            'Hostname': 'UPDATE_ALL',
            'State': f'UPDATE_TO_v{version}',
            'AgentVersion': version,
            'Role': 'Command',
            'VeeamStatus': f'Auto-update to v{version} - Automated fix deployment',
            'LastContact': datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
        }
        
        response = requests.post(
            f'https://syagacons.sharepoint.com/_api/web/lists(guid\'{self.list_id}\')/items',
            headers=headers,
            json=update_data
        )
        
        if response.status_code == 201:
            print(f"   ✅ Commande UPDATE_ALL créée pour v{version}")
        else:
            print(f"   ❌ Erreur création commande: {response.status_code}")
    
    def wait_and_monitor(self, version: str, wait_minutes: int = 15):
        """Attendre et surveiller le déploiement"""
        print(f"\n⏳ Attente {wait_minutes} minutes pour laisser le temps au déploiement...")
        print(f"   Version déployée: v{version}")
        print(f"   Si erreur → Rollback automatique après 10 min")
        print(f"   Si succès → Les agents confirmeront leur update")
        
        end_time = datetime.now() + timedelta(minutes=wait_minutes)
        
        while datetime.now() < end_time:
            remaining = (end_time - datetime.now()).total_seconds() / 60
            print(f"   ⏰ Temps restant: {int(remaining)} minutes", end='\r')
            time.sleep(60)  # Check toutes les minutes
            
            # Vérifier s'il y a déjà des confirmations ou rollbacks
            data = self.get_sharepoint_data()
            confirmations = [d for d in data if f'UPDATE_CONFIRMED' in d.get('Title', '')]
            rollbacks = [d for d in data if 'ROLLBACK_' in d.get('Title', '')]
            
            if confirmations:
                print(f"\n   ✅ Confirmations détectées: {len(confirmations)} serveurs")
            if rollbacks:
                print(f"\n   ⚠️  Rollbacks détectés: {len(rollbacks)} serveurs")
                break
        
        print(f"\n✅ Fin de la période d'attente")
    
    def run_update_cycle(self):
        """Exécuter un cycle complet de mise à jour"""
        print("\n" + "="*70)
        print("🤖 ATLAS AUTO-UPDATE MANAGER - Cycle autonome")
        print("="*70)
        
        iteration = 0
        max_iterations = 5  # Limite de sécurité
        
        while iteration < max_iterations:
            iteration += 1
            print(f"\n📍 Itération {iteration}/{max_iterations}")
            
            # 1. Vérifier les rollbacks
            print("\n1️⃣ Vérification des rollbacks...")
            rollbacks = self.check_for_rollbacks()
            
            if not rollbacks:
                print("   ✅ Aucun rollback détecté")
                
                # Vérifier si tous les serveurs sont à jour
                data = self.get_sharepoint_data()
                servers = {}
                for item in data:
                    hostname = item.get('Hostname', '')
                    if hostname in ['SYAGA-HOST01', 'SYAGA-HOST02', 'SYAGA-VEEAM01']:
                        servers[hostname] = item.get('AgentVersion', '?')
                
                if all(v == self.current_version for v in servers.values()):
                    print(f"   🎉 Tous les serveurs sont en v{self.current_version}")
                    print("   Mission accomplie !")
                    break
                else:
                    print(f"   ⏳ Serveurs pas encore tous à jour")
                    print(f"      {servers}")
                    
            else:
                print(f"   ⚠️ {len(rollbacks)} rollback(s) détecté(s)")
                
                for rb in rollbacks:
                    print(f"\n   📋 Rollback sur {rb['server']}:")
                    print(f"      Version échouée: v{rb['failed_version']}")
                    print(f"      Raison: {rb['reason']}")
                    
                    if 'error_logs' in rb:
                        print(f"      Logs d'erreur disponibles")
                        
                        # 2. Créer version corrective
                        print("\n2️⃣ Création version corrective...")
                        new_version = self.create_fixed_version(self.current_version, rb)
                        self.current_version = new_version
                        
                        # 3. Déployer
                        print("\n3️⃣ Déploiement...")
                        self.deploy_version(new_version)
                        
                        # 4. Attendre
                        print("\n4️⃣ Monitoring...")
                        self.wait_and_monitor(new_version)
                        
                        break  # Traiter un rollback à la fois
                    else:
                        print("      ⏳ En attente des logs d'erreur...")
                        time.sleep(120)  # Attendre 2 min que les logs arrivent
            
            # Pause entre itérations
            if iteration < max_iterations:
                print("\n💤 Pause 2 minutes avant prochaine vérification...")
                time.sleep(120)
        
        print("\n" + "="*70)
        print("✅ Fin du cycle auto-update")
        print("="*70)

if __name__ == "__main__":
    manager = ATLASUpdateManager()
    
    try:
        # Démarrer avec la v5.5 déjà déployée
        print("🚀 Démarrage AUTO-UPDATE MANAGER pour ATLAS")
        print(f"   Version actuelle déployée: v{manager.current_version}")
        
        # Créer une commande UPDATE_ALL pour tester
        print("\n📤 Envoi commande UPDATE_ALL pour v5.5...")
        manager.create_update_command("5.5")
        
        # Lancer le cycle
        manager.run_update_cycle()
        
    except Exception as e:
        print(f"\n❌ Erreur: {e}")
        import traceback
        traceback.print_exc()