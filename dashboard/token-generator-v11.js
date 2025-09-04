/**
 * ATLAS v11 - Dashboard Token Generator (CRITIQUE)
 * Génère tokens élevés temporaires avec sécurisation MFA
 */

class AtlasV11TokenGenerator {
    constructor() {
        this.sharePointConfig = {
            tenantId: "6027d81c-ad9b-48f5-9da6-96f1bad11429",
            clientId: "f7c4f1b2-3380-4e87-961f-09922ec452b4", 
            clientSecret: atob("Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="),
            tokensListId: "NEW_LIST_ID_FOR_V11_TOKENS" // À créer
        };
        
        this.tokenExpiration = 15 * 60 * 1000; // 15 minutes en ms
    }

    /**
     * Génère un token élevé temporaire pour installation sécurisée
     */
    async generateElevatedToken(serverName, adminEmail, clientName = "SYAGA") {
        try {
            console.log(`🔐 Génération token élevé pour ${serverName}`);
            
            // Génération token unique
            const tokenId = this.generateSecureToken();
            const expirationTime = new Date(Date.now() + this.tokenExpiration);
            
            // Données token
            const tokenData = {
                TokenId: tokenId,
                ServerName: serverName,
                AdminEmail: adminEmail,
                ClientName: clientName,
                Status: "WAITING_MFA",
                Created: new Date().toISOString(),
                ExpiresAt: expirationTime.toISOString(),
                MFAValidated: false,
                ConsumedAt: null,
                InstallationUrl: `https://install.syaga.fr/atlas?server=${serverName}&token=${tokenId}`
            };
            
            // Stockage SharePoint
            const success = await this.storeTokenInSharePoint(tokenData);
            
            if (success) {
                console.log(`✅ Token généré: ${tokenId}`);
                console.log(`📅 Expiration: ${expirationTime.toLocaleString()}`);
                
                return {
                    success: true,
                    tokenId: tokenId,
                    installUrl: tokenData.InstallationUrl,
                    expiresAt: expirationTime,
                    qrCodeUrl: this.generateQRCodeUrl(tokenData.InstallationUrl)
                };
            } else {
                throw new Error("Échec stockage SharePoint");
            }
            
        } catch (error) {
            console.error("❌ Erreur génération token:", error);
            return { success: false, error: error.message };
        }
    }

    /**
     * Génère un token sécurisé unique
     */
    generateSecureToken() {
        const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
        let result = 'ELEV_';
        
        for (let i = 0; i < 16; i++) {
            result += chars.charAt(Math.floor(Math.random() * chars.length));
        }
        
        result += '_15MIN';
        return result;
    }

    /**
     * Stocke le token dans SharePoint
     */
    async storeTokenInSharePoint(tokenData) {
        try {
            // Token OAuth SharePoint
            const accessToken = await this.getSharePointToken();
            
            const response = await fetch(
                `https://syagacons.sharepoint.com/_api/web/lists(guid'${this.sharePointConfig.tokensListId}')/items`,
                {
                    method: 'POST',
                    headers: {
                        'Authorization': `Bearer ${accessToken}`,
                        'Accept': 'application/json;odata=verbose',
                        'Content-Type': 'application/json;odata=verbose'
                    },
                    body: JSON.stringify({
                        "__metadata": { "type": "SP.Data.ATLASTokensV11ListItem" },
                        ...tokenData
                    })
                }
            );

            return response.status === 201;
            
        } catch (error) {
            console.error("Erreur SharePoint:", error);
            return false;
        }
    }

    /**
     * Obtient un token OAuth pour SharePoint
     */
    async getSharePointToken() {
        const response = await fetch(
            `https://accounts.accesscontrol.windows.net/${this.sharePointConfig.tenantId}/tokens/OAuth/2`,
            {
                method: 'POST',
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                body: new URLSearchParams({
                    grant_type: 'client_credentials',
                    client_id: `${this.sharePointConfig.clientId}@${this.sharePointConfig.tenantId}`,
                    client_secret: this.sharePointConfig.clientSecret,
                    resource: `00000003-0000-0ff1-ce00-000000000000/syagacons.sharepoint.com@${this.sharePointConfig.tenantId}`
                })
            }
        );

        const data = await response.json();
        return data.access_token;
    }

    /**
     * Génère URL QR Code pour validation MFA
     */
    generateQRCodeUrl(installUrl) {
        // URL vers API validation MFA
        const mfaValidationUrl = `https://white-river-053fc6703.2.azurestaticapps.net/api/mfa-validate?url=${encodeURIComponent(installUrl)}`;
        
        // URL QR Code service
        return `https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${encodeURIComponent(mfaValidationUrl)}`;
    }

    /**
     * Révoque un token (par admin)
     */
    async revokeToken(tokenId, reason = "Manual revocation") {
        try {
            console.log(`🚫 Révocation token ${tokenId}: ${reason}`);
            
            const accessToken = await this.getSharePointToken();
            
            // Chercher le token
            const searchResponse = await fetch(
                `https://syagacons.sharepoint.com/_api/web/lists(guid'${this.sharePointConfig.tokensListId}')/items?$filter=TokenId eq '${tokenId}'`,
                {
                    headers: { 'Authorization': `Bearer ${accessToken}` }
                }
            );
            
            const searchData = await searchResponse.json();
            
            if (searchData.d.results.length > 0) {
                const itemId = searchData.d.results[0].Id;
                
                // Marquer comme révoqué
                const updateResponse = await fetch(
                    `https://syagacons.sharepoint.com/_api/web/lists(guid'${this.sharePointConfig.tokensListId}')/items(${itemId})`,
                    {
                        method: 'POST',
                        headers: {
                            'Authorization': `Bearer ${accessToken}`,
                            'Accept': 'application/json;odata=verbose',
                            'Content-Type': 'application/json;odata=verbose',
                            'IF-MATCH': '*',
                            'X-HTTP-Method': 'MERGE'
                        },
                        body: JSON.stringify({
                            "__metadata": { "type": "SP.Data.ATLASTokensV11ListItem" },
                            "Status": "REVOKED",
                            "RevokedAt": new Date().toISOString(),
                            "RevocationReason": reason
                        })
                    }
                );

                return updateResponse.status === 204;
            }
            
            return false;
            
        } catch (error) {
            console.error("Erreur révocation:", error);
            return false;
        }
    }

    /**
     * Nettoie les tokens expirés
     */
    async cleanupExpiredTokens() {
        try {
            console.log("🧹 Nettoyage tokens expirés...");
            
            const accessToken = await this.getSharePointToken();
            const now = new Date().toISOString();
            
            // Récupérer tokens expirés
            const response = await fetch(
                `https://syagacons.sharepoint.com/_api/web/lists(guid'${this.sharePointConfig.tokensListId}')/items?$filter=ExpiresAt lt '${now}' and Status ne 'EXPIRED'`,
                {
                    headers: { 'Authorization': `Bearer ${accessToken}` }
                }
            );
            
            const data = await response.json();
            let cleaned = 0;
            
            for (const token of data.d.results) {
                const updateResponse = await fetch(
                    `https://syagacons.sharepoint.com/_api/web/lists(guid'${this.sharePointConfig.tokensListId}')/items(${token.Id})`,
                    {
                        method: 'POST',
                        headers: {
                            'Authorization': `Bearer ${accessToken}`,
                            'Accept': 'application/json;odata=verbose',
                            'Content-Type': 'application/json;odata=verbose',
                            'IF-MATCH': '*',
                            'X-HTTP-Method': 'MERGE'
                        },
                        body: JSON.stringify({
                            "__metadata": { "type": "SP.Data.ATLASTokensV11ListItem" },
                            "Status": "EXPIRED"
                        })
                    }
                );

                if (updateResponse.status === 204) cleaned++;
            }
            
            console.log(`✅ ${cleaned} tokens expirés nettoyés`);
            return cleaned;
            
        } catch (error) {
            console.error("Erreur nettoyage:", error);
            return 0;
        }
    }
}

// Export pour utilisation
if (typeof module !== 'undefined' && module.exports) {
    module.exports = AtlasV11TokenGenerator;
} else {
    window.AtlasV11TokenGenerator = AtlasV11TokenGenerator;
}

/* UTILISATION DASHBOARD:

const tokenGen = new AtlasV11TokenGenerator();

// Générer token pour installation
const result = await tokenGen.generateElevatedToken(
    "LAA-DC01", 
    "admin@client.com",
    "LAA"
);

if (result.success) {
    console.log("URL installation:", result.installUrl);
    console.log("QR Code:", result.qrCodeUrl);
    
    // Afficher dans dashboard
    document.getElementById('install-url').value = result.installUrl;
    document.getElementById('qr-code').src = result.qrCodeUrl;
}

// Nettoyage automatique (à exécuter périodiquement)
setInterval(() => {
    tokenGen.cleanupExpiredTokens();
}, 5 * 60 * 1000); // Toutes les 5 minutes

*/