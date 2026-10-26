import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  HttpException,
  Injectable,
  NotFoundException,
  Optional,
  ServiceUnavailableException,
} from "@nestjs/common";
import {
  MerchantPaymentAccount,
  PaymentMethod,
  PaymentStatus,
  Prisma,
  ReceivablePaymentMethod,
} from "@prisma/client";
import { randomBytes } from "crypto";
import { PaystackService } from "../ai-billing/paystack.service";
import { PrismaService } from "../common/prisma/prisma.service";
import { CreateSaleDto } from "../sales/dto/sales.dto";
import { SalesService } from "../sales/sales.service";
import {
  ConfigureMerchantPayoutDto,
  StartMerchantMpesaDto,
  StartMerchantReceivableMpesaDto,
} from "./dto/merchant-payments.dto";
import { LegalPolicyService } from "../legal/legal-policy.service";
import { FinanceService } from "../finance/finance.service";

type Actor = { sub: string; tenantId: string; permissions?: string[] };

// Paystack recommends waiting at least 10 seconds before checking a pending
// Charge API request. Enforce the interval on the server so a fast client or
// repeated taps cannot poll the provider prematurely.
const MIN_MERCHANT_CHARGE_CHECK_INTERVAL_MS = 10_000;

@Injectable()
export class MerchantPaymentsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly paystack: PaystackService,
    private readonly sales: SalesService,
    @Optional() private readonly legalPolicies?: LegalPolicyService,
    @Optional() private readonly finance?: FinanceService,
  ) {}

  async account(actor: Actor) {
    const row = await this.prisma.merchantPaymentAccount.findUnique({
      where: { tenantId: actor.tenantId },
    });
    if (!row)
      return {
        status: "NOT_CONFIGURED",
        provider: "PAYSTACK",
        currency: "KES",
      };
    const payout = await this.refreshPayoutVerification(row);
    const accountName = payout.row.accountName?.trim() || null;
    return {
      status: payout.status,
      provider: payout.row.provider,
      currency: payout.row.currency,
      bankCode: payout.row.bankCode,
      bankName: payout.row.bankName,
      accountName,
      accountHolderVerified: Boolean(accountName),
      paystackVerified: payout.paystackVerified,
      accountLast4: payout.row.accountLast4,
      updatedAt: payout.row.updatedAt,
    };
  }

  async banks() {
    return this.paystack.listKenyanBanks();
  }

  async configureAccount(actor: Actor, dto: ConfigureMerchantPayoutDto) {
    if (!actor.permissions?.includes("payments.manage_payout")) {
      throw new ForbiddenException(
        "You do not have permission to change payout details",
      );
    }
    await this.legalPolicies?.assertCurrentAcceptance(
      actor.tenantId,
      "MERCHANT_PAYMENT_TERMS",
    );
    if (dto.confirmAccountOwnership !== true) {
      throw new BadRequestException(
        "Confirm that this payout account belongs to your business",
      );
    }
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: actor.tenantId },
      select: { name: true },
    });
    const owner = await this.prisma.user.findUnique({
      where: { id: actor.sub },
      select: { email: true },
    });
    if (!tenant || !owner)
      throw new NotFoundException("Business owner was not found");

    const availableBanks = await this.paystack.listKenyanBanks();
    const bank = availableBanks.find((item) => item.code === dto.bankCode);
    if (!bank) throw new BadRequestException("Select a supported Kenyan bank");

    const existing = await this.prisma.merchantPaymentAccount.findUnique({
      where: { tenantId: actor.tenantId },
    });
    const payoutDetails = {
      businessName: tenant.name,
      bankCode: bank.code,
      accountNumber: dto.accountNumber,
      contactEmail: owner.email,
    };
    // Keep the Paystack route attached to each already-started charge. Updating
    // an existing subaccount changes its bank destination in place, so create
    // a new route when the destination changes. Reuse the existing route only
    // after Paystack confirms the exact same account is still attached to it.
    let unchangedSubaccount: Awaited<
      ReturnType<PaystackService["getMerchantSubaccount"]>
    > | null = null;
    if (
      existing &&
      typeof this.paystack.getMerchantSubaccount === "function" &&
      existing.bankCode === bank.code &&
      existing.accountLast4 === dto.accountNumber.slice(-4)
    ) {
      try {
        const providerAccount = await this.paystack.getMerchantSubaccount(
          existing.subaccountCode,
        );
        const normalizeBankName = (value: string) =>
          value
            .toLowerCase()
            .replace(/\blimited\b/g, "ltd")
            .replace(/[^a-z0-9]/g, "");
        const providerBank = providerAccount.settlement_bank?.trim();
        const sameProviderBank =
          !providerBank ||
          normalizeBankName(providerBank) === normalizeBankName(bank.name);
        if (
          providerAccount.subaccount_code === existing.subaccountCode &&
          providerAccount.account_number === dto.accountNumber &&
          sameProviderBank &&
          providerAccount.active !== false &&
          (!providerAccount.currency || providerAccount.currency === "KES")
        ) {
          unchangedSubaccount = providerAccount;
        }
      } catch {
        // If Paystack cannot confirm the current destination, create a fresh
        // subaccount below. Never mutate a route used by earlier charges.
      }
    }
    const subaccount =
      unchangedSubaccount ??
      (await this.paystack.createMerchantSubaccount(payoutDetails));
    const subaccountCode =
      subaccount.subaccount_code ||
      (unchangedSubaccount ? existing?.subaccountCode : undefined);
    if (
      !subaccountCode ||
      subaccount.active === false ||
      (subaccount.currency && subaccount.currency !== "KES")
    ) {
      throw new ServiceUnavailableException(
        "Paystack did not confirm a usable KES payout account. No payment route was changed.",
      );
    }

    let providerAccount = subaccount;
    if (
      typeof providerAccount.is_verified !== "boolean" &&
      typeof this.paystack.getMerchantSubaccount === "function"
    ) {
      try {
        providerAccount =
          await this.paystack.getMerchantSubaccount(subaccountCode);
      } catch {
        // Preserve the submitted bank details, but keep M-Pesa locked until
        // Paystack's verification state can be confirmed.
      }
    }
    const accountName = providerAccount.account_name?.trim() || null;
    // Older non-production adapters may not expose Paystack's verification
    // endpoint. In production the explicit is_verified flag is authoritative.
    const paystackVerified =
      typeof this.paystack.getMerchantSubaccount !== "function"
        ? Boolean(accountName)
        : providerAccount.subaccount_code === subaccountCode &&
          providerAccount.is_verified === true &&
          providerAccount.active !== false;
    if (
      typeof this.paystack.getMerchantSubaccount !== "function" &&
      !accountName
    ) {
      throw new ServiceUnavailableException(
        "Paystack could not confirm the account holder name. Check the bank and account number before accepting customer payments.",
      );
    }
    const accountStatus =
      providerAccount.active === false
        ? "INACTIVE"
        : paystackVerified
          ? "ACTIVE"
          : "PENDING_VERIFICATION";

    await this.prisma.$transaction(async (tx) => {
      await tx.merchantPaymentAccount.upsert({
        where: { tenantId: actor.tenantId },
        create: {
          tenantId: actor.tenantId,
          subaccountCode,
          bankCode: bank.code,
          bankName: bank.name,
          accountName,
          accountLast4: dto.accountNumber.slice(-4),
          currency: "KES",
          status: accountStatus,
        },
        update: {
          subaccountCode,
          bankCode: bank.code,
          bankName: bank.name,
          accountName,
          accountLast4: dto.accountNumber.slice(-4),
          currency: "KES",
          status: accountStatus,
        },
      });
      const onboarding = await tx.tenantOnboarding.findUnique({
        where: { tenantId: actor.tenantId },
        select: { id: true },
      });
      if (onboarding) {
        await tx.tenantOnboardingStep.updateMany({
          where: { onboardingId: onboarding.id, key: "activate_payment" },
          data: paystackVerified
            ? { status: "COMPLETED", completedAt: new Date(), deferredAt: null }
            : { status: "PENDING", completedAt: null, deferredAt: null },
        });
      }
    });
    return this.account(actor);
  }

  async startMpesa(actor: Actor, input: StartMerchantMpesaDto) {
    const prior = await this.prisma.merchantCharge.findUnique({
      where: {
        tenantId_requestId: {
          tenantId: actor.tenantId,
          requestId: input.requestId,
        },
      },
    });
    if (prior) {
      this.assertSameSaleRequest(prior, actor, input);
      return this.presentStart(prior);
    }
    const account = await this.prisma.merchantPaymentAccount.findUnique({
      where: { tenantId: actor.tenantId },
    });
    if (!account) {
      throw new ConflictException(
        "Add your business payout account in Customer payments to accept M-Pesa sales.",
      );
    }
    const payout = await this.refreshPayoutVerification(account);
    if (!payout.paystackVerified || payout.status !== "ACTIVE") {
      throw new ConflictException(
        "Paystack has not verified this business payout account yet. Finish verification in Customer payments to accept M-Pesa sales.",
      );
    }
    if (
      input.sale.paymentMethod !== PaymentMethod.MPESA ||
      input.sale.tenders?.length
    ) {
      throw new BadRequestException(
        "This checkout accepts one M-Pesa payment for one sale",
      );
    }
    const quote = await this.sales.quoteMerchantMpesaSale(
      actor.sub,
      actor.tenantId,
      input.sale,
    );
    const amount = quote.amount;
    if (Math.abs((input.sale.paidAmount ?? amount) - amount) > 0.01) {
      throw new BadRequestException(
        "The sale total changed. Refresh the cart before requesting payment",
      );
    }
    const phone = this.normalizePhone(input.phoneNumber);
    const paystackEmail =
      this.paystack.getMerchantPayerEmail?.() || "billing@archeaxon.com";
    const reference = `CBSALE-${randomBytes(12).toString("hex")}`;
    const salePayload: CreateSaleDto & { taxRatePercentSnapshot?: number } = {
      ...quote.sale,
      paymentMethod: PaymentMethod.MPESA,
      paidAmount: amount,
      offlineId: `paystack-${reference}`,
      ...(quote.taxRatePercent != null
        ? { taxRatePercentSnapshot: quote.taxRatePercent }
        : {}),
    };
    try {
      const charge = await this.prisma.$transaction(async (tx) => {
        // A lost client request must not start another open prompt for the same
        // cashier and branch. Serialize this check with charge creation.
        const lockKey = `merchant-sale:${actor.tenantId}:${salePayload.branchId}:${actor.sub}`;
        await tx.$queryRaw`SELECT pg_advisory_xact_lock(hashtextextended(${lockKey}, 0))`;

        const sameRequest = await tx.merchantCharge.findUnique({
          where: {
            tenantId_requestId: {
              tenantId: actor.tenantId,
              requestId: input.requestId,
            },
          },
        });
        if (sameRequest) {
          this.assertSameSaleRequest(sameRequest, actor, input);
          return { existing: sameRequest };
        }

        const openCharge = await tx.merchantCharge.findFirst({
          where: {
            tenantId: actor.tenantId,
            branchId: salePayload.branchId,
            cashierId: actor.sub,
            purpose: "SALE",
            status: { in: ["PENDING", "SETTLING", "NEEDS_REVIEW"] },
          },
          orderBy: { createdAt: "desc" },
          select: { reference: true },
        });
        if (openCharge) {
          throw new ConflictException(
            `An earlier M-Pesa payment is still open (${openCharge.reference}). Check it in Payments before starting another request.`,
          );
        }

        return {
          created: await tx.merchantCharge.create({
            data: {
              tenantId: actor.tenantId,
              requestId: input.requestId,
              branchId: salePayload.branchId,
              cashierId: actor.sub,
              reference,
              subaccountCode: payout.row.subaccountCode,
              amount: new Prisma.Decimal(amount),
              phone,
              paystackEmail,
              salePayload: salePayload as unknown as Prisma.InputJsonValue,
            },
          }),
        };
      });
      if ("existing" in charge) return this.presentStart(charge.existing);
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === "P2002"
      ) {
        const concurrent = await this.prisma.merchantCharge.findUnique({
          where: {
            tenantId_requestId: {
              tenantId: actor.tenantId,
              requestId: input.requestId,
            },
          },
        });
        if (concurrent) {
          this.assertSameSaleRequest(concurrent, actor, input);
          return this.presentStart(concurrent);
        }
      }
      throw error;
    }

    try {
      const prompt = await this.paystack.createMerchantMpesaCharge({
        email: paystackEmail,
        amountKes: amount,
        phone,
        reference,
        subaccountCode: payout.row.subaccountCode,
        tenantId: actor.tenantId,
        businessName: (
          await this.prisma.tenant.findUnique({
            where: { id: actor.tenantId },
            select: { name: true },
          })
        )?.name,
      });
      if (prompt.reference !== reference) {
        await this.prisma.merchantCharge.update({
          where: { reference },
          data: {
            status: "NEEDS_REVIEW",
            providerStatus: "reference_mismatch",
          },
        });
        throw new ServiceUnavailableException(
          "Paystack returned an unexpected payment reference",
        );
      }
      await this.prisma.merchantCharge.update({
        where: { reference },
        data: { providerStatus: prompt.status },
      });
      return {
        reference,
        status: "PENDING",
        amount,
        message:
          prompt.display_text ??
          "Approve the M-Pesa prompt on the customer phone",
      };
    } catch (error) {
      // A network timeout can happen after Paystack accepted a charge. Keep
      // this reference queryable so a retry cannot prompt the customer twice.
      if (error instanceof ServiceUnavailableException) throw error;
      if (
        error instanceof HttpException &&
        error.getStatus() >= 400 &&
        error.getStatus() < 500
      ) {
        await this.prisma.merchantCharge.update({
          where: { reference },
          data: { status: "FAILED", providerStatus: "initiation_rejected" },
        });
        throw new BadRequestException(error.message);
      }
      await this.prisma.merchantCharge.update({
        where: { reference },
        data: { providerStatus: "initiation_unknown" },
      });
      return {
        reference,
        status: "PENDING",
        amount,
        message:
          "Payment request could not be confirmed yet. Check this reference before retrying.",
      };
    }
  }

  async startReceivableMpesa(
    actor: Actor,
    input: StartMerchantReceivableMpesaDto,
  ) {
    const prior = await this.prisma.merchantCharge.findUnique({
      where: {
        tenantId_requestId: {
          tenantId: actor.tenantId,
          requestId: input.requestId,
        },
      },
    });
    if (prior) {
      this.assertSameReceivableRequest(prior, actor, input);
      return this.presentStart(prior);
    }

    const account = await this.prisma.merchantPaymentAccount.findUnique({
      where: { tenantId: actor.tenantId },
    });
    if (!account) {
      throw new ConflictException(
        "Add your business payout account in Customer payments to accept M-Pesa debt payments.",
      );
    }
    const payout = await this.refreshPayoutVerification(account);
    if (!payout.paystackVerified || payout.status !== "ACTIVE") {
      throw new ConflictException(
        "Paystack has not verified this business payout account yet. Finish verification in Customer payments to accept M-Pesa debt payments.",
      );
    }
    const receivable =
      input.receivableType === "retail"
        ? await this.prisma.retailReceivable.findFirst({
            where: {
              id: input.receivableId,
              tenantId: actor.tenantId,
              branchId: input.branchId,
            },
            select: { id: true, outstandingAmount: true, status: true },
          })
        : await this.prisma.peerReceivable.findFirst({
            where: {
              id: input.receivableId,
              tenantId: actor.tenantId,
              branchId: input.branchId,
            },
            select: { id: true, outstandingAmount: true, status: true },
          });
    if (!receivable)
      throw new NotFoundException("Receivable was not found for this business");
    if (["PAID", "WRITTEN_OFF", "VOIDED"].includes(receivable.status)) {
      throw new ConflictException("This receivable is already closed");
    }
    if (input.amount > Number(receivable.outstandingAmount)) {
      throw new BadRequestException(
        "Payment amount exceeds outstanding balance",
      );
    }

    const phone = this.normalizePhone(input.phoneNumber);
    const paystackEmail =
      this.paystack.getMerchantPayerEmail?.() || "billing@archeaxon.com";
    const reference = `CBDUE-${randomBytes(12).toString("hex")}`;
    try {
      const charge = await this.prisma.$transaction(async (tx) => {
        // Debt collection may be initiated by more than one cashier. Prevent
        // concurrent prompts from requesting more than the balance due.
        const lockKey = `merchant-receivable:${actor.tenantId}:${input.receivableType}:${input.receivableId}`;
        await tx.$queryRaw`SELECT pg_advisory_xact_lock(hashtextextended(${lockKey}, 0))`;

        const sameRequest = await tx.merchantCharge.findUnique({
          where: {
            tenantId_requestId: {
              tenantId: actor.tenantId,
              requestId: input.requestId,
            },
          },
        });
        if (sameRequest) {
          this.assertSameReceivableRequest(sameRequest, actor, input);
          return { existing: sameRequest };
        }

        const currentReceivable =
          input.receivableType === "retail"
            ? await tx.retailReceivable.findFirst({
                where: {
                  id: input.receivableId,
                  tenantId: actor.tenantId,
                  branchId: input.branchId,
                },
                select: { outstandingAmount: true, status: true },
              })
            : await tx.peerReceivable.findFirst({
                where: {
                  id: input.receivableId,
                  tenantId: actor.tenantId,
                  branchId: input.branchId,
                },
                select: { outstandingAmount: true, status: true },
              });
        if (!currentReceivable)
          throw new NotFoundException(
            "Receivable was not found for this business",
          );
        if (
          ["PAID", "WRITTEN_OFF", "VOIDED"].includes(currentReceivable.status)
        ) {
          throw new ConflictException("This receivable is already closed");
        }

        const pending = await tx.merchantCharge.aggregate({
          where: {
            tenantId: actor.tenantId,
            purpose: "RECEIVABLE",
            receivableType: input.receivableType,
            receivableId: input.receivableId,
            status: { in: ["PENDING", "SETTLING", "NEEDS_REVIEW"] },
          },
          _sum: { amount: true },
        });
        const outstandingCents = Math.round(
          Number(currentReceivable.outstandingAmount) * 100,
        );
        const pendingCents = Math.round(Number(pending._sum.amount ?? 0) * 100);
        const requestedCents = Math.round(input.amount * 100);
        if (requestedCents + pendingCents > outstandingCents) {
          throw new ConflictException(
            pendingCents > 0
              ? "Another M-Pesa request is already open for this balance. Check it before requesting another payment."
              : "Payment amount exceeds outstanding balance",
          );
        }

        return {
          created: await tx.merchantCharge.create({
            data: {
              tenantId: actor.tenantId,
              requestId: input.requestId,
              branchId: input.branchId,
              cashierId: actor.sub,
              reference,
              subaccountCode: payout.row.subaccountCode,
              amount: new Prisma.Decimal(input.amount),
              phone,
              paystackEmail,
              salePayload: {},
              purpose: "RECEIVABLE",
              receivableType: input.receivableType,
              receivableId: input.receivableId,
            },
          }),
        };
      });
      if ("existing" in charge) return this.presentStart(charge.existing);
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === "P2002"
      ) {
        const concurrent = await this.prisma.merchantCharge.findUnique({
          where: {
            tenantId_requestId: {
              tenantId: actor.tenantId,
              requestId: input.requestId,
            },
          },
        });
        if (concurrent) {
          this.assertSameReceivableRequest(concurrent, actor, input);
          return this.presentStart(concurrent);
        }
      }
      throw error;
    }

    try {
      const prompt = await this.paystack.createMerchantMpesaCharge({
        email: paystackEmail,
        amountKes: input.amount,
        phone,
        reference,
        subaccountCode: payout.row.subaccountCode,
        tenantId: actor.tenantId,
        businessName: (
          await this.prisma.tenant.findUnique({
            where: { id: actor.tenantId },
            select: { name: true },
          })
        )?.name,
      });
      if (prompt.reference !== reference) {
        await this.prisma.merchantCharge.update({
          where: { reference },
          data: {
            status: "NEEDS_REVIEW",
            providerStatus: "reference_mismatch",
          },
        });
        throw new ServiceUnavailableException(
          "Paystack returned an unexpected payment reference",
        );
      }
      await this.prisma.merchantCharge.update({
        where: { reference },
        data: { providerStatus: prompt.status },
      });
      return {
        reference,
        status: "PENDING",
        amount: input.amount,
        entityType: "RECEIVABLE",
        message:
          prompt.display_text ??
          "Approve the M-Pesa prompt on the customer phone",
      };
    } catch (error) {
      if (error instanceof ServiceUnavailableException) throw error;
      if (
        error instanceof HttpException &&
        error.getStatus() >= 400 &&
        error.getStatus() < 500
      ) {
        await this.prisma.merchantCharge.update({
          where: { reference },
          data: { status: "FAILED", providerStatus: "initiation_rejected" },
        });
        throw new BadRequestException(error.message);
      }
      await this.prisma.merchantCharge.update({
        where: { reference },
        data: { providerStatus: "initiation_unknown" },
      });
      return {
        reference,
        status: "PENDING",
        amount: input.amount,
        entityType: "RECEIVABLE",
        message:
          "Payment request could not be confirmed yet. Check this reference before retrying.",
      };
    }
  }

  async status(actor: Actor, reference: string) {
    const charge = await this.prisma.merchantCharge.findFirst({
      where: { tenantId: actor.tenantId, reference },
    });
    if (!charge)
      throw new NotFoundException("Payment was not found for this business");
    if (charge.status === "COMPLETED" || charge.status === "FAILED")
      return this.presentCharge(charge);
    const lastProviderCheckAt = charge.updatedAt?.getTime?.() ?? 0;
    if (
      Date.now() - lastProviderCheckAt <
      MIN_MERCHANT_CHARGE_CHECK_INTERVAL_MS
    ) {
      return this.presentCharge(charge);
    }
    return this.verifyAndSettle(reference);
  }

  async recentCharges(actor: Actor) {
    const charges = await this.prisma.merchantCharge.findMany({
      where: {
        tenantId: actor.tenantId,
        status: { in: ["PENDING", "SETTLING", "NEEDS_REVIEW"] },
      },
      orderBy: { createdAt: "desc" },
      take: 50,
    });
    return charges.map((charge) => ({
      ...this.presentCharge(charge),
      createdAt: charge.createdAt,
    }));
  }

  async requestStatus(actor: Actor, requestId: string) {
    const charge = await this.prisma.merchantCharge.findFirst({
      where: {
        tenantId: actor.tenantId,
        cashierId: actor.sub,
        requestId,
        purpose: "SALE",
      },
    });
    if (!charge) return { found: false };
    return { found: true, charge: this.presentCharge(charge) };
  }

  async handleWebhook(event: string, data: { reference?: string }) {
    if (event !== "charge.success" || !data?.reference)
      return { received: true, handled: false };
    const charge = await this.prisma.merchantCharge.findUnique({
      where: { reference: data.reference },
    });
    if (!charge) return { received: true, handled: false };
    await this.verifyAndSettle(charge.reference);
    return { received: true, handled: true };
  }

  private async refreshPayoutVerification(row: MerchantPaymentAccount) {
    const legacyVerified =
      row.status === "ACTIVE" && Boolean(row.accountName?.trim());
    if (typeof this.paystack.getMerchantSubaccount !== "function") {
      return {
        row,
        status:
          row.status === "ACTIVE" && !legacyVerified
            ? "PENDING_VERIFICATION"
            : row.status,
        paystackVerified: legacyVerified,
      };
    }

    try {
      const providerAccount = await this.paystack.getMerchantSubaccount(
        row.subaccountCode,
      );
      if (
        providerAccount.subaccount_code !== row.subaccountCode ||
        typeof providerAccount.is_verified !== "boolean"
      ) {
        return {
          row,
          status: row.status === "ACTIVE" ? "PENDING_VERIFICATION" : row.status,
          paystackVerified: false,
        };
      }

      const paystackVerified =
        providerAccount.is_verified && providerAccount.active !== false;
      const status =
        providerAccount.active === false
          ? "INACTIVE"
          : paystackVerified
            ? "ACTIVE"
            : "PENDING_VERIFICATION";
      const accountName =
        providerAccount.account_name?.trim() || row.accountName;
      const changed = status !== row.status || accountName !== row.accountName;
      const updated = changed
        ? await this.prisma.merchantPaymentAccount.update({
            where: { tenantId: row.tenantId },
            data: { status, accountName },
          })
        : row;
      if (status !== row.status) {
        const onboarding = await this.prisma.tenantOnboarding.findUnique({
          where: { tenantId: row.tenantId },
          select: { id: true },
        });
        if (onboarding) {
          await this.prisma.tenantOnboardingStep.updateMany({
            where: { onboardingId: onboarding.id, key: "activate_payment" },
            data:
              status === "ACTIVE"
                ? {
                    status: "COMPLETED",
                    completedAt: new Date(),
                    deferredAt: null,
                  }
                : { status: "PENDING", completedAt: null, deferredAt: null },
          });
        }
      }
      return { row: updated, status, paystackVerified };
    } catch {
      // Do not authorize a new charge from stale local state when Paystack's
      // current verification status cannot be confirmed.
      return {
        row,
        status: row.status === "ACTIVE" ? "PENDING_VERIFICATION" : row.status,
        paystackVerified: false,
      };
    }
  }

  private async verifyAndSettle(reference: string) {
    const charge = await this.prisma.merchantCharge.findUnique({
      where: { reference },
    });
    if (!charge) throw new NotFoundException("Payment was not found");
    if (charge.status === "COMPLETED" || charge.status === "FAILED")
      return this.presentCharge(charge);

    let verified: Awaited<ReturnType<PaystackService["verifyTransaction"]>>;
    try {
      verified = await this.paystack.verifyTransaction(reference);
    } catch {
      const current = await this.prisma.merchantCharge.findUnique({
        where: { reference },
      });
      return this.presentCharge(current!);
    }

    // Provider checks can overlap with a webhook or another status request.
    // A delayed non-success response must never overwrite a charge already
    // being settled or completed by the other request.
    const updateUnsettled = async (
      data: Prisma.MerchantChargeUpdateManyMutationInput,
    ) => {
      await this.prisma.merchantCharge.updateMany({
        where: {
          id: charge.id,
          status: { in: ["PENDING", "NEEDS_REVIEW"] },
        },
        data,
      });
      const current = await this.prisma.merchantCharge.findUnique({
        where: { reference },
      });
      return this.presentCharge(current!);
    };

    if (
      verified.reference !== reference ||
      verified.currency !== "KES" ||
      verified.amount !== Math.round(Number(charge.amount) * 100)
    ) {
      return updateUnsettled({
        status: "NEEDS_REVIEW",
        providerStatus: "verification_mismatch",
      });
    }
    if (verified.status !== "success") {
      const finalFailure = ["failed", "abandoned", "reversed"].includes(
        verified.status,
      );
      return updateUnsettled({
        status: finalFailure ? "FAILED" : "PENDING",
        providerStatus: verified.status,
      });
    }
    const providerSubaccount =
      typeof verified.subaccount === "string"
        ? verified.subaccount
        : verified.subaccount?.subaccount_code;
    if (providerSubaccount !== charge.subaccountCode) {
      return updateUnsettled({
        status: "NEEDS_REVIEW",
        providerStatus: "settlement_mismatch",
      });
    }

    const stale = new Date(Date.now() - 60_000);
    const settlementToken = randomBytes(24).toString("hex");
    const claimed = await this.prisma.merchantCharge.updateMany({
      where: {
        id: charge.id,
        OR: [
          { status: { in: ["PENDING", "NEEDS_REVIEW"] } },
          { status: "SETTLING", updatedAt: { lt: stale } },
        ],
      },
      data: {
        status: "SETTLING",
        providerStatus: "success",
        settlementToken,
      },
    });
    if (!claimed.count) {
      const current = await this.prisma.merchantCharge.findUnique({
        where: { reference },
      });
      return this.presentCharge(current!);
    }

    try {
      if (charge.purpose === "RECEIVABLE") {
        if (
          !this.finance ||
          !charge.receivableId ||
          (charge.receivableType !== "retail" &&
            charge.receivableType !== "peer")
        ) {
          throw new Error("Receivable charge details are incomplete");
        }
        const paymentDto = {
          branchId: charge.branchId,
          amount: Number(charge.amount),
          method: ReceivablePaymentMethod.MPESA,
          reference,
          notes: "Paystack M-Pesa debt collection",
          offlineId: `paystack-${reference}`,
        };
        if (!(await this.ownsSettlement(reference, settlementToken))) {
          const current = await this.prisma.merchantCharge.findUnique({
            where: { reference },
          });
          return this.presentCharge(current!);
        }
        const payment =
          charge.receivableType === "retail"
            ? await this.finance.recordRetailPayment(
                charge.cashierId,
                charge.tenantId,
                charge.receivableId,
                paymentDto,
                true,
              )
            : await this.finance.recordPeerPayment(
                charge.cashierId,
                charge.tenantId,
                charge.receivableId,
                paymentDto,
                true,
              );
        const completed = await this.completeMerchantCharge(
          reference,
          settlementToken,
          { receivablePaymentId: payment.id },
        );
        return this.presentCharge(completed);
      }

      const storedSalePayload =
        charge.salePayload as unknown as CreateSaleDto & {
          taxRatePercentSnapshot?: number;
        };
      const { taxRatePercentSnapshot, ...salePayload } = storedSalePayload;
      const sale = await this.sales.createSale(
        charge.cashierId,
        charge.tenantId,
        salePayload,
        {
          verifiedMerchantMpesa: true,
          ...(taxRatePercentSnapshot != null ? { taxRatePercentSnapshot } : {}),
        },
      );
      const completed = await this.completeMerchantSaleCharge(
        reference,
        settlementToken,
        sale,
        charge.amount,
      );
      return this.presentCharge(completed);
    } catch {
      // The customer's payment is real. Preserve it for reconciliation if
      // stock or a database error prevents receipt creation after the charge.
      await this.prisma.merchantCharge.updateMany({
        where: {
          id: charge.id,
          status: "SETTLING",
          settlementToken,
        },
        data: {
          status: "NEEDS_REVIEW",
          providerStatus: "paid_receipt_pending",
          settlementToken: null,
        },
      });
      const current = await this.prisma.merchantCharge.findUnique({
        where: { reference },
      });
      return this.presentCharge(current!);
    }
  }

  private async ownsSettlement(reference: string, settlementToken: string) {
    const current = await this.prisma.merchantCharge.findUnique({
      where: { reference },
      select: { status: true, settlementToken: true },
    });
    return (
      current?.status === "SETTLING" &&
      current.settlementToken === settlementToken
    );
  }

  private async completeMerchantCharge(
    reference: string,
    settlementToken: string,
    data: Prisma.MerchantChargeUpdateInput,
  ) {
    return this.prisma.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT id FROM merchant_charges WHERE reference = ${reference} FOR UPDATE`;
      const current = await tx.merchantCharge.findUnique({
        where: { reference },
      });
      if (!current) throw new NotFoundException("Payment was not found");
      if (
        current.status !== "SETTLING" ||
        current.settlementToken !== settlementToken
      ) {
        return current;
      }
      return tx.merchantCharge.update({
        where: { id: current.id },
        data: {
          ...data,
          status: "COMPLETED",
          settlementToken: null,
        },
      });
    });
  }

  private async completeMerchantSaleCharge(
    reference: string,
    settlementToken: string,
    sale: { id: string; receiptNumber: string },
    amount: Prisma.Decimal,
  ) {
    return this.prisma.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT id FROM merchant_charges WHERE reference = ${reference} FOR UPDATE`;
      const current = await tx.merchantCharge.findUnique({
        where: { reference },
      });
      if (!current) throw new NotFoundException("Payment was not found");
      if (
        current.status !== "SETTLING" ||
        current.settlementToken !== settlementToken
      ) {
        return current;
      }

      // Serialize the lookup-and-create pair by provider reference. A stale
      // settlement lease may overlap a retry, and Payment.transactionId is
      // indexed but intentionally not globally unique for other providers.
      await tx.$queryRaw`SELECT pg_advisory_xact_lock(hashtextextended(${reference}, 0))`;
      const payment = await tx.payment.findFirst({
        where: { saleId: sale.id, transactionId: reference },
        select: { id: true },
      });
      if (!payment) {
        await tx.payment.create({
          data: {
            saleId: sale.id,
            method: PaymentMethod.MPESA,
            amount,
            status: PaymentStatus.COMPLETED,
            transactionId: reference,
            paidAt: new Date(),
          },
        });
      }
      return tx.merchantCharge.update({
        where: { id: current.id },
        data: {
          status: "COMPLETED",
          saleId: sale.id,
          receiptNumber: sale.receiptNumber,
          settlementToken: null,
        },
      });
    });
  }

  private normalizePhone(value: string) {
    const digits = value.replace(/\D/g, "");
    if (digits.startsWith("0")) return `+254${digits.slice(1)}`;
    if (digits.startsWith("254")) return `+${digits}`;
    return `+254${digits}`;
  }

  private assertSameSaleRequest(
    charge: {
      purpose?: string;
      cashierId: string;
      branchId: string;
      phone: string;
      amount: Prisma.Decimal;
      salePayload: Prisma.JsonValue;
    },
    actor: Actor,
    input: StartMerchantMpesaDto,
  ) {
    const original = charge.salePayload as unknown as CreateSaleDto;
    const requested = input.sale;
    const sameItems =
      Array.isArray(original?.items) &&
      Array.isArray(requested?.items) &&
      original.items.length === requested.items.length &&
      original.items.every((item, index) => {
        const retry = requested.items[index];
        return (
          item.productId === retry.productId &&
          Number(item.quantity) === Number(retry.quantity) &&
          Number(item.unitPrice) ===
            Number(retry.unitPrice ?? item.unitPrice) &&
          Number(item.discount ?? 0) === Number(retry.discount ?? 0) &&
          (item.unit ?? null) === (retry.unit ?? null) &&
          Number(item.quantityPerUnit ?? 1) ===
            Number(retry.quantityPerUnit ?? 1)
        );
      });
    const sameCheckout =
      charge.purpose === "SALE" &&
      charge.cashierId === actor.sub &&
      charge.branchId === requested?.branchId &&
      charge.phone === this.normalizePhone(input.phoneNumber) &&
      requested?.paymentMethod === PaymentMethod.MPESA &&
      !requested.tenders?.length &&
      original?.branchId === requested.branchId &&
      (original.customerId ?? null) === (requested.customerId ?? null) &&
      Number(original.discountAmount ?? 0) ===
        Number(requested.discountAmount ?? 0) &&
      (original.couponCode?.trim() || null) ===
        (requested.couponCode?.trim() || null) &&
      Math.round(Number(charge.amount) * 100) ===
        Math.round(Number(requested.paidAmount ?? charge.amount) * 100) &&
      sameItems;

    if (!sameCheckout) {
      throw new ConflictException(
        "This payment request key already belongs to a different checkout. Check the original payment before retrying.",
      );
    }
  }

  private assertSameReceivableRequest(
    charge: {
      purpose?: string;
      cashierId: string;
      branchId: string;
      phone: string;
      amount: Prisma.Decimal;
      receivableType?: string | null;
      receivableId?: string | null;
    },
    actor: Actor,
    input: StartMerchantReceivableMpesaDto,
  ) {
    const sameRequest =
      charge.purpose === "RECEIVABLE" &&
      charge.cashierId === actor.sub &&
      charge.branchId === input.branchId &&
      charge.phone === this.normalizePhone(input.phoneNumber) &&
      charge.receivableId === input.receivableId &&
      charge.receivableType === input.receivableType &&
      Math.round(Number(charge.amount) * 100) ===
        Math.round(input.amount * 100);

    if (!sameRequest) {
      throw new ConflictException(
        "This payment request key already belongs to a different debt payment. Check the original payment before retrying.",
      );
    }
  }

  private presentCharge(charge: {
    reference: string;
    status: string;
    providerStatus: string | null;
    amount: Prisma.Decimal;
    saleId: string | null;
    receiptNumber: string | null;
    purpose?: string;
    receivableType?: string | null;
    receivableId?: string | null;
    receivablePaymentId?: string | null;
  }) {
    return {
      reference: charge.reference,
      status: charge.status,
      providerStatus: charge.providerStatus,
      amount: Number(charge.amount),
      purpose: charge.purpose ?? "SALE",
      receivableType: charge.receivableType ?? null,
      receivableId: charge.receivableId ?? null,
      receivablePaymentId: charge.receivablePaymentId ?? null,
      saleId: charge.saleId,
      receiptNumber: charge.receiptNumber,
    };
  }

  private presentStart(charge: {
    reference: string;
    status: string;
    amount: Prisma.Decimal;
    purpose?: string;
    receivableType?: string | null;
    receivableId?: string | null;
  }) {
    return {
      reference: charge.reference,
      status: charge.status,
      amount: Number(charge.amount),
      purpose: charge.purpose ?? "SALE",
      receivableType: charge.receivableType ?? null,
      receivableId: charge.receivableId ?? null,
      message:
        "This payment request already exists. Check its status before retrying.",
    };
  }
}
