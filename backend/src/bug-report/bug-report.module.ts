import { Module } from '@nestjs/common';
import { BugReportController } from './bug-report.controller';
import { BugReportService } from './bug-report.service';

@Module({
  controllers: [BugReportController],
  providers: [BugReportService],
  exports: [BugReportService],
})
export class BugReportModule {}
