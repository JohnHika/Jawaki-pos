# Paystack billing setup

Counterbase uses Paystack for the one-time KES 35,000 activation checkout and for
monthly subscription invoices. Checkout links are created by the backend;
Counterbase verifies the transaction with Paystack before activating a workspace or
marking an invoice paid.

## Vercel

Set `PAYSTACK_SECRET_KEY` in the production Vercel API environment. Use the
live secret key for live payments and keep it out of source control and the
mobile app. Set `PUBLIC_API_URL` to the public backend URL, or set these
callback values explicitly:

- `PAYSTACK_ACTIVATION_CALLBACK_URL=https://api.archeaxon.com/api/v1/tenant-activation/paystack/callback`
- `PAYSTACK_BILLING_CALLBACK_URL=https://api.archeaxon.com/api/v1/billing/paystack/callback`

## Paystack dashboard

Set the webhook URL to:

`https://api.archeaxon.com/api/v1/billing/paystack/webhook`

That single endpoint accepts activation and monthly invoice events. Paystack
signatures are checked against the raw request body, and successful invoice
events are verified directly against Paystack before settlement.

Enable the payment channels approved for the account in the Paystack
dashboard. Axon leaves channel selection to those dashboard settings for
activation and monthly invoice checkout.

## Monthly renewals

After a plan's trial or paid period ends, the backend creates its monthly
invoice. In **Settings → Subscription & Billing**, open the Paystack checkout
to pay that invoice. The callback returns to Axon, which verifies the payment
and refreshes the subscription. To use Paystack checkout for renewals, turn off
M-Pesa auto-renew before the invoice is created; an invoice with an active
M-Pesa prompt cannot start a second checkout at the same time.
