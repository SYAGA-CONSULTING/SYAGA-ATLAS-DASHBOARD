module.exports = async function (context, req) {
    context.log('SharePoint data function v2 - WITH AUTH CHECK');
    
    // Vérifier auth
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        context.res = {
            status: 401,
            headers: { 'Content-Type': 'application/json' },
            body: { error: "Authentication required" }
        };
        return;
    }
    
    // Pour l'instant, retourner des données de test
    // (on ajoutera la vraie connexion SharePoint après)
    const mockServers = [
        {
            fields: {
                Hostname: "SYAGA-HOST01",
                AgentVersion: "6.2-SHAREPOINT",
                LastContact: new Date(Date.now() - 30000).toISOString(),
                Status: "Active"
            }
        },
        {
            fields: {
                Hostname: "SYAGA-HOST02",
                AgentVersion: "6.2-SHAREPOINT",
                LastContact: new Date(Date.now() - 60000).toISOString(),
                Status: "Active"
            }
        }
    ];
    
    context.res = {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
        body: {
            value: mockServers,
            timestamp: new Date().toISOString()
        }
    };
};