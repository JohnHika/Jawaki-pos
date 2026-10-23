import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PermissionsGuard } from '../auth/guards/permissions.guard';
import { RequirePermissions } from '../auth/decorators/require-permissions.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { CouponsService } from './coupons.service';
import {
  CheckCouponDto,
  CouponReportQueryDto,
  CreateCouponDto,
  UpdateCouponDto,
} from './dto/coupons.dto';

@ApiTags('coupons')
@Controller({ path: 'coupons', version: '1' })
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class CouponsController {
  constructor(private readonly coupons: CouponsService) {}

  @Get('till')
  @ApiOperation({ summary: 'Redeemable coupons, for the till to apply offline' })
  till(@CurrentUser('tenantId') tenantId: string) {
    return this.coupons.tillList(tenantId);
  }

  @Post('check')
  @ApiOperation({ summary: 'Check a code against a cart and get the discount it gives' })
  check(@CurrentUser('tenantId') tenantId: string, @Body() dto: CheckCouponDto) {
    return this.coupons.check(tenantId, dto);
  }

  @Get()
  @UseGuards(PermissionsGuard)
  @RequirePermissions('coupons.view')
  @ApiOperation({ summary: 'All coupons for this company' })
  list(@CurrentUser('tenantId') tenantId: string) {
    return this.coupons.list(tenantId);
  }

  @Get('report')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('coupons.view')
  @ApiOperation({ summary: 'How many coupons were used and what they cost, by code and cashier' })
  report(@CurrentUser('tenantId') tenantId: string, @Query() query: CouponReportQueryDto) {
    return this.coupons.report(tenantId, query.days ?? 30);
  }

  @Post()
  @UseGuards(PermissionsGuard)
  @RequirePermissions('coupons.manage')
  @ApiOperation({ summary: 'Create a coupon' })
  create(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Body() dto: CreateCouponDto,
  ) {
    return this.coupons.create(userId, tenantId, dto);
  }

  @Patch(':id')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('coupons.manage')
  @ApiOperation({ summary: 'Change a coupon, or switch it on or off' })
  update(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateCouponDto,
  ) {
    return this.coupons.update(userId, tenantId, id, dto);
  }

  @Delete(':id')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('coupons.manage')
  @ApiOperation({ summary: 'Delete an unused coupon, or switch off one that has been used' })
  remove(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.coupons.remove(userId, tenantId, id);
  }
}
