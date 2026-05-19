#!/usr/bin/env node

/**
 * TouristTap NFC Payment Testing Script
 * Tests sandbox integration for NFC tap payments
 */

const axios = require('axios');
require('dotenv').config();

const TOURISTTAP_ENV = process.env.TOURISTTAP_ENV || 'sandbox';
const BASE_URL = 'https://api.touristtap.com/v1';

const API_KEY = process.env.TOURISTTAP_API_KEY;
const MERCHANT_ID = process.env.TOURISTTAP_MERCHANT_ID;
const CALLBACK_URL = process.env.TOURISTTAP_CALLBACK_URL;

console.log('='.repeat(60));
console.log('TouristTap NFC Payment Test');
console.log('='.repeat(60));
console.log(`Environment: ${TOURISTTAP_ENV}`);
console.log(`Base URL: ${BASE_URL}`);
console.log(`Merchant ID: ${MERCHANT_ID}`);
console.log('='.repeat(60));

async function initiatePayment() {
  try {
    const requestBody = {
      merchant_id: MERCHANT_ID,
      transaction_ref: `TT_TEST_${Date.now()}`,
      amount: 50.00,
      currency: 'KES',
      customer_ref: 'TEST_CUSTOMER_001',
      callback_url: CALLBACK_URL || 'https://example.com/api/v1/payments/touristtap/callback',
      timestamp: new Date().toISOString(),
    };

    console.log('\n🔄 Initiating payment...');
    console.log('Request:', JSON.stringify(requestBody, null, 2));

    const response = await axios.post(
      `${BASE_URL}/payments/initiate`,
      requestBody,
      {
        headers: {
          'X-API-Key': API_KEY,
          'Content-Type': 'application/json',
        },
      }
    );

    console.log('✅ Payment initiated');
    console.log('Response:', JSON.stringify(response.data, null, 2));

    return {
      transactionRef: response.data.transaction_ref,
      status: response.data.status,
    };
  } catch (error) {
    console.error('❌ Failed to initiate payment');
    console.error('Error:', error.response?.data || error.message);
    throw error;
  }
}

async function confirmPayment(transactionRef, nfcToken) {
  try {
    const requestBody = {
      merchant_id: MERCHANT_ID,
      transaction_ref: transactionRef,
      nfc_token: nfcToken,
    };

    console.log('\n🔄 Confirming payment...');
    console.log('TransactionRef:', transactionRef);
    console.log('NFCToken:', nfcToken);

    const response = await axios.post(
      `${BASE_URL}/payments/confirm`,
      requestBody,
      {
        headers: {
          'X-API-Key': API_KEY,
          'Content-Type': 'application/json',
        },
      }
    );

    console.log('✅ Payment confirmed');
    console.log('Response:', JSON.stringify(response.data, null, 2));

    return response.data;
  } catch (error) {
    console.error('❌ Failed to confirm payment');
    console.error('Error:', error.response?.data || error.message);
    throw error;
  }
}

async function getTransactionStatus(transactionRef) {
  try {
    console.log('\n🔄 Checking transaction status...');
    console.log('TransactionRef:', transactionRef);

    const response = await axios.get(
      `${BASE_URL}/payments/status/${transactionRef}`,
      {
        headers: {
          'X-API-Key': API_KEY,
        },
        params: {
          merchant_id: MERCHANT_ID,
        },
      }
    );

    console.log('✅ Status retrieved');
    console.log('Response:', JSON.stringify(response.data, null, 2));

    return response.data;
  } catch (error) {
    console.error('❌ Failed to get status');
    console.error('Error:', error.response?.data || error.message);
    throw error;
  }
}

async function runTests() {
  try {
    // Validate credentials
    if (!API_KEY || !MERCHANT_ID) {
      console.error('\n❌ Missing credentials!');
      console.log('\nPlease set the following in your .env file:');
      console.log('  TOURISTTAP_API_KEY=your_api_key');
      console.log('  TOURISTTAP_MERCHANT_ID=your_merchant_id');
      console.log('  TOURISTTAP_CALLBACK_URL=https://your-domain.com/api/v1/payments/touristtap/callback');
      console.log('\nGet credentials from: https://merchant.touristtap.com');
      process.exit(1);
    }

    // Test 1: Initiate Payment
    const { transactionRef } = await initiatePayment();

    // Test 2: Get Transaction Status
    if (transactionRef) {
      await new Promise(resolve => setTimeout(resolve, 2000)); // Wait 2 seconds
      await getTransactionStatus(transactionRef);
    }

    console.log('\n' + '='.repeat(60));
    console.log('✅ All tests passed!');
    console.log('='.repeat(60));
    console.log('\n📋 Next Steps:');
    console.log('1. Simulate NFC tap with test token');
    console.log('2. Use test NFC token: TEST_NFC_TOKEN_12345');
    console.log('3. Monitor callback URL for payment notification');
    console.log('4. Check database for transaction record');
    console.log('\n💡 Tips:');
    console.log('- TouristTap uses NFC-enabled cards/devices');
    console.log('- Test mode simulates NFC tap with test token');
    console.log('- Production requires physical NFC reader');

  } catch (error) {
    console.error('\n❌ Tests failed');
    console.error(error.message);
    process.exit(1);
  }
}

runTests();