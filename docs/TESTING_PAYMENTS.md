# Payment Integration Testing Checklist

Use this checklist to verify all payment integrations are working correctly.

## Pre-Testing Setup

- [ ] Backend server running (`npm run start:dev`)
- [ ] Database migrated (`npx prisma migrate dev`)
- [ ] Environment variables configured in `backend/.env`
- [ ] Ngrok tunnel started (`ngrok http 3000`)
- [ ] Webhook URLs updated with ngrok URL

## M-Pesa Daraja Testing

### Sandbox Credentials
- [ ] Consumer Key obtained from Daraja portal
- [ ] Consumer Secret obtained from Daraja portal
- [ ] Passkey obtained from Daraja portal
- [ ] Shortcode configured (174379 for sandbox)

### Test Flow
- [ ] Run test script: `npm run test:mpesa`
- [ ] STK Push initiated successfully
- [ ] Test phone receives prompt (254708374149)
- [ ] Enter test PIN: 1234
- [ ] Payment completes
- [ ] Callback received at `/api/v1/payments/mpesa/callback`
- [ ] Transaction status updated in database
- [ ] Receipt number stored

### Database Verification
```sql
SELECT * FROM mpesa_transactions ORDER BY created_at DESC LIMIT 5;
```

- [ ] Transaction record created
- [ ] Status = 'completed'
- [ ] mpesaReceiptNumber populated
- [ ] Amount matches

---

## PesaPal Testing

### Sandbox Credentials
- [ ] Consumer Key obtained from PesaPal dashboard
- [ ] Consumer Secret obtained from PesaPal dashboard
- [ ] IPN URL registered in PesaPal sandbox

### Test Flow
- [ ] Run test script: `npm run test:pesapal`
- [ ] Access token obtained successfully
- [ ] IPN registered
- [ ] Order submitted
- [ ] Redirect URL generated
- [ ] Open redirect URL in browser
- [ ] Pay with test card: 4242424242424242
- [ ] Expiry: Any future date, CVV: 123
- [ ] Payment completes
- [ ] IPN received at `/api/v1/payments/pesapal/ipn`
- [ ] Transaction status updated

### Database Verification
```sql
SELECT * FROM pesapal_transactions ORDER BY created_at DESC LIMIT 5;
```

- [ ] Transaction record created
- [ ] Status = 'completed'
- [ ] Payment method recorded
- [ ] Amount matches

---

## TouristTap Testing

### Sandbox Credentials
- [ ] API Key obtained from TouristTap
- [ ] Merchant ID obtained from TouristTap
- [ ] Callback URL configured

### Test Flow
- [ ] Run test script: `npm run test:touristtap`
- [ ] Payment initiated successfully
- [ ] Transaction reference generated
- [ ] Simulate NFC tap with test token: TEST_NFC_TOKEN_12345
- [ ] Payment confirmed
- [ ] Callback received at `/api/v1/payments/touristtap/callback`
- [ ] Transaction status updated

### Database Verification
```sql
SELECT * FROM touristtap_transactions ORDER BY created_at DESC LIMIT 5;
```

- [ ] Transaction record created
- [ ] Status = 'completed'
- [ ] Amount matches

---

## Webhook Testing

### Local Testing with Webhook Server

1. Start webhook server:
```bash
npm run test:webhook
```

2. In another terminal, start ngrok:
```bash
ngrok http 3333
```

3. Update callback URLs:
```env
DARAJA_CALLBACK_URL=https://abc123.ngrok.io/mpesa/callback
PESAPAL_IPN_URL=https://abc123.ngrok.io/pesapal/ipn
TOURISTTAP_CALLBACK_URL=https://abc123.ngrok.io/touristtap/callback
```

4. View received webhooks:
```bash
# Browser
http://localhost:3333/logs

# Or in terminal
curl http://localhost:3333/logs
```

- [ ] Webhook server running on port 3333
- [ ] Ngrok tunnel active
- [ ] Callback URLs updated
- [ ] Webhooks received and logged
- [ ] Logs viewable at `/logs` endpoint

---

## Integration Testing

### Mobile App Testing

- [ ] Mobile app configured with backend URL
- [ ] M-Pesa payment flow works
- [ ] PesaPal payment flow works
- [ ] TouristTap payment flow works
- [ ] Offline queue handles payment failures
- [ ] Sync works when back online

### End-to-End Sale Flow

1. Create sale in mobile app
2. Select payment method
3. Complete payment
4. Verify stock updated
5. Verify receipt generated
6. Verify transaction recorded

- [ ] Sale created successfully
- [ ] Payment method selected
- [ ] Payment processed
- [ ] Stock decremented
- [ ] Receipt generated
- [ ] Transaction recorded in database

---

## Production Readiness

### Security

- [ ] HTTPS enabled
- [ ] SSL certificates valid
- [ ] Webhook signature verification implemented
- [ ] Rate limiting configured
- [ ] JWT authentication required
- [ ] Secrets stored securely (Docker secrets/vault)

### Monitoring

- [ ] Payment success rate monitored
- [ ] Failed payment alerts configured
- [ ] Webhook timeout alerts configured
- [ ] Database transaction logs monitored

### Documentation

- [ ] Payment integration guide complete
- [ ] Troubleshooting guide complete
- [ ] API documentation updated
- [ ] Support contacts documented

---

## Troubleshooting Commands

```bash
# Check backend logs
docker-compose logs -f backend | grep -i payment

# Check database transactions
psql -U pos_user -d pos_system -c "SELECT * FROM mpesa_transactions WHERE status = 'failed';"

# Test webhook endpoint
curl -X POST http://localhost:3000/api/v1/payments/mpesa/callback \
  -H "Content-Type: application/json" \
  -d '{"test": true}'

# View webhook logs
cat backend/logs/webhooks.log

# Clear webhook logs
rm backend/logs/webhooks.log
```

---

## Sign-off

- [ ] All tests passed
- [ ] Documentation complete
- [ ] Team review completed
- [ ] Ready for production deployment

**Tested by:** ________________

**Date:** ________________

**Approved by:** ________________