import {
  Controller,
  Get,
  Post,
  Body,
  Param,
  Query,
  UseGuards,
  Request,
  BadRequestException,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { JwtAuthGuard } from '../../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../../auth/guards/roles.guard';
import { Roles } from '../../auth/decorators/roles.decorator';
import { UserRole } from '@prisma/client';
import { ManualPaymentService } from '../services/manual-payment.service';
import {
  CreateManualPaymentRequestDto,
  ApproveManualPaymentDto,
  RejectManualPaymentDto,
  ManualPaymentQueryDto,
} from '../dto/manual-payment.dto';

@Controller('payments/manual')
@ApiTags('Manual Payments')
@UseGuards(JwtAuthGuard, RolesGuard)
@ApiBearerAuth()
export class ManualPaymentController {
  constructor(private readonly manualPaymentService: ManualPaymentService) {}

  @Post('request')
  @ApiOperation({ summary: 'Create a manual payment request' })
  @Roles(UserRole.CASHIER, UserRole.SUPERVISOR, UserRole.MANAGER, UserRole.ADMIN)
  async createRequest(@Request() req: any, @Body() dto: CreateManualPaymentRequestDto) {
    return this.manualPaymentService.createRequest(req.user.userId, req.user.tenantId, dto);
  }

  @Get('pending')
  @ApiOperation({ summary: 'Get pending manual payment requests' })
  @Roles(UserRole.SUPERVISOR, UserRole.MANAGER, UserRole.ADMIN)
  async getPendingRequests(@Request() req: any, @Query() query: ManualPaymentQueryDto) {
    return this.manualPaymentService.getPendingRequests(req.user.tenantId, query);
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get manual payment request details' })
  @Roles(UserRole.SUPERVISOR, UserRole.MANAGER, UserRole.ADMIN)
  async getRequest(@Request() req: any, @Param('id') id: string) {
    return this.manualPaymentService.getRequest(id, req.user.tenantId);
  }

  @Post(':id/approve')
  @ApiOperation({ summary: 'Approve a manual payment request' })
  @Roles(UserRole.MANAGER, UserRole.ADMIN)
  async approveRequest(
    @Request() req: any,
    @Param('id') id: string,
    @Body() dto: ApproveManualPaymentDto,
  ) {
    return this.manualPaymentService.approveRequest(id, req.user.userId, req.user.tenantId, dto);
  }

  @Post(':id/reject')
  @ApiOperation({ summary: 'Reject a manual payment request' })
  @Roles(UserRole.MANAGER, UserRole.ADMIN)
  async rejectRequest(
    @Request() req: any,
    @Param('id') id: string,
    @Body() dto: RejectManualPaymentDto,
  ) {
    return this.manualPaymentService.rejectRequest(id, req.user.userId, req.user.tenantId, dto);
  }

  @Post(':id/complete')
  @ApiOperation({ summary: 'Mark manual payment as completed' })
  @Roles(UserRole.CASHIER, UserRole.SUPERVISOR, UserRole.MANAGER, UserRole.ADMIN)
  async completeRequest(
    @Request() req: any,
    @Param('id') id: string,
    @Body() dto?: { notes?: string },
  ) {
    return this.manualPaymentService.completeRequest(id, req.user.userId, req.user.tenantId, dto);
  }

  @Post(':id/cancel')
  @ApiOperation({ summary: 'Cancel (delete) a pending manual payment request' })
  @Roles(UserRole.CASHIER, UserRole.SUPERVISOR, UserRole.MANAGER, UserRole.ADMIN)
  async cancelRequest(@Request() req: any, @Param('id') id: string) {
    return this.manualPaymentService.deleteRequest(id, req.user.userId, req.user.tenantId);
  }
}
