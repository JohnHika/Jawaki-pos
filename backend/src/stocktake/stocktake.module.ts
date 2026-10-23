import { Module } from '@nestjs/common';
import { AccountabilityModule } from '../accountability/accountability.module';
import { StocktakeController } from './stocktake.controller';
import { StocktakeService } from './stocktake.service';

@Module({
  imports: [AccountabilityModule],
  controllers: [StocktakeController],
  providers: [StocktakeService],
  exports: [StocktakeService],
})
export class StocktakeModule {}
