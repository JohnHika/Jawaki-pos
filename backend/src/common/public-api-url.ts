import { ConfigService } from '@nestjs/config';

/**
 * Resolve this deployment's public API base without requiring a host-specific
 * setting. Explicit URLs win; on Vercel, production callbacks use the stable
 * production domain while previews use their own deployment URL. Render
 * remains supported for older environments.
 */
export function publicApiBase(config: ConfigService): string | null {
  const explicit = [
    config.get<string>('PUBLIC_API_URL'),
    config.get<string>('API_PUBLIC_URL'),
  ].find((value) => value?.trim());

  const vercelEnvironment = config.get<string>('VERCEL_ENV')?.trim().toLowerCase();
  const vercelDeployment = config.get<string>('VERCEL_URL');
  const vercelProduction = config.get<string>('VERCEL_PROJECT_PRODUCTION_URL');
  const platformUrl =
    vercelEnvironment === 'preview'
      ? vercelDeployment || vercelProduction
      : vercelProduction || vercelDeployment;

  const base = explicit || platformUrl || config.get<string>('RENDER_EXTERNAL_URL');
  if (!base?.trim()) return null;

  const normalized = base.trim().replace(/\/+$/, '');
  return /^https?:\/\//i.test(normalized) ? normalized : `https://${normalized}`;
}
