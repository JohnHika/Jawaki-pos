import { BadRequestException, ConflictException, Injectable } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { isCurrentPolicyVersion, POLICY_VERSIONS, PolicyType } from './policy-versions';

@Injectable()
export class LegalPolicyService {
  constructor(private readonly prisma: PrismaService) {}

  async accept(tenantId: string, userId: string, policyType: string, policyVersion: string) {
    if (!isCurrentPolicyVersion(policyType, policyVersion)) {
      throw new BadRequestException('This policy version is no longer current. Open the latest policy and accept it again.');
    }
    return this.prisma.policyAcceptance.upsert({
      where: {
        tenantId_acceptedByUserId_policyType_policyVersion: {
          tenantId,
          acceptedByUserId: userId,
          policyType,
          policyVersion,
        },
      },
      create: {
        tenantId,
        acceptedByUserId: userId,
        policyType,
        policyVersion,
        source: 'MOBILE_APP',
      },
      // Keep the first acceptance time as the evidence of when consent was
      // given; repeated requests are safe and idempotent.
      update: {},
      select: { policyType: true, policyVersion: true, acceptedAt: true },
    });
  }

  async hasCurrentAcceptance(tenantId: string, policyType: PolicyType) {
    return (await this.prisma.policyAcceptance.findFirst({
      where: { tenantId, policyType, policyVersion: this.currentVersion(policyType) },
      select: { id: true },
    })) != null;
  }

  async assertCurrentAcceptance(tenantId: string, policyType: PolicyType) {
    if (!(await this.hasCurrentAcceptance(tenantId, policyType))) {
      throw new ConflictException('Review and accept the current policy before continuing.');
    }
  }

  async listForOwner(tenantId: string, userId: string) {
    return this.prisma.policyAcceptance.findMany({
      where: { tenantId, acceptedByUserId: userId },
      orderBy: [{ acceptedAt: 'desc' }, { policyType: 'asc' }],
      select: { policyType: true, policyVersion: true, source: true, acceptedAt: true },
    });
  }

  private currentVersion(type: PolicyType) {
    // Keep service lookups tied to the same version map used by the endpoint.
    return POLICY_VERSIONS[type];
  }
}
