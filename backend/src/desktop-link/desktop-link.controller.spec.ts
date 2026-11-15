import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { ThrottlerModule } from '@nestjs/throttler';
import { THROTTLER_LIMITERS } from '../common/throttler/throttler-limiters';
import * as request from 'supertest';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { DesktopLinkController } from './desktop-link.controller';
import { DesktopLinkService } from './desktop-link.service';

/**
 * The computer polls `status` every 2 seconds until the phone answers.
 * The limiters are the same list app.module.ts registers.
 */
describe('DesktopLinkController limits', () => {
  let app: INestApplication;

  beforeAll(async () => {
    const moduleFixture = await Test.createTestingModule({
      imports: [
        ThrottlerModule.forRoot(THROTTLER_LIMITERS),
      ],
      controllers: [DesktopLinkController],
      providers: [
        {
          provide: DesktopLinkService,
          useValue: {
            status: jest.fn(async () => ({ status: 'pending' })),
          },
        },
      ],
    })
      .overrideGuard(JwtAuthGuard)
      .useValue({ canActivate: () => true })
      .compile();

    app = moduleFixture.createNestApplication();
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  it('a computer can keep polling for a minute while the phone decides', async () => {
    const codes: number[] = [];
    for (let i = 0; i < 30; i++) {
      const res = await request(app.getHttpServer())
        .get('/auth/desktop-link/status')
        .query({ linkId: 'link-1' });
      codes.push(res.status);
    }
    expect(codes.filter((code) => code !== 200)).toEqual([]);
  });
});
