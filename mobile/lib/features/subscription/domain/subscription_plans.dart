import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Subscription plan ladder — single source of truth for every plan surface
/// in the app (onboarding plan selection, settings subscription screen,
/// billing screen).
///
/// Three purchasable tiers: CORE → BUSINESS → ENTERPRISE.
///
/// The backend `PLAN_PRICING` map in
/// `backend/src/subscription/subscription.service.ts` is the price the
/// invoices charge, so it is the one the owner is shown. The app reads it
/// from `GET /subscription/plan` ([PlanPrices.apply]) and remembers the last
/// copy. The prices written below are only the last resort for a phone that
/// has never reached the server; keep them equal to the backend's.
///
/// Feature copy rules: every line describes something the app actually does
/// today, written in shop-owner language (what it does FOR the owner), not
/// technical jargon. Do not list a capability that is not implemented.

/// Where the prices on screen came from.
enum PlanPriceSource { bundled, saved, live }

/// The prices shown to the owner: the server's when known, the bundled
/// fallback otherwise. Process-wide so every plan surface agrees.
class PlanPrices {
  PlanPrices._();

  static const _prefsKey = 'plan_prices_v1';
  static final Map<String, double> _byId = {};
  static PlanPriceSource _source = PlanPriceSource.bundled;

  static PlanPriceSource get source => _source;

  /// True when the numbers are not from this session's server answer.
  static bool get isLastKnown => _source != PlanPriceSource.live;

  static double? of(String planId) => _byId[planId.toLowerCase()];

  /// Takes the server's `availablePlans` (or `plans`) list.
  static Future<void> apply(Object? plans) async {
    final parsed = _parse(plans);
    if (parsed.isEmpty) return;
    _byId
      ..clear()
      ..addAll(parsed);
    _source = PlanPriceSource.live;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(parsed));
    } catch (_) {}
  }

  /// Loads the copy saved by the last successful [apply]; never overrides
  /// live prices.
  static Future<void> restore() async {
    if (_source == PlanPriceSource.live) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final saved = <String, double>{
        for (final e in decoded.entries)
          if (e.value is num) e.key.toString(): (e.value as num).toDouble(),
      };
      if (saved.isEmpty) return;
      _byId
        ..clear()
        ..addAll(saved);
      _source = PlanPriceSource.saved;
    } catch (_) {}
  }

  @visibleForTesting
  static void reset() {
    _byId.clear();
    _source = PlanPriceSource.bundled;
  }

  static Map<String, double> _parse(Object? plans) {
    if (plans is! List) return const {};
    final out = <String, double>{};
    for (final p in plans) {
      if (p is! Map) continue;
      final id = p['planId']?.toString().toLowerCase();
      final price = p['monthlyAmountKes'];
      if (id == null || id == 'trial' || price is! num) continue;
      out[id] = price.toDouble();
    }
    return out;
  }
}

/// Represents a subscription plan option.
class SubscriptionPlan {
  final String id;
  final String name;
  final String tagline;

  /// The last-resort price written in this file; screens read [priceKes].
  final double bundledPriceKes;
  final List<PlanFeature> features;
  final bool isPopular;

  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.tagline,
    required double priceKes,
    required this.features,
    this.isPopular = false,
  }) : bundledPriceKes = priceKes;

  /// The monthly price to show: the server's when known.
  double get priceKes => PlanPrices.of(id) ?? bundledPriceKes;
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
    priceKes: 3000,
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
    priceKes: 5000,
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
    priceKes: 9999,
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

/// Monthly price for a plan id (lowercase or uppercase): the server's price
/// when known. Falls back to the CORE price for unknown ids, mirroring the
/// backend's `?? PLAN_PRICING.CORE` behaviour.
double planPriceKes(String planId) {
  final id = planId.toLowerCase();
  if (id == 'trial') return 0;
  for (final plan in kAvailablePlans) {
    if (plan.id == id) return plan.priceKes;
  }
  return kAvailablePlans.first.priceKes;
}

/// The in-trial plan — every paid plan starts with it. Not purchasable, so
/// it is kept out of [kAvailablePlans].
const kTrialPlan = SubscriptionPlan(
  id: 'trial',
  name: 'TRIAL',
  tagline: 'Explore Counterbase free for 7 days',
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

/// "KES 3,000" / "KES 9,999" — thousands separators, no decimals for whole
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
