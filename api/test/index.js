// Test fonction minimale
module.exports = async function (context, req) {
    context.log('Test function triggered');
    
    context.res = {
        status: 200,
        body: {
            message: "Hello from Azure Function",
            timestamp: new Date().toISOString()
        }
    };
};