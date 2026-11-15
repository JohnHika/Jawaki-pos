import { ForbiddenException } from '@nestjs/common';

/**
 * A shop pays for one business type. Once it has paid, the business type (the
 * main profile and any extra profiles) can only change through an approved
 * request. Everything else in the layout (labels, navigation, hidden pages,
 * quick actions) stays free to change.
 */

export const BUSINESS_TYPE_LOCKED_MESSAGE =
  'Your shop is set up for the business type you paid for. To switch to a different business type, send a change request with a reason, or add another store for it.';

export interface ApprovedProfileChange {
  requestId?: string;
  profileId?: string;
  additionalProfileIds?: string[];
}

const asList = (value: unknown): string[] =>
  Array.isArray(value)
    ? [...new Set(value.filter((v): v is string => typeof v === 'string' && v.length > 0))].sort()
    : [];

const sameList = (a: string[], b: string[]) =>
  a.length === b.length && a.every((v, i) => v === b[i]);

/**
 * Returns the settings to store. Throws 403 when a paid shop tries to change
 * its business type without an approval. Clients can never write the approval
 * marker themselves; it is removed from anything they send.
 */
export function applyBusinessTypeLock(
  tenant: { activationStatus?: string | null; settings?: unknown },
  incoming: Record<string, any> | undefined,
): Record<string, any> | undefined {
  if (!incoming) return incoming;
  const { approvedProfileChange: _forged, ...settings } = incoming;
  const layout = settings.businessLayout;
  if (!layout || typeof layout !== 'object') return settings;

  const stored = (tenant.settings ?? {}) as Record<string, any>;
  const storedLayout = stored.businessLayout;
  const storedProfile =
    storedLayout && typeof storedLayout === 'object' ? storedLayout.profileId : undefined;

  // Free while unpaid, and the first time a layout is chosen.
  if (tenant.activationStatus !== 'ACTIVE' || typeof storedProfile !== 'string' || !storedProfile) {
    return settings;
  }

  const nextProfile = typeof layout.profileId === 'string' ? layout.profileId : storedProfile;
  const nextExtras = asList(layout.additionalProfileIds);
  const storedExtras = asList(storedLayout.additionalProfileIds);
  if (nextProfile === storedProfile && sameList(nextExtras, storedExtras)) return settings;

  const approval = stored.approvedProfileChange as ApprovedProfileChange | undefined;
  if (
    approval &&
    approval.profileId === nextProfile &&
    sameList(asList(approval.additionalProfileIds), nextExtras)
  ) {
    return { ...settings, approvedProfileChange: null };
  }
  throw new ForbiddenException(BUSINESS_TYPE_LOCKED_MESSAGE);
}
