import { Controller, Get, GoneException, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PermissionsGuard } from '../auth/guards/permissions.guard';
import { RequirePermissions } from '../auth/decorators/require-permissions.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { MpesaService } from './mpesa.service';

@ApiTags('mpesa')
@Controller({ path: 'mpesa', version: '1' })
@UseGuards(JwtAuthGuard, PermissionsGuard)
@ApiBearerAuth('JWT-auth')
export class MpesaController {
  constructor(private readonly mpesa: MpesaService) {}

  @Post('parse')
  @RequirePermissions('mpesa.reconcile')
  @ApiOperation({ summary: 'Retired: M-Pesa text messages are not proof of payment' })
  parse(): never {
    throw this.manualMatchingUnavailable();
  }

  @Post('apply')
  @RequirePermissions('mpesa.reconcile')
  @ApiOperation({ summary: 'Retired: payment balances are changed only after provider verification' })
  apply(): never {
    throw this.manualMatchingUnavailable();
  }

  @Post('ignore')
  @RequirePermissions('mpesa.reconcile')
  @ApiOperation({ summary: 'Retired: M-Pesa text matching is no longer available' })
  ignore(): never {
    throw this.manualMatchingUnavailable();
  }

  @Get('history')
  @RequirePermissions('mpesa.reconcile')
  @ApiOperation({ summary: 'Payments already matched from M-Pesa messages' })
  history(@CurrentUser('tenantId') tenantId: string) {
    return this.mpesa.history(tenantId);
  }

  private manualMatchingUnavailable() {
    return new GoneException(
      'Manual M-Pesa message matching is retired. A copied message cannot verify payment. Send a Paystack M-Pesa request in Finance; the balance updates after Paystack confirms it.',
    );
  }
}
