import { readdirSync, readFileSync, statSync } from 'fs';
import { join } from 'path';

/**
 * Every key passed to @RequirePermissions(...) must exist in the seeded
 * permission catalog. A typo ('cash_reconciliation.read' vs '.view') makes the
 * endpoint return 403 for every user, including admins, with no other symptom.
 */
function listTs(dir: string, out: string[] = []): string[] {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) listTs(p, out);
    else if (p.endsWith('.ts') && !p.endsWith('.spec.ts')) out.push(p);
  }
  return out;
}

describe('RequirePermissions keys', () => {
  const catalog = new Set(
    [...readFileSync(join(__dirname, '../../scripts/seed-permissions.ts'), 'utf8').matchAll(/key:\s*'([a-z_.]+)'/g)].map(
      (m) => m[1],
    ),
  );

  it('the catalog was parsed', () => {
    expect(catalog.size).toBeGreaterThan(100);
  });

  it('every @RequirePermissions key exists in the seeded catalog', () => {
    const missing: string[] = [];
    for (const file of listTs(join(__dirname, '..'))) {
      const src = readFileSync(file, 'utf8');
      for (const call of src.matchAll(/@RequirePermissions\(([^)]*)\)/g)) {
        for (const key of call[1].matchAll(/['"]([a-z_.]+)['"]/g)) {
          if (!catalog.has(key[1])) missing.push(`${file.split('src')[1]}: ${key[1]}`);
        }
      }
    }
    expect(missing).toEqual([]);
  });
});
