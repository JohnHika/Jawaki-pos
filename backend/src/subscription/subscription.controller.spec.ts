import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import * as request from 'supertest';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { SubscriptionModule } from './subscription.module';
import { SubscriptionService } from './subscription.service';

describe('SubscriptionController (e2e)', () => {
  let app: INestApplication;
  const subscriptionService = {
    getCurrentPlan: jest.fn(),
    changePlan: jest.fn(),
    listInvoices: jest.fn(),
  };

  beforeEach(async () => {
    const moduleFixture = await Test.createTestingModule({
      imports: [SubscriptionModule],
    })
      .overrideProvider(SubscriptionService)
      .useValue(subscriptionService)
      .overrideGuard(JwtAuthGuard)
      .useValue({
        canActivate: (context: any) => {
          context.switchToHttp().getRequest().user = { tenantId: 'tenant-1' };
          return true;
        },
      })
      .compile();

    app = moduleFixture.createNestApplication();
    app.enableVersioning({ type: 0 /* URI */, defaultVersion: '1', prefix: 'api/v' });
    await app.init();

    subscriptionService.getCurrentPlan.mockReset();
    subscriptionService.changePlan.mockReset();
    subscriptionService.listInvoices.mockReset();
  });

  afterEach(async () => {
    await app.close();
  });

  describe('GET /v1/subscription/plan', () => {
    it('returns current plan details', async () => {
      subscriptionService.getCurrentPlan.mockResolvedValue({
        plan: 'CORE',
        subscriptionStatus: 'ACTIVE',
        maxBranches: 3,
        maxUsers: 10,
      });

      const { body } = await request(app.getHttpServer())
        .get('/api/v1/subscription/plan')
        .set('Authorization', 'Bearer fake-jwt')
        .expect(200);

      expect(body).toEqual({
        plan: 'CORE',
        subscriptionStatus: 'ACTIVE',
        maxBranches: 3,
        maxUsers: 10,
      });
      expect(subscriptionService.getCurrentPlan).toHaveBeenCalled();
    });
  });

  describe('POST /v1/subscription/change-plan', () => {
    it('switches from CORE to ENTERPRISE', async () => {
      subscriptionService.changePlan.mockResolvedValue({
        plan: 'ENTERPRISE',
        subscriptionStatus: 'ACTIVE',
        maxBranches: 10,
        maxUsers: 50,
      });

      const { body } = await request(app.getHttpServer())
        .post('/api/v1/subscription/change-plan')
        .set('Authorization', 'Bearer fake-jwt')
        .send({ plan: 'ENTERPRISE' })
        .expect(201);

      expect(body).toEqual({
        plan: 'ENTERPRISE',
        subscriptionStatus: 'ACTIVE',
        maxBranches: 10,
        maxUsers: 50,
      });
      expect(subscriptionService.changePlan).toHaveBeenCalledWith(expect.anything(), 'ENTERPRISE');
    });
  });
});
