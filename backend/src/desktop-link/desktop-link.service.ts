import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { createHash, randomBytes, randomInt } from 'crypto';
import * as bcrypt from 'bcryptjs';
import { PrismaService } from '../common/prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { AuthService } from '../auth/auth.service';
import { AuthResponseDto } from '../auth/dto/auth.dto';

/**
 * Signing in a computer by approving on a phone that is already signed in.
 *
 * Flow (see RFC 10027, cross-device session transfer):
 * 1. The computer makes a random verifier, keeps it, and sends only its
 *    SHA-256 (the claim challenge) to `start`. It shows the QR and the
 *    6-digit code it gets back. Neither can finish the sign-in.
 * 2. The phone scans the QR or types the code. `preview` tells it which
 *    computer is asking, from where, and whether a PIN is required.
 * 3. The phone approves (with the person's PIN when the two devices are not
 *    on the same internet connection).
 * 4. The computer polls `status`, then `claim`s with its verifier and gets
 *    the same session a password sign-in would give that person.
 */

/** How long a request waits for the phone. */
export const CHALLENGE_TTL_MS = 2 * 60 * 1000;
/**
 * Time the computer has to collect an approval. Counted from the approval,
 * so approving in the last seconds of a code still signs the computer in.
 */
export const CLAIM_WINDOW_MS = 60 * 1000;
/** Wrong verifiers or PINs before a request is burned. */
const MAX_ATTEMPTS = 5;

const TERMINAL_STATUSES = new Set(['denied', 'claimed', 'expired']);

const ALL_STATUSES = [
  'pending',
  'approved',
  'denied',
  'claimed',
  'expired',
] as const;

type LinkStatus = (typeof ALL_STATUSES)[number];

/** Where a request came from, read from the proxy headers. */
export interface RequestOrigin {
  ip?: string;
  city?: string;
  country?: string;
}

export interface DesktopLinkStartResponse {
  linkId: string;
  code: string;
  /** Text for the QR image on the computer. Holds no secret. */
  qr: string;
  expiresAt: string;
  /** Seconds the code lasts, so the computer's own clock need not be right. */
  expiresIn: number;
}

export interface DesktopLinkStatusResponse {
  status: LinkStatus;
  /** First name of the person who approved, once approved. */
  approvedBy?: string;
  expiresAt: string;
}

export interface DesktopLinkPreviewResponse {
  linkId: string;
  desktopName: string;
  platform: string | null;
  /** City and country the computer's request came from, if known. */
  place: string | null;
  /** The phone and the computer reach us from the same address. */
  sameNetwork: boolean;
  /** Approving needs the person's PIN. */
  pinRequired: boolean;
  expiresAt: string;
}

@Injectable()
export class DesktopLinkService {
  private readonly logger = new Logger(DesktopLinkService.name);

  constructor(
    private prisma: PrismaService,
    private authService: AuthService,
    private notifications: NotificationsService,
  ) {}

  /** Computer: open a request and get the QR and code to show. */
  async start(
    input: { desktopName?: string; platform?: string; claimChallenge?: string },
    origin: RequestOrigin,
  ): Promise<DesktopLinkStartResponse> {
    const challenge = (input.claimChallenge ?? '').trim().toLowerCase();
    if (!/^[a-f0-9]{64}$/.test(challenge)) {
      throw new BadRequestException('Update Counterbase on this computer and try again');
    }
    const id = randomBytes(16).toString('hex');
    const expiresAt = new Date(Date.now() + CHALLENGE_TTL_MS);

    // Codes are unique among live requests; retry on the rare clash.
    let code = '';
    for (let tries = 0; tries < 5; tries++) {
      code = randomInt(0, 1_000_000).toString().padStart(6, '0');
      const clash = await this.prisma.desktopLinkChallenge.findFirst({
        where: { code, status: 'pending', expiresAt: { gt: new Date() } },
        select: { id: true },
      });
      if (!clash) break;
    }

    await this.prisma.desktopLinkChallenge.create({
      data: {
        id,
        code,
        claimSecretHash: challenge,
        mode: 'approval',
        desktopName: cleanLabel(input.desktopName) ?? 'A computer',
        platform: cleanLabel(input.platform, 20),
        ip: origin.ip?.slice(0, 64) ?? null,
        place: placeLabel(origin),
        expiresAt,
      },
    });

    const qr = JSON.stringify({ v: 2, app: 'counterbase', id, code });
    return {
      linkId: id,
      code,
      qr,
      expiresAt: expiresAt.toISOString(),
      expiresIn: CHALLENGE_TTL_MS / 1000,
    };
  }

  /** Computer: poll while the QR is on screen. */
  async status(linkId: string): Promise<DesktopLinkStatusResponse> {
    const row = await this.prisma.desktopLinkChallenge.findUnique({
      where: { id: linkId ?? '' },
      select: {
        status: true,
        expiresAt: true,
        user: { select: { firstName: true } },
      },
    });
    if (!row) throw new NotFoundException('Sign-in request not found');
    // An approval the computer did not collect in time is expired too, so
    // the computer shows a new code instead of a claim that must fail.
    const expired =
      (row.status === 'pending' || row.status === 'approved') &&
      row.expiresAt.getTime() <= Date.now();
    const status = expired ? 'expired' : castStatus(row.status);
    return {
      status,
      approvedBy:
        status === 'approved' || status === 'claimed'
          ? row.user?.firstName ?? undefined
          : undefined,
      expiresAt: row.expiresAt.toISOString(),
    };
  }

  /** Phone: what is asking, before the person decides. */
  async preview(
    userId: string,
    input: { payload?: string; code?: string },
    origin: RequestOrigin,
  ): Promise<DesktopLinkPreviewResponse> {
    const row = await this.findPending(userId, input);
    const sameNetwork = Boolean(origin.ip && row.ip && origin.ip === row.ip);
    const pinRequired = !sameNetwork && (await this.hasPin(userId));
    return {
      linkId: row.id,
      desktopName: row.desktopName ?? 'A computer',
      platform: row.platform,
      place: row.place,
      sameNetwork,
      pinRequired,
      expiresAt: row.expiresAt.toISOString(),
    };
  }

  /** Phone: approve or refuse. The computer gets this person's own account. */
  async decide(
    approver: { userId: string; branchId?: string },
    input: { linkId: string; decision?: 'approve' | 'deny'; pin?: string },
    origin: RequestOrigin,
  ): Promise<DesktopLinkStatusResponse> {
    const decision = input.decision ?? 'approve';
    const row = await this.prisma.desktopLinkChallenge.findUnique({
      where: { id: input.linkId ?? '' },
    });
    if (!row) throw new NotFoundException('Sign-in request not found');
    if (TERMINAL_STATUSES.has(row.status) || row.status !== 'pending') {
      throw new BadRequestException('This sign-in was already answered');
    }
    if (row.expiresAt.getTime() <= Date.now()) {
      await this.expire(row.id);
      throw new BadRequestException(
        'This request has expired. Start again on the computer.',
      );
    }

    if (decision === 'approve') {
      const sameNetwork = Boolean(origin.ip && row.ip && origin.ip === row.ip);
      if (!sameNetwork && (await this.hasPin(approver.userId))) {
        await this.checkPin(approver.userId, input.pin, row.id);
      }
    }

    // Only a still-pending request can be answered, once.
    const answered = await this.prisma.desktopLinkChallenge.updateMany({
      where: { id: row.id, status: 'pending' },
      data: {
        status: decision === 'deny' ? 'denied' : 'approved',
        ...(decision === 'deny'
          ? {}
          : { expiresAt: new Date(Date.now() + CLAIM_WINDOW_MS) }),
        userId: approver.userId,
        branchId: approver.branchId ?? null,
        approverIp: origin.ip?.slice(0, 64) ?? null,
        approvedAt: new Date(),
      },
    });
    if (answered.count === 0) {
      throw new BadRequestException('This sign-in was already answered');
    }
    return this.status(row.id);
  }

  /**
   * Computer: trade the approved request for a session by proving it holds
   * the verifier whose hash it sent to `start`.
   */
  async claim(input: {
    linkId: string;
    verifier: string;
    deviceId?: string;
  }): Promise<AuthResponseDto> {
    const verifier = (input.verifier ?? '').trim();
    if (verifier.length < 32) {
      throw new UnauthorizedException('Missing sign-in proof');
    }
    const row = await this.prisma.desktopLinkChallenge.findUnique({
      where: { id: input.linkId ?? '' },
    });
    if (!row) throw new NotFoundException('Sign-in request not found');
    if (row.attempts >= MAX_ATTEMPTS) {
      throw new ForbiddenException('Too many attempts. Start a new sign-in.');
    }
    if (!timingSafeEqualText(row.claimSecretHash, sha256(verifier))) {
      await this.prisma.desktopLinkChallenge.update({
        where: { id: row.id },
        data: { attempts: { increment: 1 } },
      });
      throw new UnauthorizedException('This computer did not start that sign-in');
    }
    if (row.status === 'claimed') {
      throw new BadRequestException('This sign-in was already used');
    }
    if (row.status !== 'approved' || !row.userId) {
      throw new BadRequestException(
        row.status === 'denied'
          ? 'The sign-in was refused on the phone'
          : 'The phone has not approved this sign-in yet',
      );
    }
    if (row.expiresAt.getTime() <= Date.now()) {
      throw new BadRequestException('The sign-in expired. Start again.');
    }

    // One request, one session.
    const claimed = await this.prisma.desktopLinkChallenge.updateMany({
      where: { id: row.id, status: 'approved' },
      data: { status: 'claimed', claimedAt: new Date() },
    });
    if (claimed.count === 0) {
      throw new BadRequestException('This sign-in was already used');
    }

    const session = await this.authService.issueLinkedSession(row.userId, {
      branchId: row.branchId ?? undefined,
      deviceId: input.deviceId?.slice(0, 120) || undefined,
    });

    this.notifications
      .sendToUser(row.userId, {
        title: 'Computer signed in',
        body: `Counterbase is now signed in on ${row.desktopName ?? 'a computer'} with your account.`,
        data: { type: 'desktop_link_claimed', linkId: row.id },
      })
      .catch((e) => this.logger.warn(`desktop-link notice failed: ${e}`));

    return session;
  }

  // ------------------------------------------------------------------

  private async findPending(
    userId: string,
    input: { payload?: string; code?: string },
  ) {
    let where: { id: string } | { code: string };
    if (input.payload) {
      where = { id: parseQrPayload(input.payload) };
    } else {
      const code = (input.code ?? '').replace(/\s+/g, '');
      if (!/^\d{6}$/.test(code)) {
        throw new BadRequestException('Enter the 6-digit code from the computer');
      }
      where = { code };
    }
    const row = await this.prisma.desktopLinkChallenge.findFirst({
      where: { ...where, status: 'pending', expiresAt: { gt: new Date() } },
    });
    if (!row) {
      // Not NotFound: on this signed-in route TransformInterceptor turns a
      // 404 into 401, and the phone takes that for an expired session.
      throw new BadRequestException(await this.whyNotWaiting(userId, where));
    }
    return row;
  }

  /** Why a scanned or typed request can no longer be answered. */
  private async whyNotWaiting(
    userId: string,
    where: { id: string } | { code: string },
  ): Promise<string> {
    const last = await this.prisma.desktopLinkChallenge.findFirst({
      where,
      orderBy: { createdAt: 'desc' },
      select: { status: true, userId: true },
    });
    // Only the person who answered it hears how it was answered.
    if (last?.userId === userId) {
      if (last.status === 'approved') {
        return 'You approved this computer. It opens by itself in a few seconds.';
      }
      if (last.status === 'claimed') {
        return 'This computer is already signed in with your account.';
      }
      if (last.status === 'denied') {
        return 'You refused this sign-in. Choose Show a new code on the computer to try again.';
      }
    }
    if (last && 'id' in where) {
      return 'This code has expired. Scan the new code on the computer.';
    }
    return 'No computer is waiting with that code. Check the computer screen or start again there.';
  }

  private async hasPin(userId: string): Promise<boolean> {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { pin: true },
    });
    return Boolean(user?.pin);
  }

  private async checkPin(userId: string, pin: string | undefined, linkId: string) {
    if (!pin || !/^\d{4,8}$/.test(pin)) {
      throw new BadRequestException(
        'This computer is on a different connection. Enter your PIN to approve.',
      );
    }
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { pin: true, isActive: true },
    });
    if (!user || !user.isActive) {
      throw new UnauthorizedException('Account is disabled');
    }
    if (user.pin && (await bcrypt.compare(pin, user.pin))) return;

    const row = await this.prisma.desktopLinkChallenge.update({
      where: { id: linkId },
      data: { attempts: { increment: 1 } },
      select: { attempts: true },
    });
    if (row.attempts >= MAX_ATTEMPTS) {
      await this.expire(linkId);
      throw new UnauthorizedException(
        'Too many wrong PINs. Start a new sign-in on the computer.',
      );
    }
    throw new UnauthorizedException('Wrong PIN');
  }

  private async expire(linkId: string) {
    await this.prisma.desktopLinkChallenge
      .updateMany({
        where: { id: linkId, status: 'pending' },
        data: { status: 'expired' },
      })
      .catch(() => undefined);
  }
}

/** Reads the caller's address and Vercel's location headers. */
export function originFromRequest(req: any): RequestOrigin {
  const header = (name: string): string | undefined => {
    const value = req?.headers?.[name];
    return typeof value === 'string' && value.trim() ? value.trim() : undefined;
  };
  const forwarded = header('x-forwarded-for')?.split(',')[0]?.trim();
  const decode = (value?: string) => {
    if (!value) return undefined;
    try {
      return decodeURIComponent(value);
    } catch {
      return value;
    }
  };
  return {
    ip: forwarded || req?.ip || req?.socket?.remoteAddress || undefined,
    city: decode(header('x-vercel-ip-city')),
    country: header('x-vercel-ip-country'),
  };
}

function placeLabel(origin: RequestOrigin): string | null {
  const parts = [origin.city, origin.country].filter(Boolean);
  return parts.length ? parts.join(', ').slice(0, 80) : null;
}

function cleanLabel(value: string | undefined, max = 60): string | null {
  const text = (value ?? '').replace(/[\u0000-\u001f]/g, '').trim();
  return text ? text.slice(0, max) : null;
}

function sha256(text: string): string {
  return createHash('sha256').update(text).digest('hex');
}

/** Comparison that does not stop at the first different character. */
function timingSafeEqualText(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function parseQrPayload(raw: string): string {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new BadRequestException('That is not a Counterbase sign-in code');
  }
  const obj = parsed as { v?: number; app?: string; id?: string };
  if (obj?.v !== 2 || obj.app !== 'counterbase' || typeof obj.id !== 'string') {
    throw new BadRequestException('That is not a Counterbase sign-in code');
  }
  return obj.id;
}

function castStatus(status: string): LinkStatus {
  return ALL_STATUSES.find((s) => s === status) ?? 'expired';
}
