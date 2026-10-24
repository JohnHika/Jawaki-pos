import { ConfigService } from "@nestjs/config";
import { PesapalPaymentService } from "./pesapal-payment.service";

describe("PesapalPaymentService.getTransactionStatus", () => {
  let service: PesapalPaymentService;
  let authedGet: jest.SpyInstance;

  beforeEach(() => {
    service = new PesapalPaymentService({
      get: jest.fn(),
    } as unknown as ConfigService);
    authedGet = jest.spyOn(service as any, "authedGet");
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it("normalizes the documented API 3.0 recurring response", async () => {
    authedGet.mockResolvedValue({
      payment_status_description: "Completed",
      status_code: 1,
      order_tracking_id: "track-1",
      amount: 3200,
      currency: "KES",
      merchant_reference: "provider-order-ref",
      subscription_transaction_info: {
        account_reference: "mandate-account",
        amount: 3200,
        correlation_id: 111222,
      },
    });

    const result = await service.getTransactionStatus("track-1");

    expect(result).toMatchObject({
      orderTrackingId: "track-1",
      paymentStatus: "COMPLETED",
      paymentStatusCode: 1,
      amount: 3200,
      currency: "KES",
      merchantReference: "provider-order-ref",
      subscriptionTransactionInfo: {
        accountReference: "mandate-account",
        amount: 3200,
        correlationId: "111222",
      },
    });
  });

  it("keeps an unknown status unknown when the provider omits status fields", async () => {
    authedGet.mockResolvedValue({ order_tracking_id: "track-1", amount: 3200 });

    const result = await service.getTransactionStatus("track-1");

    expect(result.paymentStatus).toBe("");
  });
});
