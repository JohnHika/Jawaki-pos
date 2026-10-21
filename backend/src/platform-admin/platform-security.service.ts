import { Injectable } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';

const FAILED_LOGIN_ACTIONS = [
  'AUTH_LOGIN_FAILED',
  'AUTH_LOGIN_FAILED_UNKNOWN',
  'AUTH_2FA_FAILED',
  'AUTH_LOGIN_DISABLED_ACCOUNT',
];

@Injectable()
export class PlatformSecurityService {
  constructor(private readonly prisma: PrismaService) {}

  async overview() {
    const now = new Date();
    const day = new Date(now.getTime() - 86_400_000);
    const week = new Date(now.getTime() - 7 * 86_400_000);

    const [
      failedLogins24h,
      successfulLogins24h,
      critical7d,
      warn7d,
      activeSessions,
      lockedAccounts,
      staff,
      recentEvents,
      topFailedIps,
    ] = await Promise.all([
      this.prisma.platformAuditLog.count({
        where: { action: { in: FAILED_LOGIN_ACTIONS }, createdAt: { gte: day } },
      }),
      this.prisma.platformAuditLog.count({
        where: { action: 'AUTH_LOGIN_SUCCESS', createdAt: { gte: day } },
      }),
      this.prisma.platformAuditLog.count({
        where: { severity: 'CRITICAL', createdAt: { gte: week } },
      }),
      this.prisma.platformAuditLog.count({
        where: { severity: 'WARN', createdAt: { gte: week } },
      }),
      this.prisma.platformAdminSession.count({
        where: { revokedAt: null, expiresAt: { gt: now } },
      }),
      this.prisma.platformAdmin.findMany({
        where: { lockedUntil: { gt: now } },
        select: { id: true, email: true, name: true, role: true, lockedUntil: true },
      }),
      this.prisma.platformAdmin.findMany({
        select: {
          id: true,
          email: true,
          name: true,
          role: true,
          status: true,
          twoFactorEnabled: true,
          lastLoginAt: true,
        },
      }),
      this.prisma.platformAuditLog.findMany({
        where: { severity: { in: ['WARN', 'CRITICAL'] } },
        orderBy: { createdAt: 'desc' },
        take: 12,
      }),
      this.prisma.platformAuditLog.groupBy({
        by: ['ipAddress'],
        where: {
          action: { in: FAILED_LOGIN_ACTIONS },
          createdAt: { gte: day },
          ipAddress: { not: null },
        },
        _count: true,
        orderBy: { _count: { ipAddress: 'desc' } },
        take: 5,
      }),
    ]);

    const activeStaff = staff.filter((s) => s.status === 'ACTIVE');
    const withTwoFactor = activeStaff.filter((s) => s.twoFactorEnabled);
    const withoutTwoFactor = activeStaff.filter((s) => !s.twoFactorEnabled);
    const coverage = activeStaff.length
      ? Math.round((withTwoFactor.length / activeStaff.length) * 100)
      : 0;

    return {
      failedLogins24h,
      successfulLogins24h,
      critical7d,
      warn7d,
      activeSessions,
      lockedAccounts,
      staff: {
        active: activeStaff.length,
        disabled: staff.length - activeStaff.length,
        twoFactorCoveragePercent: coverage,
        withoutTwoFactor: withoutTwoFactor.map((s) => ({
          id: s.id,
          email: s.email,
          name: s.name,
          role: s.role,
        })),
      },
      topFailedIps: topFailedIps.map((r) => ({ ip: r.ipAddress, attempts: r._count })),
      recentEvents,
    };
  }
}
