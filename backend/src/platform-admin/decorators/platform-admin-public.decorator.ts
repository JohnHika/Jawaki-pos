import { SetMetadata } from '@nestjs/common';

/**
 * Marks a platform-admin route as public (no PlatformAdminGuard check).
 * Currently only the login endpoint uses this; every other route under
 * /platform-admin requires a platform-issued JWT (type='platform').
 */
export const PLATFORM_ADMIN_PUBLIC_KEY = 'platformAdminPublic';
export const PlatformAdminPublic = () => SetMetadata(PLATFORM_ADMIN_PUBLIC_KEY, true);