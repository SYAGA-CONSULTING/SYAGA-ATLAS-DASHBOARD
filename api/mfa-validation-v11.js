/**
 * ATLAS v11 - MFA Validation Backend (CRITIQUE)
 * API pour validation MFA et élévation tokens temporaires
 */

// Configuration Azure AD et SharePoint
const config = {
    azure: {
        tenantId: "6027d81c-ad9b-48f5-9da6-96f1bad11429",
        clientId: "f7c4f1b2-3380-4e87-961f-09922ec452b4",
        clientSecret: Buffer.from("Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw==", 'base64').toString('utf-8')
    },
    sharePoint: {
        siteName: "syagacons",
        tokensListId: "NEW_LIST_ID_FOR_V11_TOKENS" // À créer dans SharePoint
    }
};

/**
 * API Endpoint: /api/mfa-validate
 * Méthode: GET
 * Paramètres: ?token=ELEV_XXX_15MIN&server=HOSTNAME
 */
async function handleMFAValidation(req, res) {
    try {
        const { token, server } = req.query;
        
        if (!token || !server) {
            return res.status(400).json({
                success: false,
                error: "Token et serveur requis"
            });
        }

        console.log(`🔐 Demande validation MFA: ${token} pour ${server}`);

        // 1. Vérifier token dans SharePoint
        const tokenData = await getTokenFromSharePoint(token);
        
        if (!tokenData) {
            return res.status(404).json({
                success: false,
                error: "Token non trouvé"
            });
        }

        // 2. Vérifier expiration
        const now = new Date();
        const expiresAt = new Date(tokenData.ExpiresAt);
        
        if (now > expiresAt) {
            await updateTokenStatus(tokenData.Id, "EXPIRED");
            return res.status(401).json({
                success: false,
                error: "Token expiré"
            });
        }

        // 3. Vérifier statut
        if (tokenData.Status === "REVOKED") {
            return res.status(401).json({
                success: false,
                error: "Token révoqué"
            });
        }

        if (tokenData.Status === "CONSUMED") {
            return res.status(401).json({
                success: false,
                error: "Token déjà utilisé"
            });
        }

        // 4. Si déjà élevé, retourner succès
        if (tokenData.Status === "ELEVATED") {
            return res.json({
                success: true,
                status: "already_elevated",
                message: "Token déjà élevé"
            });
        }

        // 5. Rediriger vers Azure AD MFA
        if (tokenData.Status === "WAITING_MFA") {
            const mfaUrl = generateAzureMFAUrl(token, server);
            
            // Page HTML avec redirection Azure AD
            const htmlResponse = `
<!DOCTYPE html>
<html>
<head>
    <title>ATLAS v11 - Validation MFA</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; background: #f5f5f5; }
        .container { max-width: 500px; margin: 0 auto; background: white; padding: 40px; border-radius: 10px; box-shadow: 0 0 20px rgba(0,0,0,0.1); }
        .logo { font-size: 24px; color: #0078d4; margin-bottom: 20px; }
        .button { display: inline-block; background: #0078d4; color: white; padding: 15px 30px; text-decoration: none; border-radius: 5px; margin: 20px 0; }
        .info { color: #666; font-size: 14px; }
        .security { background: #fff3cd; border: 1px solid #ffeaa7; padding: 15px; border-radius: 5px; color: #856404; }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">🛡️ ATLAS v11 - Sécurisation MFA</div>
        
        <h2>Validation requise</h2>
        
        <div class="security">
            <strong>🔐 Sécurité:</strong><br>
            Installation sécurisée pour <strong>${server}</strong><br>
            Token: <code>${token}</code>
        </div>
        
        <p>Cliquez pour valider avec votre compte Azure AD:</p>
        
        <a href="${mfaUrl}" class="button">
            🔐 Valider avec Azure MFA
        </a>
        
        <div class="info">
            <p>⏰ Ce token expire automatiquement dans 15 minutes</p>
            <p>🔒 Authentification multi-facteurs obligatoire</p>
            <p>📱 Utilisez votre session 365 existante</p>
        </div>
    </div>
    
    <script>
        // Auto-redirect après 3 secondes si sur mobile
        if (/Mobi|Android/i.test(navigator.userAgent)) {
            setTimeout(() => {
                window.location.href = "${mfaUrl}";
            }, 3000);
        }
    </script>
</body>
</html>`;

            res.setHeader('Content-Type', 'text/html');
            return res.send(htmlResponse);
        }

        return res.status(400).json({
            success: false,
            error: "Statut token invalide"
        });

    } catch (error) {
        console.error("Erreur validation MFA:", error);
        return res.status(500).json({
            success: false,
            error: "Erreur serveur"
        });
    }
}

/**
 * API Endpoint: /api/mfa-callback
 * Callback Azure AD après validation MFA
 */
async function handleMFACallback(req, res) {
    try {
        const { code, state } = req.query;
        
        if (!code || !state) {
            return res.status(400).json({
                success: false,
                error: "Code et state requis"
            });
        }

        // Décoder state (contient token)
        const tokenData = JSON.parse(Buffer.from(state, 'base64').toString('utf-8'));
        
        console.log(`✅ MFA Callback reçu pour token: ${tokenData.token}`);

        // 1. Vérifier code Azure AD
        const azureValidation = await validateAzureCode(code, tokenData.redirect_uri);
        
        if (!azureValidation.success) {
            return res.status(401).json({
                success: false,
                error: "Validation Azure AD échouée"
            });
        }

        // 2. Élever le token
        await updateTokenStatus(tokenData.token, "ELEVATED", {
            MFAValidated: true,
            MFAValidatedAt: new Date().toISOString(),
            AzureUserId: azureValidation.userId,
            AzureUserEmail: azureValidation.userEmail
        });

        console.log(`🚀 Token élevé avec succès: ${tokenData.token}`);

        // 3. Page de succès
        const successHtml = `
<!DOCTYPE html>
<html>
<head>
    <title>ATLAS v11 - MFA Validé</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; background: #f5f5f5; }
        .container { max-width: 500px; margin: 0 auto; background: white; padding: 40px; border-radius: 10px; box-shadow: 0 0 20px rgba(0,0,0,0.1); }
        .success { color: #28a745; font-size: 48px; margin: 20px 0; }
        .info { color: #666; margin: 20px 0; }
    </style>
</head>
<body>
    <div class="container">
        <div class="success">✅</div>
        <h2>MFA Validé avec succès !</h2>
        
        <div class="info">
            <p>🛡️ Token sécurisé élevé pour 15 minutes</p>
            <p>⚙️ Installation ATLAS v11 en cours...</p>
            <p>💻 Retournez sur votre serveur PowerShell</p>
        </div>
        
        <p><strong>Serveur:</strong> ${tokenData.server}</p>
        <p><strong>Token:</strong> <code>${tokenData.token}</code></p>
    </div>
    
    <script>
        // Fermer automatiquement après 10 secondes
        setTimeout(() => {
            window.close();
        }, 10000);
    </script>
</body>
</html>`;

        res.setHeader('Content-Type', 'text/html');
        return res.send(successHtml);

    } catch (error) {
        console.error("Erreur callback MFA:", error);
        return res.status(500).json({
            success: false,
            error: "Erreur callback"
        });
    }
}

/**
 * API Endpoint: /api/token-status
 * Vérification statut token (appelé par PowerShell)
 */
async function handleTokenStatus(req, res) {
    try {
        const { token } = req.query;
        
        if (!token) {
            return res.status(400).json({
                success: false,
                error: "Token requis"
            });
        }

        const tokenData = await getTokenFromSharePoint(token);
        
        if (!tokenData) {
            return res.json({
                status: "NOT_FOUND"
            });
        }

        // Vérifier expiration
        const now = new Date();
        const expiresAt = new Date(tokenData.ExpiresAt);
        
        if (now > expiresAt && tokenData.Status !== "EXPIRED") {
            await updateTokenStatus(tokenData.Id, "EXPIRED");
            return res.json({ status: "EXPIRED" });
        }

        return res.json({
            status: tokenData.Status,
            server: tokenData.ServerName,
            expiresAt: tokenData.ExpiresAt,
            mfaValidated: tokenData.MFAValidated || false
        });

    } catch (error) {
        console.error("Erreur statut token:", error);
        return res.json({ status: "ERROR" });
    }
}

// ════════════════════════════════════════════════════
// FONCTIONS UTILITAIRES
// ════════════════════════════════════════════════════

/**
 * Obtient token SharePoint OAuth
 */
async function getSharePointToken() {
    const response = await fetch(
        `https://accounts.accesscontrol.windows.net/${config.azure.tenantId}/tokens/OAuth/2`,
        {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({
                grant_type: 'client_credentials',
                client_id: `${config.azure.clientId}@${config.azure.tenantId}`,
                client_secret: config.azure.clientSecret,
                resource: `00000003-0000-0ff1-ce00-000000000000/${config.sharePoint.siteName}.sharepoint.com@${config.azure.tenantId}`
            })
        }
    );

    const data = await response.json();
    return data.access_token;
}

/**
 * Récupère token depuis SharePoint
 */
async function getTokenFromSharePoint(tokenId) {
    const accessToken = await getSharePointToken();
    
    const response = await fetch(
        `https://${config.sharePoint.siteName}.sharepoint.com/_api/web/lists(guid'${config.sharePoint.tokensListId}')/items?$filter=TokenId eq '${tokenId}'`,
        {
            headers: { 'Authorization': `Bearer ${accessToken}` }
        }
    );
    
    const data = await response.json();
    return data.d?.results?.[0] || null;
}

/**
 * Met à jour statut token
 */
async function updateTokenStatus(tokenId, status, additionalFields = {}) {
    const accessToken = await getSharePointToken();
    
    // Chercher item
    const searchResponse = await fetch(
        `https://${config.sharePoint.siteName}.sharepoint.com/_api/web/lists(guid'${config.sharePoint.tokensListId}')/items?$filter=TokenId eq '${tokenId}'`,
        {
            headers: { 'Authorization': `Bearer ${accessToken}` }
        }
    );
    
    const searchData = await searchResponse.json();
    
    if (searchData.d?.results?.[0]) {
        const itemId = searchData.d.results[0].Id;
        
        const updateData = {
            "__metadata": { "type": "SP.Data.ATLASTokensV11ListItem" },
            "Status": status,
            "UpdatedAt": new Date().toISOString(),
            ...additionalFields
        };
        
        await fetch(
            `https://${config.sharePoint.siteName}.sharepoint.com/_api/web/lists(guid'${config.sharePoint.tokensListId}')/items(${itemId})`,
            {
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${accessToken}`,
                    'Accept': 'application/json;odata=verbose',
                    'Content-Type': 'application/json;odata=verbose',
                    'IF-MATCH': '*',
                    'X-HTTP-Method': 'MERGE'
                },
                body: JSON.stringify(updateData)
            }
        );
    }
}

/**
 * Génère URL Azure AD MFA
 */
function generateAzureMFAUrl(token, server) {
    const redirectUri = encodeURIComponent('https://white-river-053fc6703.2.azurestaticapps.net/api/mfa-callback');
    const state = Buffer.from(JSON.stringify({ token, server, redirect_uri: redirectUri })).toString('base64');
    
    return `https://login.microsoftonline.com/${config.azure.tenantId}/oauth2/v2.0/authorize?` +
           `client_id=${config.azure.clientId}&` +
           `response_type=code&` +
           `redirect_uri=${redirectUri}&` +
           `scope=openid profile User.Read&` +
           `state=${state}&` +
           `prompt=select_account&` +
           `response_mode=query`;
}

/**
 * Valide code Azure AD
 */
async function validateAzureCode(code, redirectUri) {
    try {
        // Échange code contre token
        const tokenResponse = await fetch(
            `https://login.microsoftonline.com/${config.azure.tenantId}/oauth2/v2.0/token`,
            {
                method: 'POST',
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                body: new URLSearchParams({
                    client_id: config.azure.clientId,
                    client_secret: config.azure.clientSecret,
                    code: code,
                    redirect_uri: redirectUri,
                    grant_type: 'authorization_code'
                })
            }
        );
        
        const tokenData = await tokenResponse.json();
        
        if (tokenData.access_token) {
            // Obtenir infos utilisateur
            const userResponse = await fetch('https://graph.microsoft.com/v1.0/me', {
                headers: { 'Authorization': `Bearer ${tokenData.access_token}` }
            });
            
            const userData = await userResponse.json();
            
            return {
                success: true,
                userId: userData.id,
                userEmail: userData.mail || userData.userPrincipalName
            };
        }
        
        return { success: false };
        
    } catch (error) {
        console.error("Erreur validation Azure:", error);
        return { success: false };
    }
}

// Export des handlers pour Azure Functions ou autre runtime
module.exports = {
    handleMFAValidation,
    handleMFACallback, 
    handleTokenStatus
};

/* UTILISATION:

// Azure Functions
module.exports = async function (context, req) {
    const path = req.params.path;
    
    switch(path) {
        case 'mfa-validate':
            return await handleMFAValidation(req, context.res);
        case 'mfa-callback':
            return await handleMFACallback(req, context.res);
        case 'token-status':
            return await handleTokenStatus(req, context.res);
        default:
            context.res.status = 404;
    }
};

// Express.js
app.get('/api/mfa-validate', handleMFAValidation);
app.get('/api/mfa-callback', handleMFACallback);
app.get('/api/token-status', handleTokenStatus);

*/