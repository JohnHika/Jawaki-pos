export const POLICY_VERSIONS = {
  TERMS_OF_SERVICE: '2026-10-22-v1',
  PRIVACY_NOTICE: '2026-10-22-v1',
  DATA_PROCESSING_ADDENDUM: '2026-10-22-v1',
  BILLING_TERMS: '2026-10-22-v1',
  AUTO_RENEWAL_AUTHORIZATION: '2026-10-22-v1',
  MERCHANT_PAYMENT_TERMS: '2026-10-22-v1',
} as const;

export type PolicyType = keyof typeof POLICY_VERSIONS;

export const SIGNUP_REQUIRED_POLICY_TYPES: PolicyType[] = [
  'TERMS_OF_SERVICE',
  'PRIVACY_NOTICE',
  'DATA_PROCESSING_ADDENDUM',
];

export function isPolicyType(value: string): value is PolicyType {
  return Object.prototype.hasOwnProperty.call(POLICY_VERSIONS, value);
}

export function isCurrentPolicyVersion(type: string, version: string): type is PolicyType {
  return isPolicyType(type) && POLICY_VERSIONS[type] === version;
}
