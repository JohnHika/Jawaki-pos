import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Logger,
  Post,
  Query,
  Req,
  UseGuards,
} from "@nestjs/common";
import { ApiBearerAuth, ApiOperation, ApiQuery, ApiTags } from "@nestjs/swagger";
import { IsIn, IsNotEmpty, IsOptional, IsString } from "class-validator";
import { JwtAuthGuard } from "../auth/guards/jwt-auth.guard";
import { RolesGuard } from "../auth/guards/roles.guard";
import { Roles } from "../auth/decorators/roles.decorator";
import { LegacyUserRole } from "@prisma/client";
import { PrismaService } from "../common/prisma/prisma.service";
import { PesapalRecurringService } from "./pesapal-recurring.service";

export class StartCardSubscriptionDto {
  @IsIn(["MONTHLY", "YEARLY"])
  billingCycle: "MONTHLY" | "YEARLY";

  @IsOptional()
  @IsString()
  planId?: string;
}

/**
 * Pesapal recurring card (auto-renew) endpoints.
 *
 * Lives in its own file (not billing.controller.ts) because the main billing
 * controller is owned by another workstream; registration happens through
 * CardBillingModule only.
 */
@ApiTags("billing")
@Controller({ path: "billing/card", version: "1" })
export class CardBillingController {
  private readonly logger = new Logger(CardBillingController.name);

  constructor(
    private readonly cardBilling: PesapalRecurringService,
    private readonly prisma: PrismaService,
  ) {}

  /** Admin starts a Pesapal card subscription; response carries the redirect URL. */
  @Post("subscribe")
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(LegacyUserRole.ADMIN)
  @ApiBearerAuth("JWT-auth")
  @ApiOperation({ summary: "Start a Pesapal card subscription (returns redirect URL)" })
  subscribe(@Req() req: any, @Body() dto: StartCardSubscriptionDto) {
    return this.cardBilling.startCardSubscription(
      req.user.tenantId,
      dto.planId ?? "CORE",
      dto.billingCycle,
    );
  }

  /**
   * PUBLIC: Pesapal cannot authenticate. The query params are treated as a
   * trigger only — the payment is settled exclusively after an authenticated
   * GetTransactionStatus call (same pattern as the Jenga callback).
   * Rate limiting is provided by the global ThrottlerModule.
   */
  @Post("ipn")
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: "Pesapal recurring payment notification (IPN) webhook" })
  @ApiQuery({ name: "OrderNotificationType", required: false })
  @ApiQuery({ name: "OrderTrackingId", required: false })
  @ApiQuery({ name: "OrderMerchantReference", required: false })
  ipn(@Query() query: Record<string, unknown>) {
    this.logger.log(`Pesapal IPN received: ${JSON.stringify(query)}`);
    return this.cardBilling.handleRecurringIpn(query);
  }

  /** Admin cancels the card subscription (removes the token mapping). */
  @Post("cancel")
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(LegacyUserRole.ADMIN)
  @ApiBearerAuth("JWT-auth")
  @ApiOperation({ summary: "Cancel the Pesapal card subscription" })
  cancel(@Req() req: any) {
    return this.cardBilling.cancelCardSubscription(req.user.tenantId);
  }

  /** Admin: current card-subscription state (for settings screens). */
  @Get("status")
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(LegacyUserRole.ADMIN)
  @ApiBearerAuth("JWT-auth")
  @ApiOperation({ summary: "Get the current Pesapal card subscription state" })
  async status(@Req() req: any) {
    const token = await this.prisma.subscriptionCardToken.findUnique({
      where: { tenantId: req.user.tenantId },
    });
    if (!token) return { subscribed: false };
    return {
      subscribed: token.status !== "CANCELLED",
      status: token.status,
      plan: token.plan,
      billingCycle: token.billingCycle,
      createdAt: token.createdAt,
      cancelledAt: token.cancelledAt,
    };
  }
}