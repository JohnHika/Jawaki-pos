import {
  Injectable,
  CanActivate,
  ExecutionContext,
  Logger,
  HttpException,
  HttpStatus,
} from '@nestjs/common';
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
      throw new HttpException(
        {
          message: 'A branch ID is required to use the AI assistant.',
          code: 'AI_BRANCH_ID_MISSING',
        },
        HttpStatus.BAD_REQUEST,
      );
    }

    const canUse = await this.billingService.canUseAi(branchId);
    if (!canUse) {
      this.logger.warn(`Branch ${branchId} does not have active AI subscription`);
      throw new HttpException(
        {
          message: 'This branch needs an active AI subscription to use the assistant.',
          code: 'AI_SUBSCRIPTION_REQUIRED',
        },
        HttpStatus.PAYMENT_REQUIRED,
      );
    }
    return true;
  }
}
