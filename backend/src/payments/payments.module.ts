import { Module } from '@nestjs/common';
import { PaymentsController } from './payments.controller';
import { ManualPaymentController } from './controllers/manual-payment.controller';
import { BulkPaymentsController } from './controllers/bulk-payments.controller';
import { DarajaService } from './services/daraja.service';
import { PesapalService } from './services/pesapal.service';
import { TouristTapService } from './services/touristtap.service';
import { ManualPaymentService } from './services/manual-payment.service';
import { BulkPaymentService } from './services/bulk-payment.service';

@Module({
  controllers: [PaymentsController, ManualPaymentController, BulkPaymentsController],
  providers: [DarajaService, PesapalService, TouristTapService, ManualPaymentService, BulkPaymentService],
  exports: [DarajaService, PesapalService, TouristTapService, ManualPaymentService, BulkPaymentService],
})
export class PaymentsModule {}
