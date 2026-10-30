import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Post,
  Query,
  UseGuards,
  Request,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { DesktopLinkService } from './desktop-link.service';
import {
  CodeApproveDto,
  ScanApproveDto,
} from './dto/desktop-link.dto';

@ApiTags('desktop-link')
@Controller({ path: 'auth/desktop-link', version: '1' })
export class DesktopLinkController {
  constructor(private readonly desktopLinkService: DesktopLinkService) {}

  /** Desktop: create a pending sign-in request to display as QR + code. */
  @Post('start')
  @HttpCode(HttpStatus.OK)
  @UseGuards(ThrottlerGuard)
  @Throttle({ default: { ttl: 60_000, limit: 10 } })
  @ApiOperation({ summary: 'Start a desktop sign-in request (QR + code)' })
  async start(
    @Body() body: { desktopName?: string },
  ): Promise<ReturnType<DesktopLinkService['start']>> {
    return this.desktopLinkService.start(body?.desktopName);
  }

  /** Desktop: poll the request's status while the QR screen is up. */
  @Get('status')
  @UseGuards(ThrottlerGuard)
  @Throttle({ default: { ttl: 60_000, limit: 240 } })
  @ApiOperation({ summary: 'Poll a desktop sign-in request status' })
  async status(
    @Query('linkId') linkId: string,
  ): Promise<ReturnType<DesktopLinkService['status']>> {
    return this.desktopLinkService.status(linkId);
  }

  /** Desktop: redeem an approved request for tokens. */
  @Post('claim')
  @HttpCode(HttpStatus.OK)
  @UseGuards(ThrottlerGuard)
  @Throttle({ default: { ttl: 60_000, limit: 20 } })
  @ApiOperation({ summary: 'Claim desktop sign-in tokens with the claim secret' })
  async claim(
    @Body() body: { linkId: string; secret: string },
  ): Promise<ReturnType<DesktopLinkService['claim']>> {
    return this.desktopLinkService.claim(body?.linkId, body?.secret);
  }

  /** Mobile: approve a request by scanning the desktop's QR. */
  @Post('scan-approve')
  @HttpCode(HttpStatus.OK)
  @UseGuards(JwtAuthGuard, ThrottlerGuard)
  @Throttle({ default: { ttl: 60_000, limit: 20 } })
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Approve a desktop sign-in by scanning its QR' })
  async scanApprove(@Request() req: any, @Body() dto: ScanApproveDto) {
    return this.desktopLinkService.scanApprove(req.user.id, dto);
  }

  /** Mobile: approve by typing the 6-digit code from the push/desktop screen. */
  @Post('code-approve')
  @HttpCode(HttpStatus.OK)
  @UseGuards(JwtAuthGuard, ThrottlerGuard)
  @Throttle({ default: { ttl: 60_000, limit: 20 } })
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Approve a desktop sign-in by short code' })
  async codeApprove(@Request() req: any, @Body() dto: CodeApproveDto) {
    return this.desktopLinkService.codeApprove(req.user.id, dto);
  }
}
