import { Controller, Get, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { ExchangeRatesService } from './exchange-rates.service';

@ApiTags('market')
@Controller({ path: 'market/rates', version: '1' })
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class ExchangeRatesController {
  constructor(private readonly rates: ExchangeRatesService) {}

  @Get()
  @ApiOperation({ summary: 'KES per 1 unit of the currencies importers deal in' })
  board() {
    return this.rates.getBoard();
  }
}
