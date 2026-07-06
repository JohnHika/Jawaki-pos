import { Injectable, CanActivate, ExecutionContext, Logger } from '@nestjs/common';
import { AiBillingService } from './ai-billing.service';

@Injectable()
export class AiAccessGuard implements CanActivate {
  private readonly logger = new Logger(AiAccessGuard.name);

  constructor(private readonly billingService: AiBillingService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const branchId = request.headers['x-branch-id'] || request.body?.branchId || request.query?.branchId;

    if (!branchId) {
      this.logger.warn('No branch ID provided in request');
      return false;
    }

    const canUse = await this.billingService.canUseAi(branchId);
    if (!canUse) {
      this.logger.warn(`Branch ${branchId} does not have active AI subscription`);
    }
    return canUse;
  }
}
