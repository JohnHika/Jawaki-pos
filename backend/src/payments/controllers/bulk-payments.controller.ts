import {
  Controller,
  Get,
  Post,
  Body,
  Param,
  Query,
  UseGuards,
  Request,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { JwtAuthGuard } from '../../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../../auth/guards/roles.guard';
import { Roles } from '../../auth/decorators/roles.decorator';
import { UserRole } from '@prisma/client';
import { BulkPaymentService } from '../services/bulk-payment.service';
import {
  ProcessBulkPaymentDto,
  ProcessBulkCreditPaymentDto,
  BulkPaymentQueryDto,
} from '../dto/bulk-payment.dto';

@Controller('payments/bulk')
@ApiTags('Bulk Payments')
@UseGuards(JwtAuthGuard, RolesGuard)
@ApiBearerAuth()
export class BulkPaymentsController {
  constructor(private readonly bulkPaymentService: BulkPaymentService) {}

  @Post('process')
  @ApiOperation({ summary: 'Process bulk payments for existing sales' })
  @Roles(UserRole.CASHIER, UserRole.SUPERVISOR, UserRole.MANAGER, UserRole.ADMIN)
  async processBulkPayment(
    @Request() req: any,
    @Body() dto: ProcessBulkPaymentDto,
  ) {
    return this.bulkPaymentService.processBulkPayment(
      req.user.userId,
      req.user.tenantId,
      dto,
    );
  }

  @Post('credit')
  @ApiOperation({ summary: 'Convert multiple sales to credit/payment-later' })
  @Roles(UserRole.CASHIER, UserRole.SUPERVISOR, UserRole.MANAGER, UserRole.ADMIN)
  async processBulkCredit(
    @Request() req: any,
    @Body() dto: ProcessBulkCreditPaymentDto,
  ) {
    return this.bulkPaymentService.processBulkCreditPayment(
      req.user.userId,
      req.user.tenantId,
      dto,
    );
  }

  @Get('status/:batchId')
  @ApiOperation({ summary: 'Get bulk payment batch status' })
  @Roles(UserRole.CASHIER, UserRole.SUPERVISOR, UserRole.MANAGER, UserRole.ADMIN)
  async getBulkPaymentStatus(@Param('batchId') batchId: string) {
    const status = await this.bulkPaymentService.getBulkPaymentStatus(batchId);

    if (!status) {
      return { error: 'Batch not found' };
    }

    return status;
  }

  @Get('history')
  @ApiOperation({ summary: 'Get bulk payment history' })
  @Roles(UserRole.SUPERVISOR, UserRole.MANAGER, UserRole.ADMIN)
  async getBulkPaymentHistory(
    @Request() req: any,
    @Query() query: BulkPaymentQueryDto,
  ) {
    return this.bulkPaymentService.getBulkPaymentHistory(req.user.tenantId, query);
  }
}
