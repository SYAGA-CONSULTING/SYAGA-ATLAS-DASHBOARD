// Azure Function - Proxy sécurisé pour SharePoint
// Élimine l'erreur 403 en utilisant le Service Principal côté serveur

const { ClientSecretCredential } = require('@azure/identity');
const { Client } = require('@microsoft/microsoft-graph-client');
const { TokenCredentialAuthenticationProvider } = require('@microsoft/microsoft-graph-client/authProviders/azureTokenCredentials');

module.exports = async function (context, req) {
    context.log('🔐 Proxy SharePoint - Authentification côté serveur');

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