module.exports = async function (context, req) {
    context.log('Secure message function - checking auth');
    
    // Vérifier le token M365
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        context.res = {
            status: 401,
            body: {
                error: "Authentication required",
                message: "Please login with Microsoft 365"
            }
        };
        return;
    }
    
    const token = authHeader.replace('Bearer ', '');
    
    // Validation simple du token (vérifier qu'il existe et n'est pas vide)
    if (!token || token.length < 100) {
        context.res = {
            status: 401,
            body: {
                error: "Invalid token",
                message: "Token is missing or invalid"
            }
        };
        return;
    }
    
    // Si on arrive ici, token présent
    context.res = {
        status: 200,
        body: {
            message: "Authenticated successfully!",
            tokenLength: token.length,
            timestamp: new Date().toISOString()
        }
    };
};