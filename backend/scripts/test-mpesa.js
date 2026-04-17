#!/usr/bin/env node

/**
 * M-Pesa Daraja API Testing Script
 * Tests sandbox integration for STK Push and callback handling
 */

const axios = require('axios');
require('dotenv').config();

const DARAJA_ENV = process.env.DARAJA_ENV || 'sandbox';
const BASE_URL = DARAJA_ENV === 'production'
  ? 'https://api.safaricom.co.ke'
  : 'https://sandbox.safaricom.co.ke';

const CONSUMER_KEY = process.env.DARAJA_CONSUMER_KEY;
const CONSUMER_SECRET = process.env.DARAJA_CONSUMER_SECRET;
const SHORTCODE = process.env.DARAJA_SHORTCODE || '174379';
const PASSKEY = process.env.DARAJA_PASSKEY;
const CALLBACK_URL = process.env.DARAJA_CALLBACK_URL;

console.log('='.repeat(60));
console.log('M-Pesa Daraja API Test');
console.log('='.repeat(60));
console.log(`Environment: ${DARAJA_ENV}`);
console.log(`Base URL: ${BASE_URL}`);
console.log(`Shortcode: ${SHORTCODE}`);
console.log('='.repeat(60));

async function getAccessToken() {
  try {
    const auth = Buffer.from(`${CONSUMER_KEY}:${CONSUMER_SECRET}`).toString('base64');

    const response = await axios.get(
      `${BASE_URL}/oauth/v1/generate?grant_type=client_credentials`,
      {
        headers: {
          Authorization: `Basic ${auth}`,
        },
      }
    );

    console.log('✅ Access token obtained');
    return response.data.access_token;
  } catch (error) {
    console.error('❌ Failed to get access token');
    console.error('Error:', error.response?.data || error.message);
    throw error;
  }
}

function getTimestamp() {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  const hours = String(now.getHours()).padStart(2, '0');
  const minutes = String(now.getMinutes()).padStart(2, '0');
  const seconds = String(now.getSeconds()).padStart(2, '0');
  return `${year}${month}${day}${hours}${minutes}${seconds}`;
}

function generatePassword(timestamp) {
  const data = `${SHORTCODE}${PASSKEY}${timestamp}`;
  return Buffer.from(data).toString('base64');
}

async function testSTKPush(accessToken) {
  try {
    const timestamp = getTimestamp();
    const password = generatePassword(timestamp);

    const requestBody = {
      BusinessShortCode: SHORTCODE,
      Password: password,
      Timestamp: timestamp,
      TransactionType: 'CustomerPayBillOnline',
      Amount: 1, // Test with 1 KES
      PartyA: '254708374149', // Sandbox test number
      PartyB: SHORTCODE,
      PhoneNumber: '254708374149',
      CallBackURL: CALLBACK_URL || 'https://example.com/callback',
      AccountReference: 'TEST_ACCOUNT_001',
      TransactionDesc: 'Test Payment',
    };

    console.log('\n🔄 Testing STK Push...');
    console.log('Request:', JSON.stringify(requestBody, null, 2));

    const response = await axios.post(
      `${BASE_URL}/mpesa/stkpush/v1/processrequest`,
      requestBody,
      {
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
      }
    );

    console.log('✅ STK Push successful');
    console.log('Response:', JSON.stringify(response.data, null, 2));

    return {
      merchantRequestId: response.data.MerchantRequestID,
      checkoutRequestId: response.data.CheckoutRequestID,
    };
  } catch (error) {
    console.error('❌ STK Push failed');
    console.error('Error:', error.response?.data || error.message);
    throw error;
  }
}

async function testSTKQuery(accessToken, checkoutRequestId) {
  try {
    const timestamp = getTimestamp();
    const password = generatePassword(timestamp);

    const requestBody = {
      BusinessShortCode: SHORTCODE,
      Password: password,
      Timestamp: timestamp,
      CheckoutRequestID: checkoutRequestId,
    };

    console.log('\n🔄 Testing STK Query...');
    console.log('CheckoutRequestID:', checkoutRequestId);

    const response = await axios.post(
      `${BASE_URL}/mpesa/stkpushquery/v1/query`,
      requestBody,
      {
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
      }
    );

    console.log('✅ STK Query successful');
    console.log('Response:', JSON.stringify(response.data, null, 2));

    return response.data;
  } catch (error) {
    console.error('❌ STK Query failed');
    console.error('Error:', error.response?.data || error.message);
    throw error;
  }
}

async function runTests() {
  try {
    // Validate credentials
    if (!CONSUMER_KEY || !CONSUMER_SECRET || !PASSKEY) {
      console.error('\n❌ Missing credentials!');
      console.log('\nPlease set the following in your .env file:');
      console.log('  DARAJA_CONSUMER_KEY=your_key');
      console.log('  DARAJA_CONSUMER_SECRET=your_secret');
      console.log('  DARAJA_PASSKEY=your_passkey');
      console.log('\nGet sandbox credentials from: https://developer.safaricom.co.ke');
      process.exit(1);
    }

    // Test 1: Get Access Token
    const accessToken = await getAccessToken();

    // Test 2: STK Push
    const { checkoutRequestId } = await testSTKPush(accessToken);

    // Test 3: Query Status
    if (checkoutRequestId) {
      await new Promise(resolve => setTimeout(resolve, 2000)); // Wait 2 seconds
      await testSTKQuery(accessToken, checkoutRequestId);
    }

    console.log('\n' + '='.repeat(60));
    console.log('✅ All tests passed!');
    console.log('='.repeat(60));
    console.log('\n📋 Next Steps:');
    console.log('1. Check your phone for the STK push (sandbox mode)');
    console.log('2. Enter PIN 1234 to complete test payment');
    console.log('3. Monitor callback URL for payment notification');
    console.log('4. Check database for transaction record');
    console.log('\n💡 Tips:');
    console.log('- Use sandbox test number: 254708374149');
    console.log('- Default PIN: 1234');
    console.log('- Callback will be sent to your configured URL');

  } catch (error) {
    console.error('\n❌ Tests failed');
    console.error(error.message);
    process.exit(1);
  }
}

runTests();