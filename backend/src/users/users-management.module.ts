import { Module } from '@nestjs/common';
import { UsersManagementService } from './users-management.service';
import { UsersManagementController } from './users-management.controller';
import { AuditModule } from '../audit/audit.module';
import { PermissionsModule } from '../permissions/permissions.module';

@Module({
  imports: [AuditModule, PermissionsModule],
  providers: [UsersManagementService],
  controllers: [UsersManagementController],
  exports: [UsersManagementService],
})
export class UsersManagementModule {}
