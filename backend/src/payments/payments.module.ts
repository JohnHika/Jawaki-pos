import { Module } from "@nestjs/common";
import { PaymentsController } from "./payments.controller";
import { JengaPaymentService } from "./jenga-payment.service";
import { SubscriptionRenewalSettler } from "../billing/subscription-renewal-settler.service";

@Module({
  controllers: [PaymentsController],
  providers: [JengaPaymentService, SubscriptionRenewalSettler],
  exports: [JengaPaymentService],
})
export class PaymentsModule {}