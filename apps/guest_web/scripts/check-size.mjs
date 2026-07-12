/**
 * Presupuesto de peso de la web de invitados (spec §5.2: interactiva < 1 s
 * en 4G). Falla si el total TRANSFERIDO (gzip) de JS+HTML+CSS supera el
 * límite. Se ejecuta en CI tras el build.
 */
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { gzipSync } from 'node:zlib';

const LIMIT_KB = 220;
const dist = new URL('../dist', import.meta.url).pathname.replace(
  /^\/([A-Za-z]:)/,
  '$1',
);

let total = 0;
const rows = [];
const walk = (dir) => {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) {
      walk(path);
    } else if (/\.(js|css|html)$/.test(name)) {
      const gz = gzipSync(readFileSync(path)).length;
      total += gz;
      rows.push(`${(gz / 1024).toFixed(1).padStart(7)} KB gz  ${name}`);
    }
  }
};
walk(dist);

console.log(rows.join('\n'));
console.log(`${'─'.repeat(40)}\n${(total / 1024).toFixed(1)} KB gz en total (límite ${LIMIT_KB} KB)`);

if (total > LIMIT_KB * 1024) {
  console.error('✖ Presupuesto de peso superado: replantear (lazy imports).');
  process.exit(1);
}
console.log('✓ Dentro del presupuesto.');
