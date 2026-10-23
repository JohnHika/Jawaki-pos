import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiProperty, ApiTags } from '@nestjs/swagger';
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
import { IsString, MaxLength, MinLength } from 'class-validator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PermissionsGuard } from '../auth/guards/permissions.guard';
import { RequirePermissions } from '../auth/decorators/require-permissions.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { ReferralsService } from './referrals.service';

export class RedeemCodeDto {
  @ApiProperty({ description: 'A referral code from another shop, or a promo code' })
  @IsString()
  @MinLength(3)
  @MaxLength(40)
  code: string;
}

@ApiTags('referrals')
@Controller({ path: 'referrals', version: '1' })
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class ReferralsController {
  constructor(private readonly referrals: ReferralsService) {}

  @Get('me')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('referrals.view')
  @ApiOperation({ summary: 'Your referral code, what it earns, and the shops you brought in' })
  me(@CurrentUser('tenantId') tenantId: string) {
    return this.referrals.summary(tenantId);
  }

  @Post('redeem')
  @UseGuards(PermissionsGuard, ThrottlerGuard)
  @RequirePermissions('referrals.view')
  @Throttle({ default: { ttl: 60_000, limit: 10 } })
  @ApiOperation({ summary: 'Enter a referral or promo code for your company' })
  redeem(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Body() dto: RedeemCodeDto,
  ) {
    return this.referrals.redeemCode(tenantId, userId, dto.code);
  }
}
