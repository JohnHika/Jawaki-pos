import {
  Body,
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
import { InitiateMpesaDto } from "./dto/initiate-mpesa.dto";
import { JengaPaymentService } from "./jenga-payment.service";

@ApiTags("payments")
@Controller({ path: "payments", version: "1" })
export class PaymentsController {
  constructor(private readonly jenga: JengaPaymentService) {}

  @Post("mpesa/initiate")
  @UseGuards(JwtAuthGuard, PermissionsGuard)
  @RequirePermissions("payments.mpesa_initiate")
  @ApiBearerAuth("JWT-auth")
  @ApiOperation({ summary: "Send an Equity/Jenga M-Pesa STK payment prompt" })
  initiateMpesaPayment(@Body() body: InitiateMpesaDto) {
    return this.jenga.initiate(body);
  }

  @Get("mpesa/status/:transactionId")
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth("JWT-auth")
  @ApiOperation({ summary: "Reconcile an M-Pesa payment with Jenga" })
  getMpesaStatus(@Param("transactionId") id: string) {
    return this.jenga.status(id);
  }

  // Public by design: Jenga cannot present an employee JWT. The service
  // matches the stored reference/phone/amount then performs an authenticated
  // server-to-server status query before marking a payment completed.
  @Post("mpesa/callback")
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: "Equity/Jenga payment notification webhook" })
  mpesaCallback(@Body() body: Record<string, unknown>) {
    return this.jenga.handleCallback(body);
  }

  @Get("methods")
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth("JWT-auth")
  getEnabledPaymentMethods() {
    return [
      {
        id: "mpesa",
        name: "M-Pesa (Equity/Jenga)",
        enabled: this.jenga.isConfigured(),
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
