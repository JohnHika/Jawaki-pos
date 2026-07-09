import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { cert, initializeApp, type App } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
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
   * Sends a push to every device the given user has registered a token
   * from. Fails soft: notification delivery is never allowed to break the
   * caller's primary action (e.g. resolving a stock request) — errors are
   * logged, and tokens Firebase reports as invalid/unregistered are pruned.
   */
  async sendToUser(userId: string, payload: PushNotificationPayload): Promise<void> {
    if (!this.app) return;

    const tokens = await this.prisma.pushToken.findMany({
      where: { userId },
      select: { token: true },
    });
    if (tokens.length === 0) return;

    try {
      const response = await getMessaging(this.app).sendEachForMulticast({
        tokens: tokens.map((t) => t.token),
        notification: { title: payload.title, body: payload.body },
        data: payload.data,
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
}
