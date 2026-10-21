import EmbeddedPostgres from 'embedded-postgres';
import fs from 'node:fs';

const dataDir = new URL('./data', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const fresh = !fs.existsSync(dataDir + '/PG_VERSION');
const pg = new EmbeddedPostgres({
  databaseDir: dataDir,
  user: 'aca',
  password: 'aca_local_only',
  port: 54329,
  persistent: true,
});
if (fresh) await pg.initialise();
await pg.start();
if (fresh) await pg.createDatabase('aca_dev');
console.log('PG_READY');
setInterval(() => {}, 1 << 30);
