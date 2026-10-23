export interface DebtorCandidate {
  kind: 'CUSTOMER' | 'SHOP';
  id: string;
  name: string;
  phone: string | null;
  outstanding: number;
}

export interface Suggestion {
  kind: 'CUSTOMER' | 'SHOP';
  id: string;
  name: string;
  outstanding: number;
  score: number;
  confidence: 'HIGH' | 'MEDIUM' | 'LOW';
  reasons: string[];
}

/** Last nine digits of a Kenyan number, '*' kept as a wildcard for masked senders. */
export function nineDigits(value: string | null | undefined): string | null {
  if (!value) return null;
  const compact = value.replace(/[^\d*]/g, '');
  const trimmed = compact.startsWith('254') ? compact.slice(3) : compact.startsWith('0') ? compact.slice(1) : compact;
  return trimmed.length === 9 ? trimmed : null;
}

export function phoneMatches(entryPhone: string | null, candidatePhone: string | null): boolean {
  const a = nineDigits(entryPhone);
  const b = nineDigits(candidatePhone);
  if (!a || !b) return false;
  for (let i = 0; i < 9; i++) {
    if (a[i] !== '*' && b[i] !== '*' && a[i] !== b[i]) return false;
  }
  // An all-masked number proves nothing.
  return a.replace(/\*/g, '').length >= 4;
}

const tokens = (value: string): string[] =>
  value
    .toLowerCase()
    .replace(/[^a-z\s]/g, ' ')
    .split(/\s+/)
    .filter((t) => t.length >= 3);

/** Share of the sender's name words that appear in the debtor's name (0 to 1). */
export function nameOverlap(senderName: string | null, debtorName: string): number {
  if (!senderName) return 0;
  const sender = tokens(senderName);
  const debtor = new Set(tokens(debtorName));
  if (sender.length === 0 || debtor.size === 0) return 0;
  const hits = sender.filter((t) => debtor.has(t)).length;
  return hits / sender.length;
}

export function rankCandidates(
  entry: { senderName: string | null; senderPhone: string | null; amount: number },
  candidates: DebtorCandidate[],
  claimTarget?: { kind: 'CUSTOMER' | 'SHOP'; id: string } | null,
): Suggestion[] {
  const ranked: Suggestion[] = [];
  for (const c of candidates) {
    let score = 0;
    const reasons: string[] = [];
    if (claimTarget && claimTarget.kind === c.kind && claimTarget.id === c.id) {
      score += 100;
      reasons.push('They sent this code from their statement link');
    }
    if (phoneMatches(entry.senderPhone, c.phone)) {
      score += 70;
      reasons.push('Phone number matches');
    }
    const overlap = nameOverlap(entry.senderName, c.name);
    if (overlap >= 0.5) {
      score += 40 + Math.round(30 * overlap);
      reasons.push('Name matches');
    }
    if (score === 0) continue;
    if (Math.abs(c.outstanding - entry.amount) < 0.5) {
      score += 15;
      reasons.push('Amount equals what they owe');
    }
    ranked.push({
      kind: c.kind,
      id: c.id,
      name: c.name,
      outstanding: c.outstanding,
      score,
      confidence: score >= 90 ? 'HIGH' : score >= 60 ? 'MEDIUM' : 'LOW',
      reasons,
    });
  }
  return ranked.sort((a, b) => b.score - a.score).slice(0, 3);
}
