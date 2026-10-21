import { SetMetadata } from '@nestjs/common';
import { PlatformPermission } from '../rbac/platform-permissions';

export const PLATFORM_PERMISSIONS_KEY = 'platformAdmin:permissions';
export const PLATFORM_AUTHENTICATED_KEY = 'platformAdmin:authenticated';
export const PLATFORM_ALLOW_PASSWORD_CHANGE_KEY = 'platformAdmin:allowPasswordChange';

/** The signed-in staff member must hold ALL listed permissions. */
export const RequirePlatformPermission = (...permissions: PlatformPermission[]) =>
  SetMetadata(PLATFORM_PERMISSIONS_KEY, permissions);

/**
 * Any signed-in staff member may call this route (own profile, own sessions,
 * password change). Routes with neither this nor a permission are denied, so
 * a forgotten annotation fails closed.
 */
export const PlatformAuthenticated = () => SetMetadata(PLATFORM_AUTHENTICATED_KEY, true);

/** Reachable even while the account is forced to change its password. */
export const AllowPasswordChange = () => SetMetadata(PLATFORM_ALLOW_PASSWORD_CHANGE_KEY, true);
