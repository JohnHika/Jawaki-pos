import { Module } from '@nestjs/common';
import { PaymentsController } from './payments.controller';
import { DarajaService } from './services/daraja.service';
import { PesapalService } from './services/pesapal.service';
import { TouristTapService } from './services/touristtap.service';

@Module({
  controllers: [PaymentsController],
  providers: [DarajaService, PesapalService, TouristTapService],
  exports: [DarajaService, PesapalService, TouristTapService],
})
export class PaymentsModule {}
