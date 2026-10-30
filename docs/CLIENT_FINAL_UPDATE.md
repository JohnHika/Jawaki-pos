# Axon POS — Final Project Update

**Date:** 13 October 2026
**Live release:** Axon POS Android 1.0.50 (build 2093), published 13 October 2026 — includes everything in section 2
**Server:** updated the same day; the new payment endpoints are live

---

## 1. Where things stand

The system is built and tested. Since the previous release (1.0.49, build 2092) we closed the remaining gaps from your original brief. Those changes are now **live on the server and published as Android 1.0.50 (build 2093)**. Staff phones pick up the update through the app's normal update check; it is not a forced update.

| Check (13 October, on the new code) | Result |
|---|---|
| Mobile static analysis | No issues found |
| Mobile tests | 162 / 162 passing (was 141) |
| Backend type-check | Clean |
| Backend tests | 154 / 154 passing (was 132) |
| Production API after the update | Healthy; the new payment routes are live and require sign-in |
| Release checks | Signing and version-lineage checks passed; build 2093 is newer than 2092 |

## 2. What was added in this final round

All four items from the original brief that were still open:

1. **Manual payment approval.** A cashier records a payment taken outside the app (bank transfer, cheque, other) with an amount and reason. A *different* person with approval rights approves or rejects it, and a rejection needs a reason. Nobody can approve their own request. Approving a request tied to a sale records a completed manual payment against that sale. Every step is written to the audit trail. Find it under **Payments → Manual Payments**.
2. **Bulk collection from customers.** In **Finance → Customer Credit**, "Collect for a customer" takes one payment and splits it across all of that customer's unpaid credits, oldest due first. It shows how many credits will be settled before you confirm and refuses more than the customer owes. The whole collection is saved all-or-nothing, and a dropped connection can't cause a double payment.
3. **Receipt search.** The Receipts list now has a search box. It finds a receipt by its code, receipt number, customer name, or phone number. Phone search works whether the number is typed as `0712…` or `+254712…`. Each receipt card now shows the customer's name.
4. **Held (pay-later) payments and receipt reprint.** These **already existed**, and we should have said so in our earlier draft. Held payments live in Finance → Customer Credit, with a Collect button on each credit. Receipts can be reprinted and shared from the receipt screen. Nothing new was needed beyond item 2 and item 3 above.

## 3. What the system does overall

- **Selling:** offline-first point of sale that syncs when the connection returns. Multi-unit products (bales/cartons) and batch/expiry tracking.
- **Payments:** cash, M-Pesa, credit (pay-later), manual payments with approval, and bulk collection.
- **Finance hub:** customer and other-shop receivables, supplier payables, cash flow, cash reconciliation, end-of-day.
- **Dashboard and reports:** sales, profit and loss, and a calendar to browse previous days.
- **Team and security:** staff invitations with status tracking, unique staff PINs, role-based permissions, audit trail.
- **AI assistant, subscription plans, and in-app updates with a feature tour.**

## 4. What we could not verify, and what to know

1. **The new features have been tested against a real PostgreSQL database, but not on a phone.** We applied every database migration to a fresh, disposable PostgreSQL and ran 32 checks on the new server code: bulk collection (balances, cash ledger, retry safety, rollback on a bad row, two collections at once, other-tenant access) and manual-payment approval (no self-approval, two approvers at once, completed payment recorded once, audit trail, who can see what). All passed in three consecutive runs. We then started the real server against that database and made 29 actual web requests to the new endpoints using the exact data the app sends: sign-in required, staff without approval rights are refused, bad or extra data is rejected, one person cannot approve their own request, another company's staff cannot touch your records, and a repeated bulk collection is not applied twice. All passed in three consecutive runs. We have **not** yet walked through the new screens on a real phone with real staff accounts. Please try the three new screens after updating (see question 1). Our testing never wrote anything to your live database.
2. **Calendar and audit trail on a real login.** We confirmed the code and endpoints but did not walk them through a live sign-in. Admins must sign out and back in once for the audit trail to work.
3. **Hosting cold starts.** The server runs on a free hosting tier that sleeps when idle. Our first health check timed out at 40 s while it woke up. Later requests were fast. The app retries automatically, but the first sale of the day can be slow.
4. **Who can approve manual payments.** The approval permission already exists in the system and is granted to administrator-level roles. Please confirm that is the right group (question 4).

## 5. Questions for you

1. **First look on a phone.** Can someone on your team update to 1.0.50 and try: (a) Payments → Manual Payments, (b) Finance → Customer Credit → "Collect for a customer", (c) the Receipts search box, and tell us if anything looks wrong? A test staff login would let us do this ourselves.
2. **Hosting.** Should we move the backend to a paid always-on plan to remove cold starts? (Recommended for a live shop. It carries a small monthly cost.)
3. **Payment go-live.** Which payment channels do you want live at launch: M-Pesa STK Push, PesaPal, TouristTap? Do you already have production credentials for each, or should we help you register?
4. **Approvers.** Who should be allowed to approve manual payments: owners/admins only, or managers and supervisors too?
5. **Branding.** Which business name should the app show to staff and on receipts: Levisa Adventures, Levisa Ventures, or Axon POS?
6. **Support contact.** Is `support@archeaxon.com` the right address for staff to reach support?
7. **Test access.** May we create a clearly-labelled test staff account in your live system so we can verify the new features, the calendar and the audit trail end to end? We will not do this without your say-so.
8. **Handover.** Do you want staff training, a written user guide, or both? Who will be the day-to-day administrator?
9. **Backups and monitoring.** Should we set up automated daily database backups and uptime alerts as part of closing out?
10. **Acceptance.** Is there anything you've seen in daily use that you consider unfinished? Please list it so we can fold it into the last release.

## 6. Proposed next steps

1. You answer the questions in section 5, especially 1, 3 and 7.
2. We fix anything found on first use and, if needed, ship a small follow-up release.
3. We hand over: admin accounts, documentation, and sign-off.
