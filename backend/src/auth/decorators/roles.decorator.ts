import { SetMetadata } from '@nestjs/common';
import { LegacyUserRole } from '@prisma/client';

export const ROLES_KEY = 'roles';
export const Roles = (...roles: LegacyUserRole[]) => SetMetadata(ROLES_KEY, roles);
