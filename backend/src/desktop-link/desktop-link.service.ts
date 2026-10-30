import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { createHash, randomBytes, randomInt } from 'crypto';
import * as bcrypt from 'bcryptjs';
import { PrismaService } from '../common/prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PermissionsService } from '../permissions/permissions.service';

/** How long a pending desktop sign-in request stays redeemable. */
const CHALLENGE_TTL_MS = 3 * 60 * 1000;
/** Max wrong-secret claim tries before the challenge is burned. */
const MAX_CLAIM_ATTEMPTS = 5;

const TERMINAL_STATUSES = new Set(['denied', 'claimed', 'expired']);

export interface DesktopLinkStartResponse {
  linkId: string;
  code: string;
  /** String to encode into the QR image shown on the desktop screen. */
  qr: string;
  expiresAt: string;
}

export interface DesktopLinkStatusResponse {
  status: 'pending' | 'approved' | 'denied' | 'claimed' | 'expired';
  account?: {
    firstName: string;
    lastName: string;
    email: string;
    role: string;
  };
  desktopName?: string | null;
  expiresAt: string;
}

export interface DesktopLinkClaimResponse {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
  user: {
    id: string;
    email: string;
    firstName: string;
    lastName: string;
    role: string;
    tenantId: string;
    tenantSlug?: string | null;
    branchId?: string;
    branchName?: string;
    hasPinSet: boolean;
    permissions: string[];
  };
}

export interface ScanApproveDto {
  /** Full QR payload as scanned. */
  payload: string;
  /** approve (default) or deny the request. */
  decision?: 'approve' | 'deny';
  mode?: 'approval' | 'pin';
  deviceName?: string;
  pin?: string;
}

export interface CodeApproveDto {
  code: string;
  /** approve (default) or deny the request. */
  decision?: 'approve' | 'deny';
  mode?: 'approval' | 'pin';
  deviceName?: string;
  pin?: string;
}

@Injectable()
export class DesktopLinkService {
  private readonly logger = new Logger(DesktopLinkService.name);

  constructor(
    private prisma: PrismaService,
    private jwtService: JwtService,
    private config: { get(key: string, def?: string): string | undefined },
    private notifications: NotificationsService,
    private permissionsService: PermissionsService,
  ) {}

  /**
   * Desktop calls this: creates the pending challenge whose QR + short code
   * the desktop screen displays.
   */
  async start(desktopName?: string): Promise<DesktopLinkStartResponse> {
    const code = randomInt(0, 1_000_000).toString().padStart(6, '0');
    const claimSecret = randomBytes(32).toString('base64url');
    const id = randomBytes(16).toString('hex');
    const expiresAt = new Date(Date.now() + CHALLENGE_TTL_MS);

    await this.prisma.desktopLinkChallenge.create({
      data: {
        id,
        code,
        claimSecretHash: sha256(claimSecret),
        mode: 'approval',
        desktopName: desktopName?.slice(0, 80) || null,
        expiresAt,
      },
    });

    const qr = JSON.stringify({
      v: 1,
      id,
      code,
      s: claimSecret,
      api: 'desktop-link',
    });

    return { linkId: id, code, qr, expiresAt: expiresAt.toISOString() };
  }

  /** Mobile scans the desktop QR and approves with the full payload. */
  async scanApprove(
    userId: string,
    dto: ScanApproveDto,
  ): Promise<DesktopLinkStatusResponse> {
    const parsed = parseQrPayload(dto.payload);
    return this.approve(userId, parsed.id, parsed.code, dto);
  }

  /** Mobile taps the push notification and approves by short code. */
  async codeApprove(
    userId: string,
    dto: CodeApproveDto,
  ): Promise<DesktopLinkStatusResponse> {
    const code = (dto.code ?? '').trim();
    if (!/^\d{6}$/.test(code)) {
      throw new BadRequestException('Enter the 6-digit code from the desktop');
    }
    return this.approve(userId, null, code, dto);
  }

  /** Desktop polls while its QR screen is up. */
  async status(linkId: string): Promise<DesktopLinkStatusResponse> {
    const row = await this.prisma.desktopLinkChallenge.findUnique({
      where: { id: linkId },
      select: {
        status: true,
        desktopName: true,
        expiresAt: true,
        user: {
          select: { firstName: true, lastName: true, email: true, role: true },
        },
      },
    });
    if (!row) throw new NotFoundException('Sign-in request not found');
    const expired =
      row.status === 'pending' && row.expiresAt.getTime() <= Date.now();
    return {
      status: expired ? 'expired' : castStatus(row.status),
      account: row.user
        ? {
            firstName: row.user.firstName,
            lastName: row.user.lastName,
            email: row.user.email,
            role: row.user.role,
          }
        : undefined,
      desktopName: row.desktopName,
      expiresAt: row.expiresAt.toISOString(),
    };
  }

  /**
   * Desktop redeems the approval for tokens by presenting the claim secret
   * that only the original QR payload held.
   */
  async claim(
    linkId: string,
    claimSecret: string,
  ): Promise<DesktopLinkClaimResponse> {
    if (!claimSecret) throw new UnauthorizedException('Missing claim secret');
    const row = await this.prisma.desktopLinkChallenge.findUnique({
      where: { id: linkId },
      include: {
        user: {
          select: {
            id: true,
            email: true,
            firstName: true,
            lastName: true,
            role: true,
            tenantId: true,
            pin: true,
            isActive: true,
            tenant: { select: { slug: true } },
            branches: { select: { branchId: true, isPrimary: true } },
          },
        },
      },
    });
    if (!row) throw new NotFoundException('Sign-in request not found');
    if (row.attempts >= MAX_CLAIM_ATTEMPTS) {
      throw new ForbiddenException('Too many attempts — start a new sign-in');
    }
    if (!timingSafeEqualText(row.claimSecretHash, sha256(claimSecret))) {
      await this.prisma.desktopLinkChallenge.update({
        where: { id: row.id },
        data: { attempts: { increment: 1 } },
      });
      throw new UnauthorizedException('Invalid claim secret');
    }
    if (row.status === 'claimed') {
      throw new BadRequestException('This sign-in was already used');
    }
    if (row.status !== 'approved') {
      throw new BadRequestException(
        row.status === 'pending' && row.expiresAt.getTime() <= Date.now()
          ? 'Request expired — start a new sign-in'
          : `Sign-in was ${row.status}`,
      );
    }
    if (row.expiresAt.getTime() <= Date.now()) {
      throw new BadRequestException('Request expired — start a new sign-in');
    }

    const user = row.user;
    if (!user || !user.isActive) {
      throw new UnauthorizedException('Account is disabled');
    }

    const tokens = await this.issueTokens(user, row.mode, row.desktopName);
    try {
      tokens.user.permissions =
        await this.permissionsService.getEffectivePermissions(user.id);
    } catch (error) {
      this.logger.warn(
        `Failed to resolve permissions for desktop link claim (user ${user.id}): ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }

    // One challenge, one session: flip to claimed atomically so two claims
    // in flight cannot both mint a session.
    const claimResult = await this.prisma.desktopLinkChallenge.updateMany({
      where: { id: row.id, status: 'approved' },
      data: { status: 'claimed', claimedAt: new Date() },
    });
    if (claimResult.count === 0) {
      throw new BadRequestException('This sign-in was already used');
    }

    this.pushToUser(user.id, {
      title: 'New desktop sign-in',
      body: `Counterbase was signed in on ${row.desktopName || 'a computer'}.`,
      data: { type: 'desktop_link_claimed', linkId: row.id },
    });

    return tokens;
  }

  // ------------------------------------------------------------------

  private async approve(
    userId: string,
    linkId: string | null,
    code: string,
    dto: {
      decision?: 'approve' | 'deny';
      mode?: 'approval' | 'pin';
      deviceName?: string;
      pin?: string;
    },
  ): Promise<DesktopLinkStatusResponse> {
    const decision = dto.decision ?? 'approve';
    const mode = decision === 'deny' ? 'approval' : (dto.mode ?? 'approval');

    const row = await this.prisma.desktopLinkChallenge.findFirst({
      where: linkId
        ? { id: linkId }
        : { code, status: 'pending', expiresAt: { gt: new Date() } },
      include: {
        user: { select: { id: true, pin: true } },
      },
    });
    if (!row) {
      throw new NotFoundException(
        'No waiting sign-in request matches that code — check the desktop screen',
      );
    }
    if (TERMINAL_STATUSES.has(row.status)) {
      throw new BadRequestException(`This sign-in was already ${row.status}`);
    }
    if (row.expiresAt.getTime() <= Date.now()) {
      await this.expire(row.id);
      throw new BadRequestException('This sign-in request has expired');
    }

    if (decision === 'approve' && mode === 'pin') {
      const err = await this.verifyPin(userId, dto.pin, row.id);
      if (err) throw err;
    }

    const updated = await this.prisma.desktopLinkChallenge.update({
      where: { id: row.id },
      data: {
        status: decision === 'deny' ? 'denied' : 'approved',
        mode,
        userId,
        desktopName: dto.deviceName?.slice(0, 80) ?? row.desktopName,
        approvedAt: new Date(),
      },
      include: {
        user: {
          select: { firstName: true, lastName: true, email: true, role: true },
        },
      },
    });

    if (decision === 'deny') {
      this.pushToUser(userId, {
        title: 'Desktop sign-in denied',
        body: 'You blocked the desktop sign-in request.',
        data: { type: 'desktop_link_denied', linkId: row.id },
      });
    }

    return {
      status: castStatus(updated.status),
      account: updated.user
        ? {
            firstName: updated.user.firstName,
            lastName: updated.user.lastName,
            email: updated.user.email,
            role: updated.user.role,
          }
        : undefined,
      desktopName: updated.desktopName,
      expiresAt: updated.expiresAt.toISOString(),
    };
  }

  private async verifyPin(
    userId: string,
    pin: string | undefined,
    linkId: string,
  ): Promise<UnauthorizedException | null> {
    if (!pin || !/^\d{4,8}$/.test(pin)) {
      throw new BadRequestException('Enter your 4–8 digit PIN to approve');
    }
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { pin: true, isActive: true },
    });
    if (!user || !user.isActive) {
      throw new UnauthorizedException('Account is disabled');
    }
    if (!user.pin) {
      throw new BadRequestException(
        'No PIN is set for this account — use approval mode or set a PIN first',
      );
    }
    if (!(await bcrypt.compare(pin, user.pin))) {
      // Reuse the attempts counter as an abuse brake for wrong PINs.
      const row = await this.prisma.desktopLinkChallenge.update({
        where: { id: linkId },
        data: { attempts: { increment: 1 } },
        select: { attempts: true },
      });
      if (row.attempts >= MAX_CLAIM_ATTEMPTS) {
        await this.expire(linkId);
        throw new UnauthorizedException(
          'Too many wrong PIN attempts — start a new sign-in',
        );
      }
      throw new UnauthorizedException('Incorrect PIN');
    }
    return null;
  }

  /**
   * Mints the desktop's access/refresh tokens the same way password login
   * does (same JWT shape, same RefreshToken row) so downstream middleware,
   * guards and sync code can't tell the session apart.
   */
  private async issueTokens(
    user: {
      id: string;
      email: string;
      firstName: string;
      lastName: string;
      role: string;
      tenantId: string;
      tenant: { slug: string | null } | null;
      branches: { branchId: string; isPrimary: boolean }[];
    },
    mode: string,
    deviceName: string | null,
  ): Promise<DesktopLinkClaimResponse> {
    const branchId = user.branches.find((b) => b.isPrimary)?.branchId;

    const payload = {
      sub: user.id,
      email: user.email,
      role: user.role,
      tenantId: user.tenantId,
      branchId,
      deviceId: deviceName ?? undefined,
    };
    const accessToken = this.jwtService.sign(payload);
    const refreshToken = randomBytes(32).toString('base64url');
    const refreshHash = sha256(refreshToken);

    const expiresIn = parseExpiry(
      this.config.get('JWT_EXPIRES_IN') ?? '15m',
    );
    const refreshExpiresIn = parseExpiry(
      this.config.get('JWT_REFRESH_EXPIRES_IN') ?? '7d',
    );

    await this.prisma.refreshToken.create({
      data: {
        userId: user.id,
        tokenHash: refreshHash,
        deviceId: deviceName ?? undefined,
        expiresAt: new Date(Date.now() + refreshExpiresIn * 1000),
      },
    });

    return {
      accessToken,
      refreshToken,
      expiresIn,
      user: {
        id: user.id,
        email: user.email,
        firstName: user.firstName,
        lastName: user.lastName,
        role: user.role,
        tenantId: user.tenantId,
        tenantSlug: user.tenant?.slug ?? undefined,
        branchId: branchId ?? undefined,
        hasPinSet: false,
        permissions: [],
      },
    };
  }

  private async expire(linkId: string) {
    await this.prisma.desktopLinkChallenge
      .update({
        where: { id: linkId },
        data: { status: 'expired' },
      })
      .catch(() => undefined);
  }

  private pushToUser(
    userId: string,
    payload: { title: string; body: string; data?: Record<string, string> },
  ) {
    this.notifications
      .sendToUser(userId, payload)
      .catch((e) => this.logger.warn(`desktop-link push failed: ${e}`));
  }
}

function sha256(text: string): string {
  return createHash('sha256').update(text).digest('hex');
}

/** Length-independent, early-exit-free comparison for hex digests. */
function timingSafeEqualText(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function parseQrPayload(raw: string): { id: string; code: string } {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new BadRequestException('Not a Counterbase desktop QR code');
  }
  const obj = parsed as { v?: number; id?: string; code?: string };
  if (obj?.v !== 1 || typeof obj.id !== 'string' || typeof obj.code !== 'string') {
    throw new BadRequestException('Not a Counterbase desktop QR code');
  }
  return { id: obj.id, code: obj.code };
}

const ALL_STATUSES = [
  'pending',
  'approved',
  'denied',
  'claimed',
  'expired',
] as const;

type LinkStatus = (typeof ALL_STATUSES)[number];

function castStatus(status: string): LinkStatus {
  return ALL_STATUSES.find((s) => s === status) ?? 'expired';
}

function parseExpiry(value: string): number {
  const match = /^(\d+)([smhd])$/.exec(value.trim());
  if (!match) return 15 * 60;
  const amount = Number(match[1]);
  const unitSeconds: Record<string, number> = {
    s: 1,
    m: 60,
    h: 3600,
    d: 86400,
  };
  return amount * unitSeconds[match[2]];
}
