import axios from "axios";
import { ConfigService } from "@nestjs/config";
import { ServiceUnavailableException } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { JengaPaymentService } from "./jenga-payment.service";

jest.mock("axios");

const configured: Record<string, string> = {
  JENGA_ENV: "sandbox",
  JENGA_API_KEY: "api-key",
  JENGA_MERCHANT_CODE: "merchant-code",
  JENGA_CONSUMER_SECRET: "secret",
  JENGA_PRIVATE_KEY: "unused-in-callback-tests",
  JENGA_ACCOUNT_NUMBER: "0123456789",
  JENGA_MERCHANT_NAME: "Test Merchant",
  JENGA_CALLBACK_URL: "https://example.test/api/v1/payments/mpesa/callback",
};

describe("JengaPaymentService payment verification", () => {
  const transaction = {
    checkoutRequestId: "ABC123",
    merchantRequestId: "JENGA:ABC123",
    phoneNumber: "254712345678",
    amount: new Prisma.Decimal("100.00"),
    accountReference: "POS-1",
    status: "processing",
    mpesaReceiptNumber: null,
    transactionDate: null,
  };
  let prisma: any;

  beforeEach(() => {
    jest.resetAllMocks();
    prisma = {
      mpesaTransaction: {
        findUnique: jest.fn().mockResolvedValue(transaction),
        update: jest
          .fn()
          .mockImplementation(({ data }: any) =>
            Promise.resolve({ ...transaction, ...data }),
          ),
      },
    };
  });

  it("fails closed when gateway credentials are missing", async () => {
    const service = new JengaPaymentService(
      { get: jest.fn().mockReturnValue(undefined) } as unknown as ConfigService,
      prisma,
    );
    await expect(service.status("ABC123")).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
  });

  it("does not approve a completion callback with a mismatched amount", async () => {
    const service = new JengaPaymentService(
      { get: (key: string) => configured[key] } as ConfigService,
      prisma,
    );
    await service.handleCallback({
      code: 3,
      transactionReference: "ABC123",
      requestAmount: "99.00",
      currency: "KES",
      mobileNumber: "254712345678",
    });
    expect(axios.get).not.toHaveBeenCalled();
    expect(prisma.mpesaTransaction.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ status: "processing" }),
      }),
    );
  });

  it("approves only after the authenticated status query says Paid for the exact amount", async () => {
    const service = new JengaPaymentService(
      { get: (key: string) => configured[key] } as ConfigService,
      prisma,
    );
    (axios.post as jest.Mock).mockResolvedValue({
      data: { accessToken: "token", expiresIn: 3600 },
    });
    (axios.get as jest.Mock).mockResolvedValue({
      data: {
        data: {
          order: { orderStatus: "Paid", amountPaid: "100.00" },
          invoice: { externalReference: "QWE123" },
        },
      },
    });

    await service.handleCallback({
      code: 3,
      transactionReference: "ABC123",
      telcoReference: "QWE123",
      requestAmount: "100.00",
      currency: "KES",
      mobileNumber: "0712345678",
    });

    expect(axios.get).toHaveBeenCalledTimes(1);
    expect(prisma.mpesaTransaction.update).toHaveBeenLastCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ status: "completed" }),
      }),
    );
  });
});
