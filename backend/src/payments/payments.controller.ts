import {
  Body,
  GoneException,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  ServiceUnavailableException,
  UseGuards,
} from "@nestjs/common";
import {
  ApiBearerAuth,
  ApiOperation,
  ApiTags,
} from "@nestjs/swagger";
import { JwtAuthGuard } from "../auth/guards/jwt-auth.guard";
import { PermissionsGuard } from "../auth/guards/permissions.guard";
import { RequirePermissions } from "../auth/decorators/require-permissions.decorator";
import { JengaPaymentService } from "./jenga-payment.service";
import { PrismaService } from '../common/prisma/prisma.service';
import { CurrentUser } from '../auth/decorators/current-user.decorator';

@ApiTags("payments")
@Controller({ path: "payments", version: "1" })
export class PaymentsController {
  constructor(private readonly jenga: JengaPaymentService, private readonly prisma: PrismaService) {}

  @Post("mpesa/initiate")
  @UseGuards(JwtAuthGuard, PermissionsGuard)
  @RequirePermissions("payments.mpesa_initiate")
  @ApiBearerAuth("JWT-auth")
  @ApiOperation({ summary: "Retired host-account POS M-Pesa endpoint" })
  initiateMpesaPayment() {
    // The host Jenga credentials settle to Counterbase's account and must
    // never collect a shop's product revenue. Subscription renewal invokes
    // JengaPaymentService internally with its AXONSUB invoice reference.
    throw new GoneException('Update Counterbase and connect the shop payout account to accept M-Pesa sales');
  }

  @Get("mpesa/status/:transactionId")
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth("JWT-auth")
  @ApiOperation({ summary: "Reconcile an M-Pesa payment with Jenga" })
  getMpesaStatus(@Param("transactionId") id: string) {
    throw new GoneException('Use the merchant payment reference on the current Counterbase app');
  }

  // Public by design: Jenga cannot present an employee JWT. The body is
  // treated as a trigger only — no status change is ever taken from it.
  // The service matches the stored reference/phone/amount, then performs an
  // authenticated server-to-server status query before marking a payment
  // completed. TODO(security): verify the callback signature once Jenga
  // callback credentials are available (see JengaPaymentService.handleCallback).
  @Post("mpesa/callback")
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: "Equity/Jenga payment notification webhook" })
  mpesaCallback(@Body() body: Record<string, unknown>) {
    return this.jenga.handleCallback(body);
  }

  @Get("methods")
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth("JWT-auth")
  async getEnabledPaymentMethods(@CurrentUser('tenantId') tenantId: string) {
    const account = await this.prisma.merchantPaymentAccount.findUnique({
      where: { tenantId }, select: { status: true },
    });
    return [
      {
        id: "mpesa",
        name: "M-Pesa (merchant settlement)",
        enabled: account?.status === 'ACTIVE',
      },
      { id: "pesapal", name: "Pesapal", enabled: false },
      { id: "touristtap", name: "TouristTap (NFC)", enabled: false },
    ];
  }

  @Post(["pesapal/initiate", "touristtap/initiate"])
  @UseGuards(JwtAuthGuard)
  unavailable() {
    throw new ServiceUnavailableException(
      "This payment provider is not configured",
    );
  }
}
