import { Module } from "@nestjs/common";
import { AuditModule } from "../audit/audit.module";
import { PaymentsController } from "./payments.controller";
import { JengaPaymentService } from "./jenga-payment.service";
import { SubscriptionRenewalSettler } from "../billing/subscription-renewal-settler.service";

@Module({
  imports: [AuditModule],
  controllers: [PaymentsController],
  providers: [JengaPaymentService, SubscriptionRenewalSettler],
  exports: [JengaPaymentService],
})
export class PaymentsModule {}
