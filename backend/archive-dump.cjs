// One-off archive: dump every Prisma model to JSON before POS teardown.
// Reads DATABASE_URL from backend/.env (never prints it), writes to
// ../pos-archive-2026-10-27/<Model>.json
const fs = require('fs');
const path = require('path');

const envText = fs.readFileSync(path.join(__dirname, '.env'), 'utf8');
for (const line of envText.split(/\r?\n/)) {
  const m = /^\s*DATABASE_URL\s*=\s*"?([^"\n]+)"?\s*$/.exec(line);
  if (m) process.env.DATABASE_URL = m[1].trim();
}
if (!process.env.DATABASE_URL) {
  console.error('DATABASE_URL not found in backend/.env — aborting');
  process.exit(1);
}

const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

const schema = fs.readFileSync(path.join(__dirname, 'prisma', 'schema.prisma'), 'utf8');
const models = [...schema.matchAll(/^model\s+(\w+)/gm)].map(m => m[1]);

const outDir = path.join(__dirname, '..', 'pos-archive-2026-10-27');
fs.mkdirSync(outDir, { recursive: true });

(async () => {
  const summary = [];
  for (const model of models) {
    const key = model[0].toLowerCase() + model.slice(1);
    const delegate = prisma[key];
    if (!delegate || typeof delegate.findMany !== 'function') {
      summary.push({ model, status: 'no-delegate', rows: 0 });
      continue;
    }
    try {
      const rows = await delegate.findMany();
      fs.writeFileSync(path.join(outDir, `${model}.json`), JSON.stringify(rows, null, 2));
      summary.push({ model, status: 'ok', rows: rows.length });
    } catch (e) {
      summary.push({ model, status: `error: ${String(e.message).slice(0, 60)}`, rows: 0 });
    }
  }
  for (const s of summary) console.log(`${s.status.padEnd(10)} ${String(s.rows).padStart(6)}  ${s.model}`);
  await prisma.$disconnect();
})();
