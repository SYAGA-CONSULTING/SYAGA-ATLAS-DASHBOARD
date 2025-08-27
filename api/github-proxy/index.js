const https = require('https');

module.exports = async function (context, req) {
    // Headers CORS pour GitHub Pages
    context.res.headers = {
        'Access-Control-Allow-Origin': 'https://syaga-consulting.github.io',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        'Content-Type': 'application/json'
    };

    // Gérer preflight OPTIONS
    if (req.method === 'OPTIONS') {
        context.res = { status: 200, body: '' };
        return;
    }

    try {
        // Vérifier authentification (basique pour commencer)
        if (!req.headers.authorization) {
            context.res = {
                status: 401,
                body: { error: 'Token d\'authentification requis' }
            };
            return;
        }

        // Token GitHub depuis les variables d'environnement
        const githubToken = process.env.GITHUB_TOKEN;
        if (!githubToken) {
            context.res = {
                status: 500,
                body: { error: 'Configuration serveur manquante' }
            };
            return;
        }

        // URL GitHub depuis la requête
        const { githubPath } = req.body;
        if (!githubPath || !githubPath.startsWith('/repos/SYAGA-CONSULTING/SYAGA-ATLAS-DATA/')) {
            context.res = {
                status: 400,
                body: { error: 'Chemin GitHub invalide' }
            };
            return;
        }

        // Construire l'URL GitHub API
        const githubUrl = `https://api.github.com${githubPath}`;

        context.log(`Proxy vers: ${githubUrl}`);

        // Appel à GitHub API
        const response = await fetch(githubUrl, {
            method: 'GET',
            headers: {
                'Authorization': `token ${githubToken}`,
                'Accept': 'application/vnd.github.v3+json',
                'User-Agent': 'SYAGA-ATLAS-Dashboard'
            }
        });

        if (!response.ok) {
            throw new Error(`GitHub API error: ${response.status} ${response.statusText}`);
        }

        const data = await response.json();

        context.res = {
            status: 200,
            body: data
        };

        context.log(`✅ Succès: ${githubPath}`);

    } catch (error) {
        context.log.error(`❌ Erreur: ${error.message}`);
        
        context.res = {
            status: 500,
            body: { 
                error: 'Erreur serveur', 
                message: error.message,
                timestamp: new Date().toISOString()
            }
        };
    }
};

// Fonction fetch pour Node.js (si pas disponible)
async function fetch(url, options) {
    const https = require('https');
    const { URL } = require('url');
    
    return new Promise((resolve, reject) => {
        const parsedUrl = new URL(url);
        const requestOptions = {
            hostname: parsedUrl.hostname,
            port: parsedUrl.port || 443,
            path: parsedUrl.pathname + parsedUrl.search,
            method: options.method || 'GET',
            headers: options.headers || {}
        };

        const req = https.request(requestOptions, (res) => {
            let data = '';
            
            res.on('data', (chunk) => {
                data += chunk;
            });
            
            res.on('end', () => {
                resolve({
                    ok: res.statusCode >= 200 && res.statusCode < 300,
                    status: res.statusCode,
                    statusText: res.statusMessage,
                    json: () => Promise.resolve(JSON.parse(data))
                });
            });
        });

        req.on('error', (error) => {
            reject(error);
        });

        if (options.body) {
            req.write(options.body);
        }

        req.end();
    });
}