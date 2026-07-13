import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';

// Claimed jobs older than this are treated as abandoned (the claiming
// device crashed, lost Bluetooth, or was force-closed mid-print) and made
// reclaimable again rather than stuck "claimed" forever.
const CLAIM_STALE_AFTER_MS = 2 * 60 * 1000;

@Injectable()
export class PrintingService {
  constructor(private readonly prisma: PrismaService) {}

  /// Any device on the branch can enqueue a print request — it never talks
  /// to the printer itself, only hands the receipt payload off.
  async enqueue(branchId: string, userId: string | undefined, deviceId: string, payload: Record<string, unknown>) {
    return this.prisma.printJob.create({
      data: {
        branchId,
        requestedById: deviceId,
        requestedByUserId: userId,
        payload: payload as any,
        status: 'pending',
      },
    });
  }

  /// Polled by the single device designated (via [setPrinterDevice]) as the
  /// one holding the Bluetooth connection. Claims and returns pending jobs
  /// (including any this same device had claimed but never completed, and
  /// any abandoned by a device that went away) so it can print them one at
  /// a time in order — never concurrently, since Bluetooth Classic only
  /// supports one active connection.
  async claimPending(branchId: string, deviceId: string) {
    const staleThreshold = new Date(Date.now() - CLAIM_STALE_AFTER_MS);

    await this.prisma.printJob.updateMany({
      where: {
        branchId,
        status: 'claimed',
        claimedAt: { lt: staleThreshold },
      },
      data: { status: 'pending', claimedById: null, claimedAt: null },
    });

    const jobs = await this.prisma.printJob.findMany({
      where: { branchId, status: 'pending' },
      orderBy: { createdAt: 'asc' },
      take: 20,
    });

    if (jobs.length === 0) return [];

    const now = new Date();
    await this.prisma.printJob.updateMany({
      where: { id: { in: jobs.map((j) => j.id) } },
      data: { status: 'claimed', claimedById: deviceId, claimedAt: now },
    });

    return jobs.map((j) => ({ ...j, status: 'claimed', claimedById: deviceId, claimedAt: now }));
  }

  async complete(
    jobId: string,
    branchId: string,
    deviceId: string,
    status: 'printed' | 'failed',
    errorMessage?: string,
  ) {
    const job = await this.prisma.printJob.findFirst({ where: { id: jobId, branchId } });
    if (!job) throw new NotFoundException('Print job not found');
    if (job.claimedById !== deviceId) {
      // Most likely this job's claim already went stale and was reclaimed
      // by another device (or this device retried after a timeout) — not
      // worth failing loudly over, the job's real owner will report status.
      throw new ForbiddenException('This device did not claim that print job');
    }

    return this.prisma.printJob.update({
      where: { id: jobId },
      data: {
        status,
        errorMessage: status === 'failed' ? (errorMessage ?? 'Unknown error') : null,
        completedAt: new Date(),
      },
    });
  }

  /// Lets the requesting device show live status ("queued" -> "printed"/
  /// "failed") for jobs it raised itself, without needing to be the one
  /// draining the queue.
  async listMine(branchId: string, deviceId: string) {
    return this.prisma.printJob.findMany({
      where: { branchId, requestedById: deviceId },
      orderBy: { createdAt: 'desc' },
      take: 20,
    });
  }

  async getPrinterDevice(branchId: string): Promise<string | null> {
    const branch = await this.prisma.branch.findUnique({ where: { id: branchId } });
    if (!branch) throw new NotFoundException('Branch not found');
    const settings = (branch.settings as Record<string, unknown>) ?? {};
    const deviceId = settings.printerDeviceId;
    return typeof deviceId === 'string' && deviceId.length > 0 ? deviceId : null;
  }

  async setPrinterDevice(branchId: string, deviceId: string | null) {
    const branch = await this.prisma.branch.findUnique({ where: { id: branchId } });
    if (!branch) throw new NotFoundException('Branch not found');
    const settings = { ...((branch.settings as Record<string, unknown>) ?? {}) };
    if (deviceId) {
      settings.printerDeviceId = deviceId;
    } else {
      delete settings.printerDeviceId;
    }
    await this.prisma.branch.update({ where: { id: branchId }, data: { settings: settings as any } });
    return { printerDeviceId: deviceId };
  }
}
