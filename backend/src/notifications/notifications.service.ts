import { HttpException, HttpStatus, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { cert, initializeApp, type App } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import { LegacyUserRole, Prisma } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';

export interface PushNotificationPayload {
  title: string;
  body: string;
  /** Arbitrary key/value data delivered alongside the notification, e.g.
   * { type: 'stock_request_resolved', stockRequestId: '...' } — lets the
   * mobile app deep-link when the user taps the notification. */
  data?: Record<string, string>;
}

@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);
  private app: App | null = null;

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {
    this.app = this.initFirebaseApp();
  }

  private initFirebaseApp(): App | null {
    const projectId = this.config.get<string>('FIREBASE_PROJECT_ID');
    const clientEmail = this.config.get<string>('FIREBASE_CLIENT_EMAIL');
    const privateKey = this.config.get<string>('FIREBASE_PRIVATE_KEY');

    if (!projectId || !clientEmail || !privateKey) {
      this.logger.warn(
        'Firebase Admin credentials not configured — push notifications are disabled.',
      );
      return null;
    }

    try {
      return initializeApp({
        credential: cert({
          projectId,
          clientEmail,
          // .env stores the key with literal "\n" sequences (can't contain
          // real newlines in a single-line env var); Firebase needs them
          // converted back to actual newlines to parse the PEM key.
          privateKey: privateKey.replace(/\\n/g, '\n'),
        }),
      });
    } catch (error) {
      this.logger.error(`Failed to initialize Firebase Admin SDK: ${error}`);
      return null;
    }
  }

  get isConfigured(): boolean {
    return this.app !== null;
  }

  async registerToken(
    userId: string,
    token: string,
    deviceUuid?: string,
    platform = 'android',
  ): Promise<void> {
    // A token belongs to whichever user most recently registered it — if a
    // second user logs into the same device, the token should follow them,
    // not silently keep pushing to the previous account.
    await this.prisma.pushToken.upsert({
      where: { token },
      create: { userId, token, deviceUuid, platform },
      update: { userId, deviceUuid, platform },
    });
  }

  async unregisterToken(token: string): Promise<void> {
    await this.prisma.pushToken
      .delete({ where: { token } })
      .catch(() => undefined); // already gone — nothing to do
  }

  /**
   * Stores the notification in the user's inbox (always) and then sends a
   * push to every device the user has registered a token from. Fails soft:
   * neither persistence nor delivery is allowed to break the caller's
   * primary action (e.g. resolving a stock request) - errors are logged, and
   * tokens Firebase reports as invalid/unregistered are pruned.
   */
  async sendToUser(
    userId: string,
    payload: PushNotificationPayload,
    opts?: { tenantId?: string },
  ): Promise<void> {
    const notificationId = await this.persist(userId, payload, opts?.tenantId);

    if (!this.app) return;

    try {
      const tokens = await this.prisma.pushToken.findMany({
        where: { userId },
        select: { token: true },
      });
      if (tokens.length === 0) return;

      const data: Record<string, string> = {};
      for (const [key, value] of Object.entries(payload.data ?? {})) {
        if (value === undefined || value === null) continue;
        data[key] = typeof value === 'string' ? value : JSON.stringify(value);
      }
      data.type = data.type ?? 'general';
      if (notificationId) data.notificationId = notificationId;

      const response = await getMessaging(this.app).sendEachForMulticast({
        tokens: tokens.map((t) => t.token),
        notification: { title: payload.title, body: payload.body },
        data,
        android: { priority: 'high' },
      });

      const staleTokens: string[] = [];
      response.responses.forEach((result, index) => {
        if (!result.success) {
          const code = result.error?.code;
          if (
            code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token'
          ) {
            staleTokens.push(tokens[index].token);
          } else {
            this.logger.warn(
              `Push send failed for user ${userId}: ${result.error?.message}`,
            );
          }
        }
      });

      if (staleTokens.length > 0) {
        await this.prisma.pushToken.deleteMany({
          where: { token: { in: staleTokens } },
        });
      }
    } catch (error) {
      this.logger.error(`Failed to send push notification to user ${userId}: ${error}`);
    }
  }

  /** Best-effort inbox insert. Returns the new row id, or null on failure. */
  private async persist(
    userId: string,
    payload: PushNotificationPayload,
    tenantId?: string,
  ): Promise<string | null> {
    try {
      const { type, ...rest } = (payload.data ?? {}) as Record<string, string>;
      const row = await this.prisma.appNotification.create({
        data: {
          userId,
          tenantId: tenantId ?? null,
          type: type || 'general',
          title: payload.title,
          body: payload.body,
          data: Object.keys(rest).length > 0 ? (rest as Prisma.InputJsonValue) : undefined,
        },
        select: { id: true },
      });
      return row.id;
    } catch (error) {
      this.logger.error(`Failed to persist notification for user ${userId}: ${error}`);
      return null;
    }
  }

  /** Notifies every active user of a tenant holding one of the given roles. */
  async sendToTenantRoles(
    tenantId: string,
    roles: LegacyUserRole[],
    payload: PushNotificationPayload,
  ): Promise<void> {
    try {
      const users = await this.prisma.user.findMany({
        where: { tenantId, isActive: true, role: { in: roles } },
        select: { id: true },
      });
      await Promise.all(
        users.map((u) => this.sendToUser(u.id, payload, { tenantId })),
      );
    } catch (error) {
      this.logger.error(`Failed to notify roles ${roles.join(',')} of tenant ${tenantId}: ${error}`);
    }
  }

  async list(userId: string, limit = 50, before?: string) {
    const take = Math.min(Math.max(Math.trunc(Number(limit)) || 50, 1), 100);
    let beforeDate: Date | undefined;
    if (before) {
      const d = new Date(before);
      if (!Number.isNaN(d.getTime())) beforeDate = d;
    }
    const [rows, unreadCount] = await Promise.all([
      this.prisma.appNotification.findMany({
        where: { userId, ...(beforeDate ? { createdAt: { lt: beforeDate } } : {}) },
        orderBy: { createdAt: 'desc' },
        take,
        select: {
          id: true,
          type: true,
          title: true,
          body: true,
          data: true,
          readAt: true,
          createdAt: true,
        },
      }),
      this.prisma.appNotification.count({ where: { userId, readAt: null } }),
    ]);
    return { items: rows, unreadCount };
  }

  async markAllRead(userId: string): Promise<void> {
    await this.prisma.appNotification.updateMany({
      where: { userId, readAt: null },
      data: { readAt: new Date() },
    });
  }

  async markRead(userId: string, id: string): Promise<void> {
    const existing = await this.prisma.appNotification.findFirst({
      where: { id, userId },
      select: { id: true, readAt: true },
    });
    // Plain HttpException (not NotFoundException): the global
    // TransformInterceptor rewrites NotFoundException to 401 for
    // authenticated requests, which would hide this real 404.
    if (!existing) throw new HttpException('Notification not found', HttpStatus.NOT_FOUND);
    if (!existing.readAt) {
      await this.prisma.appNotification.update({
        where: { id },
        data: { readAt: new Date() },
      });
    }
  }
}
