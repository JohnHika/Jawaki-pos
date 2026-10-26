import { PaymentMethod, PaymentStatus, Prisma } from "@prisma/client";

/**
 * A mobile-money sale is reportable only after the provider-backed payment
 * row has been completed. The generic sale and offline-sync endpoints cannot
 * prove an M-Pesa payment, so this also keeps orphaned legacy rows out of
 * dashboards, customer history, and sales-based inventory calculations.
 */
export function verifiedSalePaymentFilter(): Prisma.SaleWhereInput {
  return {
    OR: [
      { paymentMethod: { not: PaymentMethod.MPESA } },
      {
        paymentMethod: PaymentMethod.MPESA,
        payments: {
          some: {
            method: PaymentMethod.MPESA,
            status: PaymentStatus.COMPLETED,
          },
        },
      },
    ],
  };
}
