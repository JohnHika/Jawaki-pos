#!/usr/bin/env node

/**
 * PesaPal API Testing Script
 * Tests sandbox integration for payment orders and IPN handling
 */

const axios = require('axios');
require('dotenv').config();

const PESAPAL_ENV = process.env.PESAPAL_ENV || 'sandbox';
const BASE_URL = PESAPAL_ENV === 'production'
  ? 'https://pay.pesapal.com/v3'
  : 'https://cybqa.pesapal.com/pesapalv3';

const CONSUMER_KEY = process.env.PESAPAL_CONSUMER_KEY;
const CONSUMER_SECRET = process.env.PESAPAL_CONSUMER_SECRET;
const IPN_URL = process.env.PESAPAL_IPN_URL;

console.log('='.repeat(60));
console.log('PesaPal API Test');
console.log('='.repeat(60));
console.log(`Environment: ${PESAPAL_ENV}`);
console.log(`Base URL: ${BASE_URL}`);
console.log('='.repeat(60));

async function getAccessToken() {
  try {
    const response = await axios.post(
      `${BASE_URL}/api/Auth/RequestToken`,
      {
        consumer_key: CONSUMER_KEY,
        consumer_secret: CONSUMER_SECRET,
      },
      {
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
        },
      }
    );

    console.log('✅ Access token obtained');
    console.log('Token:', response.data.token?.substring(0, 20) + '...');
    console.log('Expires:', response.data.expiryDate);
    return response.data.token;
  } catch (error) {
    console.error('❌ Failed to get access token');
    console.error('Error:', error.response?.data || error.message);
    throw error;
  }
}

async function registerIPN(accessToken) {
  try {
    const response = await axios.post(
      `${BASE_URL}/api/URLSetup/RegisterIPN`,
      {
        url: IPN_URL || 'https://example.com/api/v1/payments/pesapal/ipn',
        ipn_notification_type: 'POST',
      },
      {
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
      }
    );

    console.log('✅ IPN registered');
    console.log('IPN ID:', response.data.ipn_id);
    return response.data.ipn_id;
  } catch (error) {
    console.error('❌ Failed to register IPN');
    console.error('Error:', error.response?.data || error.message);
    throw error;
  }
}

async function submitOrder(accessToken, ipnId) {
  try {
    const orderRequest = {
      id: `TEST_${Date.now()}`,
      currency: 'KES',
      amount: 100.00,
      description: 'Test Order Payment',
      callback_url: IPN_URL?.replace('/ipn', '/callback') || 'https://example.com/callback',
      notification_id: ipnId,
      billing_address: {
        email_address: 'test@example.com',
        phone_number: '254708374149',
        first_name: 'Test',
        last_name: 'User',
      },
    };

    console.log('\n🔄 Submitting order...');
    console.log('Request:', JSON.stringify(orderRequest, null, 2));

    const response = await axios.post(
      `${BASE_URL}/api/Transactions/SubmitOrderRequest`,
      orderRequest,
      {
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
      }
    );

    console.log('✅ Order submitted');
    console.log('Response:', JSON.stringify(response.data, null, 2));

    return {
      orderTrackingId: response.data.order_tracking_id,
      redirectUrl: response.data.redirect_url,
      merchantReference: response.data.merchant_reference,
    };
  } catch (error) {
    console.error('❌ Failed to submit order');
    console.error('Error:', error.response?.data || error.message);
    throw error;
  }
}

async function getTransactionStatus(accessToken, orderTrackingId) {
  try {
    console.log('\n🔄 Checking transaction status...');
    console.log('OrderTrackingId:', orderTrackingId);

    const response = await axios.get(
      `${BASE_URL}/api/Transactions/GetTransactionStatus?orderTrackingId=${orderTrackingId}`,
      {
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
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
    if (!CONSUMER_KEY || !CONSUMER_SECRET) {
      console.error('\n❌ Missing credentials!');
      console.log('\nPlease set the following in your .env file:');
      console.log('  PESAPAL_CONSUMER_KEY=your_key');
      console.log('  PESAPAL_CONSUMER_SECRET=your_secret');
      console.log('  PESAPAL_IPN_URL=https://your-domain.com/api/v1/payments/pesapal/ipn');
      console.log('\nGet sandbox credentials from: https://developer.pesapal.com');
      process.exit(1);
    }

    // Test 1: Get Access Token
    const accessToken = await getAccessToken();

    // Test 2: Register IPN
    const ipnId = await registerIPN(accessToken);

    // Test 3: Submit Order
    const { orderTrackingId, redirectUrl } = await submitOrder(accessToken, ipnId);

    // Test 4: Get Transaction Status
    if (orderTrackingId) {
      await new Promise(resolve => setTimeout(resolve, 2000)); // Wait 2 seconds
      await getTransactionStatus(accessToken, orderTrackingId);
    }

    console.log('\n' + '='.repeat(60));
    console.log('✅ All tests passed!');
    console.log('='.repeat(60));
    console.log('\n📋 Next Steps:');
    console.log('1. Open the redirect URL in browser to complete payment');
    console.log(`   URL: ${redirectUrl}`);
    console.log('2. Use test card: 4242424242424242 (Visa)');
    console.log('3. Expiry: Any future date, CVV: 123');
    console.log('4. Monitor IPN callback URL for notifications');
    console.log('5. Check database for transaction record');
    console.log('\n💡 Tips:');
    console.log('- Sandbox mode uses test payment methods');
    console.log('- IPN will be sent to your configured URL');
    console.log('- Use ngrok for local testing: ngrok http 3000');

  } catch (error) {
    console.error('\n❌ Tests failed');
    console.error(error.message);
    process.exit(1);
  }
}

runTests();