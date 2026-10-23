import { Lang } from './statements.types';

/**
 * Text on the statement page and PDF, in English and Kiswahili. The Swahili
 * is everyday trading language, not formal; have a native speaker review it
 * before it is relied on.
 */
export interface StatementStrings {
  statement: string;
  statementFor: string;
  asOf: string;
  youOwe: string;
  overdue: string;
  overdueBy: (days: number) => string;
  due: string;
  receipt: string;
  date: string;
  openItems: string;
  original: string;
  paidSoFar: string;
  balance: string;
  howToPay: string;
  recentPayments: string;
  nothingOwed: string;
  paidAlready: string;
  promise: string;
  mpesaCode: string;
  amountKes: string;
  yourName: string;
  payDate: string;
  send: string;
  sending: string;
  thanks: (shop: string) => string;
  somethingWrong: string;
  download: string;
  language: string;
  otherLanguageLabel: string;
  expired: string;
  expiredHelp: string;
  joinTitle: string;
  joinBody: (shop: string, code: string | null) => string;
  getApp: string;
  preparedWith: string;
  contact: string;
  shareLine: (debtor: string, shop: string, amount: string, url: string) => string;
  pdfFooter: string;
  method: { CASH: string; MPESA: string; CARD: string };
  moreItems: (n: number) => string;
  codeHelp: string;
}

const EN: StatementStrings = {
  statement: 'Statement',
  statementFor: 'Statement for',
  asOf: 'As of',
  youOwe: 'Amount owed',
  overdue: 'Overdue',
  overdueBy: (d) => `${d} day${d === 1 ? '' : 's'} overdue`,
  due: 'Due',
  receipt: 'Receipt',
  date: 'Date',
  openItems: 'Open items',
  original: 'Original',
  paidSoFar: 'Paid',
  balance: 'Balance',
  howToPay: 'How to pay',
  recentPayments: 'Recent payments',
  nothingOwed: 'You owe nothing right now. Thank you!',
  paidAlready: 'I have paid',
  promise: 'I will pay on',
  mpesaCode: 'M-Pesa code',
  amountKes: 'Amount (KES)',
  yourName: 'Your name',
  payDate: 'Date you will pay',
  send: 'Send',
  sending: 'Sending...',
  thanks: (shop) => `Thank you. ${shop} has been told.`,
  somethingWrong: 'Something went wrong. Please try again.',
  download: 'Download PDF',
  language: 'Kiswahili',
  otherLanguageLabel: 'Kiswahili',
  expired: 'This link has expired',
  expiredHelp: 'Ask the shop to send you a new statement.',
  joinTitle: 'Run your own shop with Counterbase',
  joinBody: (shop, code) =>
    `${shop} uses Counterbase to keep stock, credit and cash in order. Shops on it can trade with each other, share prices and message each other.` +
    (code ? ` Use code ${code} when you sign up for extra free days.` : ''),
  getApp: 'Get the app',
  preparedWith: 'Prepared with Counterbase',
  contact: 'Questions? Call',
  shareLine: (debtor, shop, amount, url) =>
    `Hello ${debtor}, this is your statement from ${shop}. Amount owed: ${amount}. See the details and pay here: ${url}`,
  pdfFooter: 'Prepared with Counterbase',
  method: { CASH: 'Cash', MPESA: 'M-Pesa', CARD: 'Card' },
  moreItems: (n) => `and ${n} more`,
  codeHelp: 'The 10 letters and numbers in the M-Pesa message, e.g. QJK7ABCD12',
};

const SW: StatementStrings = {
  statement: 'Taarifa ya deni',
  statementFor: 'Taarifa ya',
  asOf: 'Hadi tarehe',
  youOwe: 'Kiasi unachodaiwa',
  overdue: 'Imechelewa',
  overdueBy: (d) => `Imechelewa siku ${d}`,
  due: 'Tarehe ya kulipa',
  receipt: 'Risiti',
  date: 'Tarehe',
  openItems: 'Madeni yaliyo wazi',
  original: 'Deni la awali',
  paidSoFar: 'Umelipa',
  balance: 'Salio',
  howToPay: 'Jinsi ya kulipa',
  recentPayments: 'Malipo ya karibuni',
  nothingOwed: 'Huna deni kwa sasa. Asante!',
  paidAlready: 'Nimelipa',
  promise: 'Nitalipa tarehe',
  mpesaCode: 'Nambari ya M-Pesa',
  amountKes: 'Kiasi (KES)',
  yourName: 'Jina lako',
  payDate: 'Tarehe utakayolipa',
  send: 'Tuma',
  sending: 'Inatuma...',
  thanks: (shop) => `Asante. ${shop} ameambiwa.`,
  somethingWrong: 'Kuna hitilafu. Tafadhali jaribu tena.',
  download: 'Pakua PDF',
  language: 'English',
  otherLanguageLabel: 'English',
  expired: 'Kiungo hiki kimekwisha muda',
  expiredHelp: 'Mwombe muuzaji akutumie taarifa mpya.',
  joinTitle: 'Endesha duka lako na Counterbase',
  joinBody: (shop, code) =>
    `${shop} anatumia Counterbase kuweka hisa, madeni na pesa kwa mpangilio. Maduka yaliyomo yanaweza kufanya biashara pamoja, kushiriki bei na kutumiana ujumbe.` +
    (code ? ` Tumia msimbo ${code} unapojisajili upate siku za bure.` : ''),
  getApp: 'Pakua programu',
  preparedWith: 'Imeandaliwa na Counterbase',
  contact: 'Una swali? Piga simu',
  shareLine: (debtor, shop, amount, url) =>
    `Habari ${debtor}, hii ni taarifa yako kutoka ${shop}. Kiasi unachodaiwa: ${amount}. Tazama maelezo na ulipe hapa: ${url}`,
  pdfFooter: 'Imeandaliwa na Counterbase',
  method: { CASH: 'Pesa taslimu', MPESA: 'M-Pesa', CARD: 'Kadi' },
  moreItems: (n) => `na ${n} zaidi`,
  codeHelp: 'Herufi na nambari 10 zilizo kwenye ujumbe wa M-Pesa, mfano QJK7ABCD12',
};

export function stringsFor(lang: Lang): StatementStrings {
  return lang === 'sw' ? SW : EN;
}

export function parseLang(value: unknown): Lang {
  return value === 'sw' ? 'sw' : 'en';
}
