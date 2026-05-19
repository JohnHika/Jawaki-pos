#!/usr/bin/env node

/**
 * Local Webhook Testing Server
 * Receives and logs payment webhooks for local development
 */

const express = require('express');
const bodyParser = require('body-parser');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = process.env.WEBHOOK_PORT || 3333;

// Ensure logs directory exists
const logsDir = path.join(__dirname, '..', 'logs');
if (!fs.existsSync(logsDir)) {
  fs.mkdirSync(logsDir, { recursive: true });
}

// Middleware
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

// Logging middleware
function logWebhook(source, data) {
  const timestamp = new Date().toISOString();
  const logEntry = {
    timestamp,
    source,
    data,
  };

  const logLine = JSON.stringify(logEntry, null, 2) + '\n';
  const logFile = path.join(logsDir, 'webhooks.log');

  fs.appendFile(logFile, logLine, (err) => {
    if (err) console.error('Failed to write log:', err);
  });

  console.log('\n' + '='.repeat(60));
  console.log(`[${timestamp}] ${source} Webhook Received`);
  console.log('='.repeat(60));
  console.log(JSON.stringify(data, null, 2));
  console.log('='.repeat(60) + '\n');
}

// M-Pesa Callback
app.post('/mpesa/callback', (req, res) => {
  logWebhook('M-Pesa', req.body);
  res.json({ ResultCode: 0, ResultDesc: 'Accepted' });
});

// M-Pesa C2B Confirmation
app.post('/mpesa/confirmation', (req, res) => {
  logWebhook('M-Pesa C2B', req.body);
  res.json({ ResultCode: 0, ResultDesc: 'Accepted' });
});

// PesaPal IPN
app.post('/pesapal/ipn', (req, res) => {
  logWebhook('PesaPal', req.body);
  res.json({ status: 'ok' });
});

// PesaPal Callback
app.get('/pesapal/callback', (req, res) => {
  logWebhook('PesaPal Callback', req.query);
  res.json({
    OrderTrackingId: req.query.OrderTrackingId,
    OrderMerchantReference: req.query.OrderMerchantReference,
    status: 'received',
  });
});

// TouristTap Callback
app.post('/touristtap/callback', (req, res) => {
  logWebhook('TouristTap', req.body);
  res.json({ status: 'ok' });
});

// Health check
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
  });
});

// View logs
app.get('/logs', (req, res) => {
  const logFile = path.join(logsDir, 'webhooks.log');
  if (fs.existsSync(logFile)) {
    const logs = fs.readFileSync(logFile, 'utf8');
    res.type('text/plain').send(logs);
  } else {
    res.send('No webhooks received yet.');
  }
});

// Clear logs
app.delete('/logs', (req, res) => {
  const logFile = path.join(logsDir, 'webhooks.log');
  if (fs.existsSync(logFile)) {
    fs.unlinkSync(logFile);
    res.json({ status: 'ok', message: 'Logs cleared' });
  } else {
    res.json({ status: 'ok', message: 'No logs to clear' });
  }
});

// Start server
app.listen(PORT, () => {
  console.log('='.repeat(60));
  console.log('Webhook Testing Server Started');
  console.log('='.repeat(60));
  console.log(`Port: ${PORT}`);
  console.log(`Logs: ${path.join(logsDir, 'webhooks.log')}`);
  console.log('='.repeat(60));
  console.log('\nEndpoints:');
  console.log('  POST /mpesa/callback      - M-Pesa STK callback');
  console.log('  POST /mpesa/confirmation   - M-Pesa C2B confirmation');
  console.log('  POST /pesapal/ipn          - PesaPal IPN');
  console.log('  GET  /pesapal/callback     - PesaPal redirect');
  console.log('  POST /touristtap/callback  - TouristTap callback');
  console.log('  GET  /health               - Health check');
  console.log('  GET  /logs                 - View webhook logs');
  console.log('  DELETE /logs               - Clear logs');
  console.log('\nUsage with ngrok:');
  console.log(`  ngrok http ${PORT}`);
  console.log('  Use the ngrok URL as your callback base URL');
  console.log('='.repeat(60));
});

// Handle errors
process.on('uncaughtException', (error) => {
  console.error('Uncaught Exception:', error);
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);
});