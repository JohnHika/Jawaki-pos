import { Module } from "@nestjs/common";
import { PaymentsController } from "./payments.controller";
import { JengaPaymentService } from "./jenga-payment.service";

@Module({
  controllers: [PaymentsController],
  providers: [JengaPaymentService],
})
export class PaymentsModule {}
