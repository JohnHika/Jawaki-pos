import { Module } from '@nestjs/common';
import { AccountabilityModule } from '../accountability/accountability.module';
import { ExchangeRatesModule } from '../exchange-rates/exchange-rates.module';
import { InventoryModule } from '../inventory/inventory.module';
import { ImportsController } from './imports.controller';
import { ImportsService } from './imports.service';

@Module({
  imports: [AccountabilityModule, ExchangeRatesModule, InventoryModule],
  controllers: [ImportsController],
  providers: [ImportsService],
  exports: [ImportsService],
})
export class ImportsModule {}
