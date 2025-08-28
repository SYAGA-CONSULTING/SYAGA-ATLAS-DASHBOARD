const { app } = require('@azure/functions');

app.http('message', {
    methods: ['GET', 'POST'],
    authLevel: 'anonymous',
    handler: async (request, context) => {
        context.log('Message function processed a request');
        return { 
            body: JSON.stringify({ 
                text: "Hello from Azure Functions!",
                timestamp: new Date().toISOString()
            })
        };
    }
});