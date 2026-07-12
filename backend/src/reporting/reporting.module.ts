import { Module } from '@nestjs/common';
import { ReportingController } from './reporting.controller';
import { ReportingService } from './reporting.service';
import { ReportExportService } from './report-export.service';
import { PrismaModule } from '../common/prisma/prisma.module';
import { RedisModule } from '../common/redis/redis.module';

@Module({
  imports: [PrismaModule, RedisModule],
  controllers: [ReportingController],
  providers: [ReportingService, ReportExportService],
  exports: [ReportingService, ReportExportService],
})
export class ReportingModule {}
