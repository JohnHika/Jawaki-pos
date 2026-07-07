import { Controller, Get, Put, Body, Param, Query, UseGuards, ParseUUIDPipe } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth } from '@nestjs/swagger';
import { CashFlowService } from './cash-flow.service';
import { UpdateCashSettingsDto, CashLedgerQueryDto, AvailableCashResponseDto } from './dto/cash-flow.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';

@ApiTags('cash-flow')
@Controller({ path: 'cash-flow', version: '1' })
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class CashFlowController {
  constructor(private readonly cashFlowService: CashFlowService) {}

  @Get('settings/:branchId')
  @ApiOperation({ summary: 'Get branch cash flow mode' })
  @ApiResponse({ status: 200, description: 'Current cash flow settings' })
  async getSettings(@Param('branchId', ParseUUIDPipe) branchId: string) {
    return this.cashFlowService.getSettings(branchId);
  }

  @Put('settings/:branchId')
  @ApiOperation({ summary: 'Set branch cash flow mode' })
  @ApiResponse({ status: 200, description: 'Updated cash flow settings' })
  async updateSettings(
    @Param('branchId', ParseUUIDPipe) branchId: string,
    @Body() dto: UpdateCashSettingsDto,
  ) {
    return this.cashFlowService.updateSettings(branchId, dto.mode);
  }

  @Get('available/:branchId')
  @ApiOperation({ summary: 'Get cash available to restock for a branch' })
  @ApiResponse({ status: 200, description: 'Available cash breakdown', type: AvailableCashResponseDto })
  async getAvailable(@Param('branchId', ParseUUIDPipe) branchId: string) {
    return this.cashFlowService.getAvailableCash(branchId);
  }

  @Get('ledger/:branchId')
  @ApiOperation({ summary: 'Get paginated cash ledger entries for a branch' })
  @ApiResponse({ status: 200, description: 'Paginated ledger entries' })
  async getLedger(
    @Param('branchId', ParseUUIDPipe) branchId: string,
    @Query() query: CashLedgerQueryDto,
  ) {
    return this.cashFlowService.getLedger(branchId, query);
  }
}
