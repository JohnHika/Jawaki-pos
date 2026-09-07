import { SetMetadata } from '@nestjs/common';

/**
 * Marks a route as exempt from the subscription restricted-mode gate
 * (SubscriptionGuard). Use for routes that must stay writable even when a
 * tenant is PAST_DUE beyond grace — e.g. the billing recovery endpoints
 * themselves, or health/auth plumbing.
 */
export const PUBLIC_SUBSCRIPTION_EXEMPT_KEY = 'publicSubscriptionExempt';
export const PublicSubscriptionExempt = () =>
  SetMetadata(PUBLIC_SUBSCRIPTION_EXEMPT_KEY, true);