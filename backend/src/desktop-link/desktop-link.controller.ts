import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Post,
  Query,
  Request,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { DesktopLinkService, originFromRequest } from './desktop-link.service';
import {
  ClaimDesktopLinkDto,
  DecideDesktopLinkDto,
  PreviewDesktopLinkDto,
  StartDesktopLinkDto,
} from './dto/desktop-link.dto';

/** Signing in a computer by approving on a phone that is signed in. */
@ApiTags('desktop-link')
@Controller({ path: 'auth/desktop-link', version: '1' })
export class DesktopLinkController {
  constructor(private readonly desktopLinkService: DesktopLinkService) {}

  /** Computer: open a request to show as a QR and code. */
  @Post('start')
  @HttpCode(HttpStatus.OK)
  @UseGuards(ThrottlerGuard)
  @Throttle({ default: { ttl: 60_000, limit: 10 } })
  @ApiOperation({ summary: 'Start a phone-approved computer sign-in' })
  start(@Request() req: any, @Body() dto: StartDesktopLinkDto) {
    return this.desktopLinkService.start(dto, originFromRequest(req));
  }

  /** Computer: poll while the QR is on screen. */
  @Get('status')
  @UseGuards(ThrottlerGuard)
  @Throttle({ default: { ttl: 60_000, limit: 120 } })
  @ApiOperation({ summary: 'Poll a computer sign-in request' })
  status(@Query('linkId') linkId: string) {
    return this.desktopLinkService.status(linkId);
  }

  /** Computer: trade an approved request for a session. */
  @Post('claim')
  @HttpCode(HttpStatus.OK)
  @UseGuards(ThrottlerGuard)
  @Throttle({ default: { ttl: 60_000, limit: 20 } })
  @ApiOperation({ summary: 'Finish a computer sign-in with its verifier' })
  claim(@Body() dto: ClaimDesktopLinkDto) {
    return this.desktopLinkService.claim(dto);
  }

  /** Phone: which computer is asking, before deciding. */
  @Post('preview')
  @HttpCode(HttpStatus.OK)
  @UseGuards(JwtAuthGuard, ThrottlerGuard)
  @Throttle({ default: { ttl: 60_000, limit: 30 } })
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Look up a computer sign-in by QR or code' })
  preview(@Request() req: any, @Body() dto: PreviewDesktopLinkDto) {
    return this.desktopLinkService.preview(
      req.user.sub,
      dto,
      originFromRequest(req),
    );
  }

  /** Phone: approve or refuse. */
  @Post('decide')
  @HttpCode(HttpStatus.OK)
  @UseGuards(JwtAuthGuard, ThrottlerGuard)
  @Throttle({ default: { ttl: 60_000, limit: 20 } })
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Approve or refuse a computer sign-in' })
  decide(@Request() req: any, @Body() dto: DecideDesktopLinkDto) {
    return this.desktopLinkService.decide(
      { userId: req.user.sub, branchId: req.user.branchId },
      dto,
      originFromRequest(req),
    );
  }
}
