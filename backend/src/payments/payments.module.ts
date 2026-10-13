import { Module } from "@nestjs/common";
import { AuditModule } from "../audit/audit.module";
import { PaymentsController } from "./payments.controller";
import { ManualPaymentsController } from "./manual-payments.controller";
import { ManualPaymentsService } from "./manual-payments.service";
import { JengaPaymentService } from "./jenga-payment.service";
import { SubscriptionRenewalSettler } from "../billing/subscription-renewal-settler.service";

@Module({
  imports: [AuditModule],
  controllers: [PaymentsController, ManualPaymentsController],
  providers: [JengaPaymentService, SubscriptionRenewalSettler, ManualPaymentsService],
  exports: [JengaPaymentService],
})
export class PaymentsModule {}