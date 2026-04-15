#!/usr/bin/env node
/**
 * Generate cryptographically secure secrets for JWT and API keys
 * Usage: node scripts/generate-secrets.js
 */

const crypto = require('crypto');

function generateSecret(length = 64) {
  return crypto.randomBytes(length).toString('base64').slice(0, length);
}

function generatePassword(length = 32) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*';
  let password = '';
  for (let i = 0; i < length; i++) {
    password += chars[crypto.randomInt(chars.length)];
  }
  return password;
}

console.log('\n=== Secure Secrets for POS System ===\n');
console.log('JWT_SECRET=' + generateSecret(64));
console.log('JWT_REFRESH_SECRET=' + generateSecret(64));
console.log('NEXTAUTH_SECRET=' + generateSecret(64));
console.log('REDIS_PASSWORD=' + generatePassword(32));
console.log('POSTGRES_PASSWORD=' + generatePassword(32));
console.log('\n=== API Keys (from providers) ===\n');
console.log('DARAJA_CONSUMER_KEY=       # Get from Safaricom Developer Portal');
console.log('DARAJA_CONSUMER_SECRET=    # Get from Safaricom Developer Portal');
console.log('DARAJA_PASSKEY=            # Get from Safaricom Developer Portal');
console.log('PESAPAL_CONSUMER_KEY=      # Get from PesaPal Dashboard');
console.log('PESAPAL_CONSUMER_SECRET=   # Get from PesaPal Dashboard');
console.log('TOURISTTAP_API_KEY=        # Get from TouristTap Portal');
console.log('\n=== Instructions ===\n');
console.log('1. Copy these values to your .env files');
console.log('2. NEVER commit .env files to git');
console.log('3. Use different secrets for dev/staging/production');
console.log('4. Rotate secrets every 90 days minimum');
console.log('\n');
