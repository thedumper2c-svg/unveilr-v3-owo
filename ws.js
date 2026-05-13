// Simple WebSocket server using 'ws' library
// Install with: npm install ws
// Run with: node server.js

const WebSocket = require('ws');

const server = new WebSocket.Server({ port: 8000 });

server.on('connection', (ws) => {
  console.log('Client connected');

  // Send a welcome message
  ws.send('Welcome to the WebSocket server!');

  // Send a message every 3 seconds
  const interval = setInterval(() => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(`Server message at ${new Date().toLocaleTimeString()}`);
    }
  }, 3000);

  // Handle incoming messages from client
  ws.on('message', (message) => {
    console.log('Received from client:', message.toString());
  });

  // Handle client disconnect
  ws.on('close', () => {
    console.log('Client disconnected');
    clearInterval(interval);
  });
});

console.log('WebSocket server is running on ws://localhost:8000');