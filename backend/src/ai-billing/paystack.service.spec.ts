import { HttpException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { PaystackService } from "./paystack.service";

describe("PaystackService merchant payment requests", () => {
  let fetchSpy: jest.SpyInstance;
  let service: PaystackService;

  beforeEach(() => {
    fetchSpy = jest.spyOn(globalThis, "fetch");
    service = new PaystackService({
      get: jest.fn((key: string) =>
        key === "PAYSTACK_SECRET_KEY" ? "sk_test_unit-test-key" : undefined,
      ),
    } as unknown as ConfigService);
  });

  afterEach(() => {
    fetchSpy.mockRestore();
  });

  it("starts Kenyan M-Pesa charges with the international phone format Paystack documents", async () => {
    fetchSpy.mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        status: true,
        message: "Charge attempted",
        data: { reference: "CBSALE-reference", status: "pay_offline" },
      }),
    } as Response);

    await service.createMerchantMpesaCharge({
      email: "customer@example.test",
      amountKes: 500,
      phone: "+254712345678",
      reference: "CBSALE-reference",
      subaccountCode: "ACCT_shop",
      tenantId: "tenant-1",
      businessName: "Levisa Ventures",
    });

    const request = fetchSpy.mock.calls[0];
    const body = JSON.parse(request[1].body as string);
    expect(request[0]).toBe("https://api.paystack.co/charge");
    expect(body.mobile_money).toEqual({
      phone: "+254712345678",
      provider: "mpesa",
    });
    expect(body.amount).toBe(50000);
    expect(body.currency).toBe("KES");
    expect(body.subaccount).toBe("ACCT_shop");
    expect(body.bearer).toBe("subaccount");
    expect(body.metadata.shopName).toBe("Levisa Ventures");
    expect(body.metadata.custom_fields).toContainEqual({
      display_name: "Shop",
      variable_name: "shop_name",
      value: "Levisa Ventures",
    });
  });

  it("surfaces a useful provider rejection while masking customer contact details", async () => {
    fetchSpy.mockResolvedValue({
      ok: false,
      status: 400,
      json: async () => ({
        status: false,
        message: "Invalid M-Pesa phone 0712345678 for customer@example.test",
        data: null,
      }),
    } as Response);

    let failure: unknown;
    try {
      await service.createMerchantMpesaCharge({
        email: "customer@example.test",
        amountKes: 500,
        phone: "+254712345678",
        reference: "CBSALE-reference",
        subaccountCode: "ACCT_shop",
        tenantId: "tenant-1",
      });
    } catch (error) {
      failure = error;
    }
    expect(failure).toBeInstanceOf(HttpException);
    expect((failure as Error).message).toBe(
      "Paystack rejected this M-Pesa request: Invalid M-Pesa phone [number] for [email]",
    );
    expect((failure as Error).message).not.toContain("0712345678");
    expect((failure as Error).message).not.toContain("customer@example.test");
  });
});
