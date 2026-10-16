// Independent Node consumer. Run: node integrations/dial_history/read_history.mjs
// Cloud on this Mac: append --cloud. Remote: set DIAL_HISTORY_URL and DIAL_HISTORY_READ_TOKEN.
import { readFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';

let base = process.env.DIAL_HISTORY_URL;
let token = process.env.DIAL_HISTORY_READ_TOKEN;
if (!base) {
  const manifest = JSON.parse(await readFile(join(homedir(), 'Music/Dial/manifest.json'), 'utf8'));
  const cloud = process.argv.includes('--cloud');
  base = cloud ? manifest.cloud_base_url : manifest.local_base_url;
  if (!base) throw new Error('The requested Dial History endpoint is not configured');
  const tokenFile = cloud ? manifest.cloud_access.token_file : manifest.token_file;
  token = (await readFile(tokenFile, 'utf8')).trim();
}
if (!token) throw new Error('DIAL_HISTORY_READ_TOKEN is required for remote access');
const discovery = await fetch(`${base}/.well-known/dial-history`, { signal: AbortSignal.timeout(10000) });
if (!discovery.ok) throw new Error(`Discovery failed: ${discovery.status}`);
const { routes } = await discovery.json();
async function read(route) {
  const response = await fetch(new URL(route, base), {
    headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(60000),
  });
  if (!response.ok) throw new Error(`Dial History failed: ${response.status}`);
  return response.json();
}
const [status, recent] = await Promise.all([read(routes.status), read(`${routes.plays}?limit=5`)]);
console.log(JSON.stringify({ schema_version: recent.schema_version, freshness: recent.freshness,
  saved_records: status.coverage.records,
  months_without_records: status.coverage.months_without_records_between_first_and_last,
  recent_plays: recent.items }, null, 2));
