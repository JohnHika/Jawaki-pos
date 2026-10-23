import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PermissionsGuard } from '../auth/guards/permissions.guard';
import { RequirePermissions } from '../auth/decorators/require-permissions.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { MpesaService } from './mpesa.service';
import { ApplyMpesaDto, IgnoreMpesaDto, ParseMpesaDto } from './dto/mpesa.dto';

@ApiTags('mpesa')
@Controller({ path: 'mpesa', version: '1' })
@UseGuards(JwtAuthGuard, PermissionsGuard)
@ApiBearerAuth('JWT-auth')
export class MpesaController {
  constructor(private readonly mpesa: MpesaService) {}

  @Post('parse')
  @RequirePermissions('mpesa.reconcile')
  @ApiOperation({ summary: 'Read pasted M-Pesa messages and suggest which debt each payment settles' })
  parse(@CurrentUser('tenantId') tenantId: string, @Body() dto: ParseMpesaDto) {
    return this.mpesa.preview(tenantId, dto.text);
  }

  @Post('apply')
  @RequirePermissions('mpesa.reconcile', 'finance.manage_receivables')
  @ApiOperation({ summary: 'Record the payments you confirmed against the matching debts' })
  apply(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Body() dto: ApplyMpesaDto,
  ) {
    return this.mpesa.apply(userId, tenantId, dto);
  }

  @Post('ignore')
  @RequirePermissions('mpesa.reconcile')
  @ApiOperation({ summary: 'Mark payments that are not debt payments so they stop showing up' })
  ignore(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Body() dto: IgnoreMpesaDto,
  ) {
    return this.mpesa.ignore(userId, tenantId, dto);
  }

  @Get('history')
  @RequirePermissions('mpesa.reconcile')
  @ApiOperation({ summary: 'Payments already matched from M-Pesa messages' })
  history(@CurrentUser('tenantId') tenantId: string) {
    return this.mpesa.history(tenantId);
  }
}
