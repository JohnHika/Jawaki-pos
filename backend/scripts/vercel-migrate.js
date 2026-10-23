const path = require('node:path');
const { spawnSync } = require('node:child_process');

if (process.env.VERCEL_ENV !== 'production') {
  console.log('Skipping database migrations outside Vercel production.');
  process.exit(0);
}

if (process.env.SKIP_DATABASE_MIGRATIONS === 'true') {
  console.log('Skipping database migrations for this explicitly requested code-only deployment.');
  process.exit(0);
}

console.log('Applying Prisma migrations for the Vercel production deployment.');
const backendRoot = path.resolve(__dirname, '..');
const result = spawnSync(
  process.execPath,
  ['node_modules/prisma/build/index.js', 'migrate', 'deploy'],
  { cwd: backendRoot, env: process.env, stdio: 'inherit' },
);

if (result.error) {
  console.error('Could not start Prisma migrate deploy:', result.error.message);
  process.exit(1);
}

process.exit(result.status ?? 1);
