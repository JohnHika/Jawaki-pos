import {
  Body,
  Controller,
  Get,
  Headers,
  HttpCode,
  Param,
  Post,
  Query,
  Req,
  Res,
  UseGuards,
  VERSION_NEUTRAL,
} from '@nestjs/common';
import { ApiExcludeController } from '@nestjs/swagger';
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
import { Request, Response } from 'express';
import { randomBytes } from 'crypto';
import { StatementsService } from './statements.service';
import { PublicClaimDto } from './dto/statements.dto';
import { parseLang } from './statements.i18n';
import { Lang } from './statements.types';
import { esc, renderExpiredPage, renderStatementPage } from './statements.render';

const APP_DOWNLOAD_PATH = '/api/v1/app-updates/android/download';

function pickLang(query: unknown, acceptLanguage?: string): Lang {
  if (query === 'sw' || query === 'en') return parseLang(query);
  return /^\s*sw/i.test(acceptLanguage ?? '') ? 'sw' : 'en';
}

/**
 * The page a customer or shop opens from a WhatsApp link. No sign-in: the long
 * random token in the address is the only credential, it expires, and the
 * owner can revoke it. Every failure looks the same so a token cannot be probed.
 */
@ApiExcludeController()
@Controller({ path: 's', version: VERSION_NEUTRAL })
@UseGuards(ThrottlerGuard)
export class StatementsPublicController {
  constructor(private readonly statements: StatementsService) {}

  private privateHeaders(res: Response, nonce?: string) {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Robots-Tag', 'noindex, nofollow');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader(
      'Content-Security-Policy',
      [
        "default-src 'none'",
        "style-src 'unsafe-inline'",
        nonce ? `script-src 'nonce-${nonce}'` : "script-src 'none'",
        "connect-src 'self'",
        'img-src https: data:',
        "base-uri 'none'",
        "form-action 'none'",
        "frame-ancestors 'none'",
      ].join('; '),
    );
  }

  @Get(':token')
  // Generous on purpose: behind a proxy every visitor can look like one address,
  // and a shop's customers must never be locked out of seeing what they owe.
  // What stops abuse is the unguessable token and the cap on replies per link.
  @Throttle({ default: { ttl: 60_000, limit: 600 } })
  async page(
    @Param('token') token: string,
    @Query('lang') langQuery: string | undefined,
    @Headers('accept-language') acceptLanguage: string | undefined,
    @Headers('user-agent') userAgent: string | undefined,
    @Res() res: Response,
  ) {
    const lang = pickLang(langQuery, acceptLanguage);
    const view = await this.statements.openLink(token, userAgent);
    res.type('html');
    if (!view) {
      this.privateHeaders(res);
      return res.status(410).send(renderExpiredPage(lang));
    }
    const nonce = randomBytes(16).toString('base64');
    this.privateHeaders(res, nonce);
    return res.status(200).send(
      renderStatementPage(view, { lang, token, nonce, appDownloadPath: APP_DOWNLOAD_PATH }),
    );
  }

  @Get(':token/pdf')
  @Throttle({ default: { ttl: 60_000, limit: 300 } })
  async pdf(
    @Param('token') token: string,
    @Query('lang') langQuery: string | undefined,
    @Headers('accept-language') acceptLanguage: string | undefined,
    @Res() res: Response,
  ) {
    const lang = pickLang(langQuery, acceptLanguage);
    const file = await this.statements.renderPdfForToken(token, lang);
    if (!file) {
      this.privateHeaders(res);
      return res.status(410).type('html').send(renderExpiredPage(lang));
    }
    this.privateHeaders(res);
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename="${esc(file.filename)}"`);
    return res.status(200).send(file.buffer);
  }

  @Post(':token/claims')
  @HttpCode(200)
  @Throttle({ default: { ttl: 60_000, limit: 60 } })
  submit(@Param('token') token: string, @Body() dto: PublicClaimDto, @Req() _req: Request) {
    return this.statements.submitClaim(token, dto);
  }
}
