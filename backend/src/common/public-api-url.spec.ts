import { publicApiBase } from './public-api-url';

describe('publicApiBase', () => {
  const config = (values: Record<string, string>) =>
    ({ get: (key: string) => values[key] }) as any;

  it('prefers an explicitly configured API URL', () => {
    expect(
      publicApiBase(
        config({
          PUBLIC_API_URL: 'https://api.example.com/api/v1/',
          VERCEL_PROJECT_PRODUCTION_URL: 'api-project.vercel.app',
          RENDER_EXTERNAL_URL: 'legacy.onrender.com',
        }),
      ),
    ).toBe('https://api.example.com/api/v1');
  });

  it('uses the stable Vercel production domain for production callbacks', () => {
    expect(
      publicApiBase(
        config({
          VERCEL_ENV: 'production',
          VERCEL_URL: 'api-project-random.vercel.app',
          VERCEL_PROJECT_PRODUCTION_URL: 'api.example.com',
        }),
      ),
    ).toBe('https://api.example.com');
  });

  it('uses the deployment URL for preview callbacks', () => {
    expect(
      publicApiBase(
        config({
          VERCEL_ENV: 'preview',
          VERCEL_URL: 'api-project-branch.vercel.app',
          VERCEL_PROJECT_PRODUCTION_URL: 'api.example.com',
        }),
      ),
    ).toBe('https://api-project-branch.vercel.app');
  });

  it('keeps Render URLs working and returns null when no host is configured', () => {
    expect(publicApiBase(config({ RENDER_EXTERNAL_URL: 'https://legacy.onrender.com/' }))).toBe(
      'https://legacy.onrender.com',
    );
    expect(publicApiBase(config({}))).toBeNull();
  });
});
