import { Module } from '@nestjs/common';
import { CatalogController } from './catalog.controller';
import { CatalogService } from './catalog.service';
import { UploadsModule } from '../uploads/uploads.module';
import { AccountabilityModule } from '../accountability/accountability.module';

@Module({
  imports: [UploadsModule, AccountabilityModule],
  controllers: [CatalogController],
  providers: [CatalogService],
  exports: [CatalogService],
})
export class CatalogModule {}
