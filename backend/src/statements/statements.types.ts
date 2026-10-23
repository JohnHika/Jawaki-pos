export type Lang = 'en' | 'sw';

export interface StatementItem {
  date: Date;
  reference: string;
  description: string;
  original: number;
  paid: number;
  outstanding: number;
  dueDate: Date | null;
  overdueDays: number;
}

export interface StatementPayment {
  date: Date;
  amount: number;
  method: string;
  reference: string | null;
}

/** Everything the web page, the PDF and the app's preview show about one debtor. */
export interface StatementView {
  business: {
    name: string;
    phone: string | null;
    logo: string | null;
    payInstructions: string | null;
  };
  debtor: { name: string; kind: 'CUSTOMER' | 'SHOP' };
  asOf: Date;
  outstanding: number;
  overdue: number;
  oldestOverdueDays: number;
  items: StatementItem[];
  payments: StatementPayment[];
  message: string | null;
  expiresAt: Date | null;
  /** The sending shop's referral code, shown on the invitation to join. */
  inviteCode: string | null;
}
