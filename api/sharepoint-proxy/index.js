// Azure Function - Proxy sécurisé pour SharePoint
// Élimine l'erreur 403 en utilisant le Service Principal côté serveur

const { ClientSecretCredential } = require('@azure/identity');
const { Client } = require('@microsoft/microsoft-graph-client');
const { TokenCredentialAuthenticationProvider } = require('@microsoft/microsoft-graph-client/authProviders/azureTokenCredentials');

module.exports = async function (context, req) {
    context.log('🔐 Proxy SharePoint - Authentification côté serveur avec vérification utilisateur');
    
    // SÉCURITÉ : Vérifier que l'utilisateur est authentifié M365
    const userToken = req.headers.authorization?.replace('Bearer ', '');
    if (!userToken) {
        context.log.error('❌ Accès refusé - Authentification M365 requise');
        context.res = {
            status: 401,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            body: {
                error: 'Authentification Microsoft 365 requise',
                message: 'Connectez-vous avec votre compte Microsoft 365'
            }
        };
        return;
    }

    // SÉCURITÉ : Valider le token utilisateur Microsoft 365
    try {
        const tokenValidation = await fetch('https://graph.microsoft.com/v1.0/me', {
            headers: { 'Authorization': `Bearer ${userToken}` }
        });
        
        if (!tokenValidation.ok) {
            throw new Error('Token invalide');
        }
        
        const userInfo = await tokenValidation.json();
        context.log(`✅ Utilisateur authentifié: ${userInfo.userPrincipalName}`);
        
        // Vérifier domaine autorisé
        if (!userInfo.userPrincipalName?.endsWith('@syaga.fr')) {
            context.log.error(`❌ Domaine non autorisé: ${userInfo.userPrincipalName}`);
            context.res = {
                status: 403,
                headers: {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                body: {
                    error: 'Domaine non autorisé',
                    message: 'Seuls les utilisateurs @syaga.fr peuvent accéder au dashboard ATLAS'
                }
            };
            return;
        }
        
    } catch (error) {
        context.log.error('❌ Validation token échouée:', error.message);
        context.res = {
            status: 401,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            body: {
                error: 'Token invalide',
                message: 'Reconnectez-vous à Microsoft 365'
            }
        };
        return;
    }

    // Configuration Service Principal - Variables d'environnement pour sécurité
    const tenantId = process.env.AZURE_TENANT_ID || '6027d81c-ad9b-48f5-9da6-96f1bad11429';
    const clientId = process.env.AZURE_CLIENT_ID || 'f66a8c6c-1037-41b8-be3c-4f6e67c1f49e';
    const clientSecret = process.env.AZURE_CLIENT_SECRET; // Obligatoire via variable d'environnement
    
    const siteId = 'syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8';
    const listId = '94dc7ad4-740f-4c1f-b99c-107e01c8f70b';

    // Vérification que le secret est configuré
    if (!clientSecret) {
        context.log.error('❌ AZURE_CLIENT_SECRET non configuré');
        context.res = {
            status: 500,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            body: {
                error: 'Configuration manquante',
                message: 'Variable AZURE_CLIENT_SECRET non configurée dans Azure Static Web App'
            }
        };
        return;
    }

    try {
        // Authentification avec Service Principal
        const credential = new ClientSecretCredential(tenantId, clientId, clientSecret);
        const authProvider = new TokenCredentialAuthenticationProvider(credential, {
            scopes: ['https://graph.microsoft.com/.default']
        });
        
        const graphClient = Client.initWithMiddleware({
            authProvider: authProvider
        });

        // Récupérer les données SharePoint
        const items = await graphClient
            .api(`/sites/${siteId}/lists/${listId}/items`)
            .expand('fields')
            .get();

        context.log(`✅ ${items.value.length} serveurs récupérés`);

        // Retourner les données au dashboard
        context.res = {
            status: 200,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type'
            },
            body: items
        };

    } catch (error) {
        context.log.error('❌ Erreur proxy SharePoint:', error);
        
        context.res = {
            status: 500,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            body: {
                error: 'Erreur serveur proxy SharePoint',
                message: error.message
            }
        };
    }
};