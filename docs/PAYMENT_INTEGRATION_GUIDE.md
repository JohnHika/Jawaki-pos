# Payment Integration Guide

Complete guide for integrating M-Pesa (Daraja), PesaPal, and TouristTap NFC payments in the POS system.

## 📋 Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [M-Pesa Daraja Integration](#m-pesa-daraja-integration)
4. [PesaPal Integration](#pesapal-integration)
5. [TouristTap NFC Integration](#touristtap-nfc-integration)
6. [Testing Locally](#testing-locally)
7. [Production Deployment](#production-deployment)
8. [Troubleshooting](#troubleshooting)

---

## Overview

This POS system supports three payment methods:

| Payment Method | Type | Use Case |
|---------------|------|----------|
| **M-Pesa (Daraja)** | Mobile Money | Kenyan customers with M-Pesa accounts |
| **PesaPal** | Card/Mobile | International cards, multiple mobile money |
| **TouristTap** | NFC Contactless | Tourists with NFC-enabled cards/devices |

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Mobile POS App                            │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                 │
│  │  M-Pesa  │  │ PesaPal  │  │TouristTap│                 │
│  │  Button  │  │  Button  │  │  Button  │                 │
│  └─────┬────┘  └─────┬────┘  └─────┬────┘                 │
└────────┼─────────────┼─────────────┼───────────────────────┘
         │             │             │
         └─────────────┼─────────────┘
                       │
              ┌────────▼────────┐
              │  Backend API    │
              │  /payments/*     │
              └────────┬────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
   ┌────▼─────┐  ┌────▼─────┐  ┌────▼──────┐
   │  Daraja  │  │ PesaPal  │  │TouristTap │
   │  Service │  │  Service │  │  Service  │
   └────┬─────┘  └────┬─────┘  └────┬──────┘
        │              │              │
        └──────────────┼──────────────┘
                       │
              ┌────────▼────────┐
              │  Payment Gateway │
              │  (Safaricom/     │
              │   PesaPal/       │
              │   TouristTap)    │
              └──────────────────┘
```

---

## Prerequisites

### 1. Development Environment

```bash
# Install dependencies
cd backend
npm install

# Generate Prisma client
npx prisma generate

# Run database migrations
npx prisma migrate dev

# Start backend server
npm run start:dev
```

### 2. Ngrok (for local webhook testing)

```bash
# Install ngrok
# Windows: winget install ngrok.ngrok
# macOS: brew install ngrok
# Linux: sudo apt install ngrok

# Sign up at https://ngrok.com and get auth token
ngrok config add-authtoken YOUR_AUTH_TOKEN

# Start tunnel
ngrok http 3000
```

Note the HTTPS URL (e.g., `https://abc123.ngrok.io`) - this will be your webhook URL.

### 3. Payment Provider Accounts

#### M-Pesa Daraja
1. Visit https://developer.safaricom.co.ke
2. Create account and login
3. Go to "My Apps" → "Create New App"
4. Select "Lipa Na M-Pesa Sandbox" product
5. Copy Consumer Key and Consumer Secret
6. Get PassKey from: https://developer.safaricom.co.ke/lipa-na-m-pesa-online-payment

#### PesaPal
1. Visit https://developer.pesapal.com
2. Create merchant account
3. Get sandbox credentials from dashboard
4. Register IPN URL in sandbox

#### TouristTap
1. Contact TouristTap for merchant account
2. Get API Key and Merchant ID
3. Configure callback URL

---

## M-Pesa Daraja Integration

### Configuration

Add to `backend/.env`:

```env
# Daraja (M-Pesa) Configuration
DARAJA_ENV=sandbox
DARAJA_CONSUMER_KEY=your_consumer_key_here
DARAJA_CONSUMER_SECRET=your_consumer_secret_here
DARAJA_PASSKEY=your_passkey_here
DARAJA_SHORTCODE=174379
DARAJA_CALLBACK_URL=https://your-domain.com/api/v1/payments/mpesa/callback
```

### Test Credentials (Sandbox)

| Field | Value |
|-------|-------|
| Shortcode | 174379 |
| Test MSISDN | 254708374149 |
| Test PIN | 1234 |

### Test Script

```bash
# Run M-Pesa test
cd backend
node scripts/test-mpesa.js
```

### Expected Flow

```
1. POS initiates STK Push
   ↓
2. Customer receives prompt on phone
   ↓
3. Customer enters PIN (1234 for sandbox)
   ↓
4. Payment processed
   ↓
5. Callback received at /api/v1/payments/mpesa/callback
   ↓
6. Transaction record updated in database
   ↓
7. POS polls status or receives webhook
```

### Database Schema

```sql
-- mpesa_transactions table
id                  UUID PRIMARY KEY
merchantRequestId   VARCHAR UNIQUE
checkoutRequestId   VARCHAR UNIQUE
phoneNumber          VARCHAR
amount              DECIMAL(10,2)
accountReference    VARCHAR
transactionDesc     VARCHAR
resultCode          INT
resultDesc          VARCHAR
mpesaReceiptNumber  VARCHAR
transactionDate     TIMESTAMP
status              VARCHAR DEFAULT 'pending'
callbackPayload     JSON
createdAt           TIMESTAMP
updatedAt           TIMESTAMP
```

### API Endpoints

#### Initiate STK Push

```http
POST /api/v1/payments/mpesa/stkpush
Authorization: Bearer {jwt_token}
Content-Type: application/json

{
  "phoneNumber": "254708374149",
  "amount": 100,
  "accountReference": "SALE-123",
  "transactionDesc": "Payment for goods"
}
```

**Response:**
```json
{
  "success": true,
  "transactionId": "ws_CO_123456789",
  "message": "STK push sent successfully"
}
```

#### Query Status

```http
GET /api/v1/payments/mpesa/status/{checkoutRequestId}
Authorization: Bearer {jwt_token}
```

**Response:**
```json
{
  "transactionId": "ws_CO_123456789",
  "status": "completed",
  "amount": 100,
  "paidAt": "2024-01-15T10:30:00Z",
  "receiptNumber": "QEG4R5TYUO"
}
```

### Mobile App Integration

```dart
// mobile/lib/features/sales/presentation/providers/payment_provider.dart

Future<void> initiateMpesaPayment(String phoneNumber, double amount) async {
  try {
    final response = await _apiClient.post('/payments/mpesa/stkpush', {
      'phoneNumber': phoneNumber,
      'amount': amount,
      'accountReference': currentSale.id,
      'transactionDesc': 'POS Sale ${currentSale.id}',
    });

    final transactionId = response['transactionId'];

    // Poll for status every 3 seconds
    for (int i = 0; i < 20; i++) {
      await Future.delayed(Duration(seconds: 3));

      final status = await _apiClient.get(
        '/payments/mpesa/status/$transactionId',
      );

      if (status['status'] == 'completed') {
        // Payment successful - complete sale
        await completeSale(transactionId);
        return;
      } else if (status['status'] == 'failed') {
        throw Exception('Payment failed');
      }
    }

    throw Exception('Payment timeout');
  } catch (e) {
    throw Exception('M-Pesa payment failed: $e');
  }
}
```

---

## PesaPal Integration

### Configuration

Add to `backend/.env`:

```env
# PesaPal Configuration
PESAPAL_ENV=sandbox
PESAPAL_CONSUMER_KEY=your_consumer_key_here
PESAPAL_CONSUMER_SECRET=your_consumer_secret_here
PESAPAL_IPN_URL=https://your-domain.com/api/v1/payments/pesapal/ipn
```

### Test Card Details (Sandbox)

| Card Type | Number | Expiry | CVV |
|-----------|--------|--------|-----|
| Visa | 4242424242424242 | Any future date | 123 |
| Mastercard | 5555555555554444 | Any future date | 123 |

### Test Script

```bash
# Run PesaPal test
cd backend
node scripts/test-pesapal.js
```

### Expected Flow

```
1. POS initiates payment order
   ↓
2. PesaPal returns redirect URL
   ↓
3. Customer redirected to PesaPal checkout page
   ↓
4. Customer pays with card/mobile money
   ↓
5. IPN notification sent to /api/v1/payments/pesapal/ipn
   ↓
6. Transaction record updated
   ↓
7. Customer redirected to callback URL
```

### API Endpoints

#### Initiate Payment

```http
POST /api/v1/payments/pesapal/initiate
Authorization: Bearer {jwt_token}
Content-Type: application/json

{
  "amount": 100.00,
  "currency": "KES",
  "description": "POS Sale #123",
  "email": "customer@example.com",
  "phoneNumber": "254708374149",
  "firstName": "John",
  "lastName": "Doe",
  "merchantReference": "SALE-123"
}
```

**Response:**
```json
{
  "success": true,
  "transactionId": "e5f6g7h8i9j0",
  "checkoutUrl": "https://cybqa.pesapal.com/pay/e5f6g7h8i9j0",
  "message": "Redirect user to checkout URL"
}
```

#### Query Status

```http
GET /api/v1/payments/pesapal/status/{orderTrackingId}
Authorization: Bearer {jwt_token}
```

---

## TouristTap NFC Integration

### Configuration

Add to `backend/.env`:

```env
# TouristTap Configuration
TOURISTTAP_API_KEY=your_api_key_here
TOURISTTAP_MERCHANT_ID=your_merchant_id_here
TOURISTTAP_CALLBACK_URL=https://your-domain.com/api/v1/payments/touristtap/callback
```

### Test NFC Token (Sandbox)

| Token | Description |
|-------|-------------|
| TEST_NFC_TOKEN_12345 | Test token for sandbox |

### Test Script

```bash
# Run TouristTap test
cd backend
node scripts/test-touristtap.js
```

### Expected Flow

```
1. POS initiates NFC payment
   ↓
2. Customer taps NFC card/device
   ↓
3. NFC reader sends token to POS
   ↓
4. POS confirms payment with token
   ↓
5. Payment processed
   ↓
6. Callback received at /api/v1/payments/touristtap/callback
   ↓
7. Transaction record updated
```

### Hardware Requirements

For production:

1. **NFC Reader**: Contact TouristTap for certified readers
2. **POS Integration**: USB or Bluetooth connection
3. **Network**: Stable internet for payment processing

### API Endpoints

#### Initiate Payment

```http
POST /api/v1/payments/touristtap/initiate
Authorization: Bearer {jwt_token}
Content-Type: application/json

{
  "transactionRef": "SALE-123",
  "amount": 50.00,
  "currency": "KES",
  "customerRef": "CUST-001"
}
```

#### Confirm Payment

```http
POST /api/v1/payments/touristtap/confirm
Authorization: Bearer {jwt_token}
Content-Type: application/json

{
  "transactionRef": "SALE-123",
  "nfcToken": "TEST_NFC_TOKEN_12345"
}
```

---

## Testing Locally

### 1. Start Backend Server

```bash
cd backend
npm run start:dev
```

### 2. Start Ngrok Tunnel

```bash
# Terminal 2
ngrok http 3000
```

Copy the HTTPS URL (e.g., `https://abc123.ngrok.io`)

### 3. Update Webhook URLs

Update `backend/.env`:

```env
DARAJA_CALLBACK_URL=https://abc123.ngrok.io/api/v1/payments/mpesa/callback
PESAPAL_IPN_URL=https://abc123.ngrok.io/api/v1/payments/pesapal/ipn
TOURISTTAP_CALLBACK_URL=https://abc123.ngrok.io/api/v1/payments/touristtap/callback
```

### 4. Run Test Scripts

```bash
# Test M-Pesa
node scripts/test-mpesa.js

# Test PesaPal
node scripts/test-pesapal.js

# Test TouristTap
node scripts/test-touristtap.js
```

### 5. Monitor Webhooks

```bash
# Terminal 3 - Watch backend logs
tail -f backend/logs/combined.log | grep -i payment

# Or use ngrok web interface
# Open http://localhost:4040 in browser
```

---

## Production Deployment

### 1. SSL/TLS Certificates

```bash
# Generate Let's Encrypt certificate
sudo certbot certonly --standalone -d your-domain.com

# Copy to nginx/ssl/
sudo cp /etc/letsencrypt/live/your-domain.com/fullchain.pem nginx/ssl/cert.pem
sudo cp /etc/letsencrypt/live/your-domain.com/privkey.pem nginx/ssl/key.pem
```

### 2. Update Environment Variables

```bash
# backend/.env.production
DARAJA_ENV=production
DARAJA_CALLBACK_URL=https://your-domain.com/api/v1/payments/mpesa/callback

PESAPAL_ENV=production
PESAPAL_IPN_URL=https://your-domain.com/api/v1/payments/pesapal/ipn

TOURISTTAP_CALLBACK_URL=https://your-domain.com/api/v1/payments/touristtap/callback
```

### 3. Firewall Configuration

```bash
# Allow only HTTP/HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw deny 3000/tcp
sudo ufw enable
```

### 4. Rate Limiting

Payment endpoints are already rate-limited in `app.module.ts`:

```typescript
ThrottlerModule.forRoot([
  {
    ttl: 60000,  // 1 minute
    limit: 100,  // 100 requests per minute
  },
])
```

### 5. Monitoring

```bash
# Monitor payment transactions
docker-compose logs -f backend | grep -i payment

# Check failed transactions
psql -U pos_user -d pos_system -c "SELECT * FROM mpesa_transactions WHERE status = 'failed';"
```

---

## Troubleshooting

### M-Pesa Issues

#### "Invalid credentials" error
- Verify Consumer Key and Secret from Daraja portal
- Check if app is approved in sandbox
- Ensure correct environment (sandbox vs production)

#### STK Push not received
- Check phone number format (254XXXXXXXXX)
- Verify shortcode and passkey
- Check callback URL is accessible from internet

#### Callback not received
- Use ngrok for local testing
- Verify callback URL in Daraja portal
- Check backend logs for errors

### PesaPal Issues

#### "Invalid consumer key" error
- Verify credentials from PesaPal dashboard
- Check environment (sandbox vs production)

#### IPN not received
- Register IPN URL in PesaPal dashboard
- Verify URL is publicly accessible
- Check firewall allows POST requests

### TouristTap Issues

#### "Invalid API key" error
- Contact TouristTap support for valid credentials
- Verify merchant ID matches account

#### NFC reader not detected
- Install NFC reader drivers
- Check USB/Bluetooth connection
- Verify reader is TouristTap certified

### Database Issues

#### Transaction not found
```sql
-- Check recent transactions
SELECT * FROM mpesa_transactions
ORDER BY created_at DESC
LIMIT 10;

-- Check failed transactions
SELECT * FROM mpesa_transactions
WHERE status = 'failed';
```

#### Duplicate transactions
```sql
-- Find duplicates
SELECT checkoutRequestId, COUNT(*)
FROM mpesa_transactions
GROUP BY checkoutRequestId
HAVING COUNT(*) > 1;
```

---

## Security Checklist

- [ ] HTTPS enabled for all payment endpoints
- [ ] Webhook signature verification implemented
- [ ] Rate limiting configured
- [ ] JWT authentication required for all payment endpoints
- [ ] Transaction amounts validated
- [ ] Phone numbers validated and formatted
- [ ] SQL injection prevention (Prisma parameterized queries)
- [ ] Logs sanitized of sensitive data
- [ ] Database encrypted at rest
- [ ] Secrets stored in Docker secrets or vault

---

## Support

### M-Pesa Daraja
- Documentation: https://developer.safaricom.co.ke/docs
- Support: developer@safaricom.co.ke

### PesaPal
- Documentation: https://developer.pesapal.com/docs
- Support: support@pesapal.com

### TouristTap
- Contact: Contact TouristTap representative

### Internal Support
- Check logs: `docker-compose logs -f backend`
- Database queries: See troubleshooting section
- Security issues: security@your-domain.com