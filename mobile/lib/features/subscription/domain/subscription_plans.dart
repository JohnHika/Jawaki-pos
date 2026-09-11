import 'package:intl/intl.dart';

/// Subscription plan ladder — single source of truth for every plan surface
/// in the app (onboarding plan selection, settings subscription screen,
/// billing screen).
///
/// Three purchasable tiers: CORE → BUSINESS → ENTERPRISE.
///
/// Prices MUST mirror the backend `PLAN_PRICING` map in
/// `backend/src/subscription/subscription.service.ts` — change both
/// together. The backend is the billing source of truth; this catalog only
/// drives UI copy and the change-plan request.
///
/// Feature copy rules: every line describes something the app actually does
/// today, written in shop-owner language (what it does FOR the owner), not
/// technical jargon. Do not list a capability that is not implemented.

/// Represents a subscription plan option.
class SubscriptionPlan {
  final String id;
  final String name;
  final String tagline;
  final double priceKes;
  final List<PlanFeature> features;
  final bool isPopular;

  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.tagline,
    required this.priceKes,
    required this.features,
    this.isPopular = false,
  });
}

/// A feature row used in the plan comparison table.
class PlanFeature {
  final String text;
  final bool includedInCore;
  final bool includedInBusiness;
  final bool includedInEnterprise;

  const PlanFeature({
    required this.text,
    this.includedInCore = false,
    this.includedInBusiness = false,
    this.includedInEnterprise = false,
  });
}

/// Rich feature catalog used for the comparison table. Rows are grouped by
/// the job the owner is trying to get done, and each row must map to real
/// behaviour in the app.
const kPlanFeatures = [
  // ── Selling ────────────────────────────────────────────────────────
  PlanFeature(
    text: 'Sell as many items as you want — no per-sale charge',
    includedInCore: true,
    includedInBusiness: true,
    includedInEnterprise: true,
  ),
  PlanFeature(
    text: 'Keep selling when the internet goes down (works offline)',
    includedInCore: true,
    includedInBusiness: true,
    includedInEnterprise: true,
  ),
  PlanFeature(
    text: 'Record M-Pesa, cash and card payments on every sale',
    includedInCore: true,
    includedInBusiness: true,
    includedInEnterprise: true,
  ),
  PlanFeature(
    text: 'Print receipts on a thermal printer or send them digitally',
    includedInCore: true,
    includedInBusiness: true,
    includedInEnterprise: true,
  ),
  PlanFeature(
    text: 'Give discounts and change prices with your PIN',
    includedInCore: true,
    includedInBusiness: true,
    includedInEnterprise: true,
  ),

  // ── Stock ──────────────────────────────────────────────────────────
  PlanFeature(
    text: 'Know your stock level at any moment',
    includedInCore: true,
    includedInBusiness: true,
    includedInEnterprise: true,
  ),
  PlanFeature(
    text: 'Get warned before fast-selling items run out',
    includedInCore: true,
    includedInBusiness: true,
    includedInEnterprise: true,
  ),
  PlanFeature(
    text: 'Record deliveries from suppliers, item by item',
    includedInCore: true,
    includedInBusiness: true,
    includedInEnterprise: true,
  ),
  PlanFeature(
    text: 'Move stock between your shops',
    includedInBusiness: true,
    includedInEnterprise: true,
  ),
  PlanFeature(
    text: 'Restock suggestions — what to reorder and how much',
    includedInBusiness: true,
    includedInEnterprise: true,
  ),
  PlanFeature(
    text: 'Forecast what you will need next month',
    includedInBusiness: true,
    includedInEnterprise: true,
  ),

  // ── Money ──────────────────────────────────────────────────────────
  PlanFeature(
    text: 'Keep your books in order — every sale and expense recorded',
    includedInCore: true,
    includedInBusiness: true,
    includedInEnterprise: true,
  ),
  PlanFeature(
    text: 'Record customer debts and see who owes you and for how long',
    includedInCore: true,
    includedInBusiness: true,
    includedInEnterprise: true,
  ),
  PlanFeature(
    text: 'Match your till to the system at end of day',
    includedInCore: true,
    includedInBusiness: true,
    includedInEnterprise: true,
  ),
  PlanFeature(
    text: 'See today\u2019s sales, profit and top items before you close',
    includedInCore: true,
    includedInBusiness: true,
    includedInEnterprise: true,
  ),
  PlanFeature(
    text: 'Track suppliers — who you owe, invoices and payments',
    includedInBusiness: true,
    includedInEnterprise: true,
  ),
  PlanFeature(
    text: 'Advanced reports and export your data to Excel',
    includedInBusiness: true,
    includedInEnterprise: true,
  ),
  PlanFeature(
    text: 'Books combined across all your branches in one place',
    includedInEnterprise: true,
  ),

  // ── Customers ──────────────────────────────────────────────────────
  PlanFeature(
    text: 'Customer profiles with their full buying history',
    includedInCore: true,
    includedInBusiness: true,
    includedInEnterprise: true,
  ),
  PlanFeature(
    text: 'Loyalty points to keep customers coming back',
    includedInCore: true,
    includedInBusiness: true,
    includedInEnterprise: true,
  ),
  PlanFeature(
    text: 'See your best customers and inactive ones',
    includedInBusiness: true,
    includedInEnterprise: true,
  ),

  // ── Staff & branches ───────────────────────────────────────────────
  PlanFeature(
    text: 'Each staff member gets their own login and rights',
    includedInCore: true,
    includedInBusiness: true,
    includedInEnterprise: true,
  ),
  PlanFeature(
    text: 'Up to 3 branches',
    includedInCore: true,
  ),
  PlanFeature(
    text: 'Up to 10 branches',
    includedInBusiness: true,
  ),
  PlanFeature(
    text: 'Unlimited branches',
    includedInEnterprise: true,
  ),
  PlanFeature(
    text: 'Up to 10 staff accounts',
    includedInCore: true,
  ),
  PlanFeature(
    text: 'Up to 50 staff accounts',
    includedInBusiness: true,
  ),
  PlanFeature(
    text: 'Unlimited staff accounts',
    includedInEnterprise: true,
  ),
  PlanFeature(
    text: 'See which staff sell the most',
    includedInBusiness: true,
    includedInEnterprise: true,
  ),
  PlanFeature(
    text: 'Compare your shops side by side',
    includedInBusiness: true,
    includedInEnterprise: true,
  ),
  PlanFeature(
    text: 'Every action logged — full audit trail',
    includedInEnterprise: true,
  ),

  // ── AI assistant ───────────────────────────────────────────────────
  PlanFeature(
    text: 'AI assistant included — ask about sales, stock, debts and profit',
    includedInCore: true,
    includedInBusiness: true,
    includedInEnterprise: true,
  ),
  PlanFeature(
    text: 'AI answers across all your branches at once',
    includedInBusiness: true,
    includedInEnterprise: true,
  ),

  // ── Support ────────────────────────────────────────────────────────
  PlanFeature(
    text: 'Email support',
    includedInCore: true,
    includedInBusiness: true,
  ),
  PlanFeature(
    text: 'WhatsApp support from our team',
    includedInBusiness: true,
  ),
  PlanFeature(
    text: 'Priority phone and WhatsApp support — talk to a human fast',
    includedInEnterprise: true,
  ),
  PlanFeature(
    text: 'Free onboarding and training for your team',
    includedInEnterprise: true,
  ),

  // ── Trial ──────────────────────────────────────────────────────────
  PlanFeature(
    text: '7-day free trial on every plan',
    includedInCore: true,
    includedInBusiness: true,
    includedInEnterprise: true,
  ),
];

/// Plan metadata used for the plan cards. Feature lists are written in
/// plain shop-owner language and cover every real capability of the plan.
const kAvailablePlans = [
  SubscriptionPlan(
    id: 'core',
    name: 'CORE',
    tagline: 'Everything a single shop needs to sell, track stock and keep books',
    priceKes: 3200,
    features: [
      PlanFeature(text: 'Sell as many items as you want — no per-sale charge', includedInCore: true),
      PlanFeature(text: 'Keep selling when the internet goes down (works offline)', includedInCore: true),
      PlanFeature(text: 'Record M-Pesa, cash and card payments on every sale', includedInCore: true),
      PlanFeature(text: 'Print receipts on a thermal printer or send them digitally', includedInCore: true),
      PlanFeature(text: 'Know your stock level at any moment', includedInCore: true),
      PlanFeature(text: 'Get warned before fast-selling items run out', includedInCore: true),
      PlanFeature(text: 'Keep your books in order — every sale and expense recorded', includedInCore: true),
      PlanFeature(text: 'Record customer debts and see who owes you and for how long', includedInCore: true),
      PlanFeature(text: 'Match your till to the system at end of day', includedInCore: true),
      PlanFeature(text: 'See today\u2019s sales, profit and top items before you close', includedInCore: true),
      PlanFeature(text: 'Customer profiles with their full buying history', includedInCore: true),
      PlanFeature(text: 'Loyalty points to keep customers coming back', includedInCore: true),
      PlanFeature(text: 'Each staff member gets their own login and rights', includedInCore: true),
      PlanFeature(text: 'AI assistant included — ask about sales, stock, debts and profit', includedInCore: true),
      PlanFeature(text: 'Up to 3 branches', includedInCore: true),
      PlanFeature(text: 'Up to 10 staff accounts', includedInCore: true),
      PlanFeature(text: 'Email support', includedInCore: true),
      PlanFeature(text: '7-day free trial', includedInCore: true),
    ],
  ),
  SubscriptionPlan(
    id: 'business',
    name: 'BUSINESS',
    tagline: 'For shops growing to more than one branch — transfers, suppliers and deeper reports',
    priceKes: 6500,
    isPopular: true,
    features: [
      PlanFeature(text: 'Everything in Core, plus:', includedInBusiness: true),
      PlanFeature(text: 'Up to 10 branches', includedInBusiness: true),
      PlanFeature(text: 'Up to 50 staff accounts', includedInBusiness: true),
      PlanFeature(text: 'Move stock between your shops', includedInBusiness: true),
      PlanFeature(text: 'Compare your shops side by side', includedInBusiness: true),
      PlanFeature(text: 'Restock suggestions — what to reorder and how much', includedInBusiness: true),
      PlanFeature(text: 'Forecast what you will need next month', includedInBusiness: true),
      PlanFeature(text: 'Track suppliers — who you owe, invoices and payments', includedInBusiness: true),
      PlanFeature(text: 'See which staff sell the most', includedInBusiness: true),
      PlanFeature(text: 'See your best customers and inactive ones', includedInBusiness: true),
      PlanFeature(text: 'Advanced reports and export your data to Excel', includedInBusiness: true),
      PlanFeature(text: 'AI answers across all your branches at once', includedInBusiness: true),
      PlanFeature(text: 'WhatsApp support from our team', includedInBusiness: true),
      PlanFeature(text: '7-day free trial', includedInBusiness: true),
    ],
  ),
  SubscriptionPlan(
    id: 'enterprise',
    name: 'ENTERPRISE',
    tagline: 'Unlimited branches and staff, combined books and priority support',
    priceKes: 10000,
    features: [
      PlanFeature(text: 'Everything in Business, plus:', includedInEnterprise: true),
      PlanFeature(text: 'Unlimited branches', includedInEnterprise: true),
      PlanFeature(text: 'Unlimited staff accounts', includedInEnterprise: true),
      PlanFeature(text: 'Books combined across all your branches in one place', includedInEnterprise: true),
      PlanFeature(text: 'Every action logged — full audit trail', includedInEnterprise: true),
      PlanFeature(text: 'Priority phone and WhatsApp support — talk to a human fast', includedInEnterprise: true),
      PlanFeature(text: 'Free onboarding and training for your team', includedInEnterprise: true),
      PlanFeature(text: 'AI answers across all your branches at once', includedInEnterprise: true),
      PlanFeature(text: '7-day free trial', includedInEnterprise: true),
    ],
  ),
];

/// Monthly price for a plan id (lowercase or uppercase). Falls back to the
/// CORE price for unknown ids, mirroring the backend's `?? PLAN_PRICING.CORE`
/// behaviour.
double planPriceKes(String planId) {
  switch (planId.toLowerCase()) {
    case 'trial':
      return 0;
    case 'core':
      return 3200;
    case 'business':
      return 6500;
    case 'enterprise':
      return 10000;
    default:
      return 3200;
  }
}

/// The in-trial plan — every paid plan starts with it. Not purchasable, so
/// it is kept out of [kAvailablePlans].
const kTrialPlan = SubscriptionPlan(
  id: 'trial',
  name: 'TRIAL',
  tagline: 'Explore Axon free for 7 days',
  priceKes: 0,
  features: [
    PlanFeature(text: 'Up to 1 branch', includedInCore: true),
    PlanFeature(text: 'Up to 3 staff accounts', includedInCore: true),
    PlanFeature(text: 'Sell, track stock and record payments', includedInCore: true),
    PlanFeature(text: 'AI assistant included', includedInCore: true),
    PlanFeature(text: '7-day free trial', includedInCore: true),
  ],
);

/// Look up a plan (including TRIAL) by id, case-insensitive. Returns null
/// for unknown ids.
SubscriptionPlan? planById(String? id) {
  if (id == null) return null;
  final key = id.toLowerCase();
  if (key == kTrialPlan.id) return kTrialPlan;
  for (final plan in kAvailablePlans) {
    if (plan.id == key) return plan;
  }
  return null;
}

/// Display name for a plan id (uppercase), falling back to the raw id.
String planDisplayName(String planId) {
  for (final plan in kAvailablePlans) {
    if (plan.id == planId.toLowerCase()) return plan.name;
  }
  return planId.toUpperCase();
}

/// Limits at or above this value render as "Unlimited" (the backend uses a
/// large sentinel for unlimited plans).
const int kUnlimitedLimitThreshold = 1000;

bool isUnlimitedLimit(int? value) =>
    value != null && value >= kUnlimitedLimitThreshold;

/// "KES 3,200" / "KES 10,000" — thousands separators, no decimals for whole
/// shillings.
String formatKes(num amount) {
  if (amount == amount.roundToDouble()) {
    return 'KES ${NumberFormat('#,###').format(amount.toInt())}';
  }
  return 'KES ${amount.toStringAsFixed(2)}';
}

/// "Up to 3" / "Unlimited" / "—" for branch and staff limits.
String formatLimit(int? value) {
  if (value == null) return '—';
  if (isUnlimitedLimit(value)) return 'Unlimited';
  return 'Up to $value';
}
