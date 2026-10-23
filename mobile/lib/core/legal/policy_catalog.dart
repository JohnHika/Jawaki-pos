class PolicySection {
  const PolicySection(this.title, this.body);

  final String title;
  final String body;
}

class PolicyDocument {
  const PolicyDocument({
    required this.slug,
    required this.type,
    required this.title,
    required this.version,
    required this.summary,
    required this.sections,
  });

  final String slug;
  final String type;
  final String title;
  final String version;
  final String summary;
  final List<PolicySection> sections;
}

const kPolicyEffectiveDate = '22 October 2026';
const kPolicyContactEmail = 'support@archeaxon.com';

const kPolicyVersions = <String, String>{
  'TERMS_OF_SERVICE': '2026-10-22-v1',
  'PRIVACY_NOTICE': '2026-10-22-v1',
  'DATA_PROCESSING_ADDENDUM': '2026-10-22-v1',
  'BILLING_TERMS': '2026-10-22-v1',
  'AUTO_RENEWAL_AUTHORIZATION': '2026-10-22-v1',
  'MERCHANT_PAYMENT_TERMS': '2026-10-22-v1',
};

const kSignupPolicyTypes = <String>[
  'TERMS_OF_SERVICE',
  'PRIVACY_NOTICE',
  'DATA_PROCESSING_ADDENDUM',
];

String policyVersion(String type) => kPolicyVersions[type] ?? '';

const kPolicyDocuments = <PolicyDocument>[
  PolicyDocument(
    slug: 'terms',
    type: 'TERMS_OF_SERVICE',
    title: 'Terms of Service',
    version: '2026-10-22-v1',
    summary: 'Rules for using Counterbase for your business.',
    sections: [
      PolicySection('1. Who these terms cover',
          'These Terms of Service are between you and Arche Axon, the provider of Counterbase. If you create a workspace for a business, you confirm that you are allowed to act for that business. These terms apply to workspace owners and invited users.'),
      PolicySection('2. The service',
          'Counterbase provides point-of-sale, inventory, customer, reporting, team, and related business tools. Features depend on the selected plan, your device, connectivity, and any third-party service used. Counterbase is software; it is not a bank, lender, tax adviser, or seller of the goods you list.'),
      PolicySection('3. Your workspace and users',
          'You are responsible for accurate workspace details, choosing staff roles carefully, protecting passwords and PINs, reviewing activity, and removing access when it is no longer needed. You remain responsible for transactions and changes made by people you authorize.'),
      PolicySection('4. Your business and customer records',
          'You retain your rights in the products, prices, sales, stock, customer, supplier, and other business information you enter. You authorize Counterbase to host and process that information to provide the service, protect it, support your workspace, and carry out your documented instructions. You are responsible for having a lawful basis and giving your own customers any notices required for information you collect about them.'),
      PolicySection('5. Plans and billing',
          'Workspace activation currently costs KES 35,000 once. After activation, a seven-day trial applies. The monthly plan price shown before you select a plan is KES 3,200 for Core, KES 6,500 for Business, or KES 10,000 for Enterprise. Your selected plan and invoice show the applicable amount and period. Plan features and prices may change with notice before a change affects a future billing period.'),
      PolicySection('6. Renewal and payment',
          'Monthly invoices are raised for the selected plan. You can pay an invoice using an available checkout or the manual payment method shown in the app. Optional Auto-Renew sends an M-Pesa STK prompt to the billing number you choose. An STK prompt is not a silent debit: the person holding that phone must approve each prompt in M-Pesa. Auto-Renew is off for new workspaces until an owner enables it and accepts the separate Auto-Renew Authorization.'),
      PolicySection('7. Cancelling and overdue invoices',
          'Turn Auto-Renew off in Plan & Billing to stop future automatic STK prompts; you can continue paying invoices manually. Turning it off does not cancel an invoice already issued or reverse a completed payment. An unpaid invoice may restrict the workspace after the in-app grace period. To close a workspace or ask us to stop service, email support@archeaxon.com. We will explain any outstanding invoice and the data export or deletion options that apply.'),
      PolicySection('8. Refunds',
          'If you believe a payment was duplicated, incorrect, or otherwise should be reviewed, send the payment reference and workspace details to support@archeaxon.com. We review refund requests under applicable law and the relevant payment provider’s processing rules. A request is not approved until we confirm it. This section does not limit rights that cannot be excluded by law.'),
      PolicySection('9. Payments for goods sold by your shop',
          'Your shop is responsible for the goods and services it sells, its prices, taxes, receipts, returns, refunds, customer communications, and disputes. When you enable Paystack merchant payments, Paystack processes the customer payment and settlement under its own terms. Counterbase does not become the seller or merchant of record for your shop.'),
      PolicySection('10. Acceptable use and availability',
          'Do not use Counterbase to break the law, access another workspace without permission, interfere with the service, or upload information you have no right to use. We may suspend access when needed to protect users, investigate abuse, comply with law, or address an unpaid account, and will give notice where reasonably possible. We work to keep the service available but cannot promise uninterrupted access; offline features and later sync can be affected by device or network conditions.'),
      PolicySection('11. Intellectual property and feedback',
          'Arche Axon and its licensors own Counterbase and its software, brands, and service materials. We grant your workspace a limited, non-exclusive right to use the service while your account is active and these terms are followed. You may send feedback; we may use it to improve the service without paying for it.'),
      PolicySection('12. Ending service and data',
          'You can ask to close your workspace through support@archeaxon.com. After closure, we will make business data available for export for a reasonable period where technically possible, then delete or de-identify it subject to legal, security, accounting, backup, and dispute-resolution obligations. Some records may have to be kept where law requires.'),
      PolicySection('13. Changes and contact',
          'We may update these terms when the service or law changes. We will show the current version in the app and ask you to accept a new version when required. Questions or complaints about Counterbase can be sent to support@archeaxon.com. These terms are governed by the laws applicable in Kenya, subject to mandatory consumer protections.'),
    ],
  ),
  PolicyDocument(
    slug: 'privacy',
    type: 'PRIVACY_NOTICE',
    title: 'Privacy Notice',
    version: '2026-10-22-v1',
    summary: 'What information Counterbase handles and how to exercise your rights.',
    sections: [
      PolicySection('1. About this notice',
          'Arche Axon provides Counterbase. For workspace accounts, billing, security, and support information, Arche Axon decides why and how that information is used. For retail customer and business records that a shop enters into Counterbase, the shop generally decides the purpose and Counterbase processes the information to provide the software.'),
      PolicySection('2. Information we handle',
          'This can include workspace and branch names and contact details; owner and staff names, email addresses, phone numbers, credentials and role assignments; products, stock, sales, expenses, supplier records, and audit activity; customer names, contact details, debts, and purchase history entered by a shop; device and diagnostic information; and billing invoices, references, payment status, and subscription settings. For a shop payout account, the bank account number is sent to Paystack for account setup. Counterbase keeps the Paystack subaccount code and masked bank details, including the last four digits, rather than the full account number.'),
      PolicySection('3. What we use it for',
          'We use information to create and secure accounts, run sales and inventory tools, sync data between authorized devices, provide billing and payment routing, send account and verification messages, answer support requests, prevent fraud and misuse, diagnose failures, and meet legal obligations. Optional AI features process the content needed to answer the request made in that feature.'),
      PolicySection('4. When information is shared',
          'We share only what is needed with service providers that host the app and database, deliver email or notifications, store uploaded files, provide optional AI features, or process payments. Paystack receives payment information needed for checkout, verification, and merchant payout setup. Providers may change as the service develops; ask support@archeaxon.com for the current provider details. We may also disclose information where law requires or to protect users and the service.'),
      PolicySection('5. Processing for shops',
          'A shop controls the personal information it collects about its own customers and staff. The shop must decide what to collect, provide its own privacy notice where required, and respond to its customers’ requests. Counterbase uses that information only to provide the shop’s workspace and related support, subject to the Data Processing Addendum.'),
      PolicySection('6. Transfers and security',
          'Some service providers may process or store information outside Kenya. Where that happens, we use safeguards intended to protect the information and handle transfers in accordance with applicable data-protection rules. We use technical and organizational safeguards appropriate to the service, including access controls and protected connections. No online service can guarantee absolute security.'),
      PolicySection('7. Retention',
          'We keep information for as long as needed to provide the service, maintain accounting and security records, resolve disputes, and comply with law. On workspace closure, business data can be exported where available and is then deleted or de-identified under our retention and backup processes, except where a longer period is required or permitted by law.'),
      PolicySection('8. Your privacy rights',
          'Depending on the applicable law and the information involved, you may ask for access, correction, deletion, restriction, or objection to processing, or withdraw consent where processing relies on consent. For information held in a shop workspace, contact that shop first; we will support the shop as its processor. To contact Arche Axon, email support@archeaxon.com. You may also contact Kenya’s Office of the Data Protection Commissioner through odpc.go.ke.'),
      PolicySection('9. Updates and contact',
          'We publish and update this notice when our information practices change. The version and effective date appear above. Send privacy questions or rights requests to support@archeaxon.com.'),
    ],
  ),
  PolicyDocument(
    slug: 'data-processing',
    type: 'DATA_PROCESSING_ADDENDUM',
    title: 'Data Processing Addendum',
    version: '2026-10-22-v1',
    summary: 'How Counterbase processes shop customer and staff data for a workspace.',
    sections: [
      PolicySection('1. Roles',
          'For information a shop enters about its own retail customers, staff, suppliers, and business operations, the shop is the controller and Arche Axon is the processor. For Counterbase account administration, billing, security, and support records, Arche Axon may act as an independent controller as described in the Privacy Notice.'),
      PolicySection('2. Instructions and purposes',
          'Arche Axon processes workspace data to host, secure, sync, back up, support, and provide the Counterbase features the shop uses, and on the shop’s documented instructions in the app or support channel. The shop is responsible for ensuring its instructions and collection of information are lawful.'),
      PolicySection('3. Confidentiality and safeguards',
          'Arche Axon limits staff access to authorized purposes and uses reasonable technical and organizational safeguards to protect workspace data against unauthorized access, loss, or alteration. The shop must protect its own devices, passwords, PINs, staff permissions, and exported files.'),
      PolicySection('4. Service providers and transfers',
          'Arche Axon may use hosting, database, payment, email, notification, file-storage, and optional AI providers to operate features. We require providers to protect information appropriate to their role and use. Some providers may process data outside Kenya; applicable transfer safeguards are used where required. Current provider details are available from support@archeaxon.com.'),
      PolicySection('5. Requests and incidents',
          'Arche Axon will provide reasonable assistance so a shop can respond to a data-subject request involving workspace data, subject to the available service features and applicable law. We will notify the affected shop without undue delay if we become aware of a security incident affecting its workspace data, and provide information reasonably needed for the shop to respond.'),
      PolicySection('6. Return and deletion',
          'When a workspace closes, the shop can request an export of available workspace data. Arche Axon will delete or de-identify data under its retention and backup processes after the service ends, except for records required for legal compliance, security, accounting, or dispute resolution.'),
      PolicySection('7. Shop responsibilities',
          'The shop decides which personal information to enter, limits it to what is needed, gives required notices to its customers and staff, sets suitable user permissions, and responds to requests it receives as controller. The shop should not enter bank passwords, M-Pesa PINs, or one-time passwords into Counterbase.'),
    ],
  ),
  PolicyDocument(
    slug: 'billing',
    type: 'BILLING_TERMS',
    title: 'Subscription, Billing & Refunds',
    version: '2026-10-22-v1',
    summary: 'Activation, trial, monthly prices, invoice payment, and refund requests.',
    sections: [
      PolicySection('Activation and trial',
          'The one-time workspace activation payment is KES 35,000. After activation, the workspace receives a seven-day trial. Choosing a plan records which service tier continues after the trial; the app displays the plan price before you confirm.'),
      PolicySection('Monthly plan prices',
          'Current monthly prices are Core — KES 3,200; Business — KES 6,500; and Enterprise — KES 10,000. Prices are in Kenyan shillings. The invoice shows the selected plan, amount, and billing period. We will show any changed price before it applies to a future billing period.'),
      PolicySection('Invoice payment',
          'Counterbase raises an invoice for each monthly period. Pay using the available checkout or manual payment instructions shown in Plan & Billing. A payment is not treated as complete until the payment provider or authorized workspace administrator confirms it. If an invoice remains unpaid, the app provides a grace period and may then restrict access; the current grace period is three days.'),
      PolicySection('Auto-Renew',
          'Auto-Renew is optional and starts off for new workspaces. When an owner enables it and accepts the separate authorization, Counterbase sends an M-Pesa STK prompt to the billing phone number selected by the owner when a monthly invoice is due. Each prompt must be approved on the phone. The amount is the invoice amount for the selected plan; it is not a silent recurring debit.'),
      PolicySection('Stopping automatic prompts',
          'An owner can turn Auto-Renew off in Plan & Billing at any time. This stops future automatic STK prompts; it does not cancel an invoice already raised or reverse a completed payment. You can pay manually while the account remains eligible. To close the workspace, contact support@archeaxon.com.'),
      PolicySection('Refund requests',
          'Send a refund or duplicate-charge request to support@archeaxon.com with the workspace name, payment reference, amount, and date. We review requests under applicable law and the payment provider’s processing rules and confirm the decision. Nothing here removes a right that applicable law does not allow us to exclude.'),
      PolicySection('Payment processors',
          'Paystack or another provider shown in checkout processes payment details under its own terms. Counterbase does not store M-Pesa PINs or bank passwords. Provider fees, settlement timing, and reversal processing may be set by the provider and displayed during its checkout.'),
    ],
  ),
  PolicyDocument(
    slug: 'auto-renewal',
    type: 'AUTO_RENEWAL_AUTHORIZATION',
    title: 'Auto-Renew Authorization',
    version: '2026-10-22-v1',
    summary: 'Separate authorization for monthly M-Pesa renewal prompts.',
    sections: [
      PolicySection('What you authorize',
          'By enabling Auto-Renew and accepting this authorization, you authorize Counterbase to send M-Pesa STK prompts to the billing phone number you enter for the monthly invoice amount shown in Plan & Billing. Only an owner or authorized billing administrator may enable this setting.'),
      PolicySection('Each payment still needs approval',
          'An STK prompt is a request for the phone holder to approve a payment in M-Pesa. Counterbase does not know or ask for the M-Pesa PIN and cannot silently debit the wallet. An invoice is paid only after the payment is verified.'),
      PolicySection('Changing or stopping it',
          'You can turn Auto-Renew off in Plan & Billing. That stops future automatic prompts. It does not cancel an invoice already issued, change its amount, or reverse a payment already completed. You may update the billing phone in the same settings screen.'),
      PolicySection('Amount and attempts',
          'Each prompt relates to the open invoice for the selected monthly plan. If a prompt is declined, expires, or fails, you can use another payment method shown in the app. Counterbase may limit repeated prompts and require manual payment after those attempts.'),
      PolicySection('Contact',
          'For a billing-phone or Auto-Renew question, email support@archeaxon.com.'),
    ],
  ),
  PolicyDocument(
    slug: 'merchant-payments',
    type: 'MERCHANT_PAYMENT_TERMS',
    title: 'Merchant Payments & Settlement',
    version: '2026-10-22-v1',
    summary: 'Terms for routing shop M-Pesa sales through Paystack to your bank.',
    sections: [
      PolicySection('Separate from your Counterbase plan',
          'Product-sale payments belong to your shop and are separate from the KES 35,000 Counterbase activation fee and the monthly Counterbase subscription. Connecting a payout account does not pay or change your Counterbase plan.'),
      PolicySection('Your payout account',
          'An authorized owner must select a supported Kenyan bank, enter the business account number, and confirm that the account belongs to the business. The full account number is sent to Paystack to create a merchant subaccount. Counterbase stores the subaccount code, bank and account name when returned, and the last four digits only. Never enter a bank password, M-Pesa PIN, or OTP.'),
      PolicySection('Payment processing and settlement',
          'Paystack processes eligible M-Pesa customer payments and routes the merchant share to the connected subaccount. Fees are borne by the merchant where configured; the provider shows or applies its fees. Paystack and the receiving bank determine settlement timing, account verification, reversals, and availability. Counterbase confirms a sale only after verifying the exact payment and payout route.'),
      PolicySection('Your shop’s obligations',
          'Your shop remains the seller and is responsible for product descriptions, prices, taxes, receipts, delivery, customer notices, returns, refunds, chargebacks, and customer disputes. Give your customers your own sales and privacy policies. Do not release goods based only on an unverified phone prompt or screenshot; rely on the completed status in Counterbase.'),
      PolicySection('Provider terms and support',
          'Your use of Paystack checkout and subaccounts is also subject to Paystack’s terms, eligibility checks, and settlement rules. Counterbase cannot guarantee that every bank account is accepted or that a provider will settle immediately. Contact support@archeaxon.com for a Counterbase payment record; contact Paystack or your bank for provider-side settlement questions.'),
    ],
  ),
];

PolicyDocument? policyDocument(String slug) {
  for (final document in kPolicyDocuments) {
    if (document.slug == slug) return document;
  }
  return null;
}
