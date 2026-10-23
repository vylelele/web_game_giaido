import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const root = path.dirname(new URL(import.meta.url).pathname);
const html = fs.readFileSync(path.join(root, 'public', 'index.html'), 'utf8');
const sql = fs.readFileSync(path.join(root, 'supabase', 'supabase.sql'), 'utf8');
const config = fs.readFileSync(path.join(root, 'public', 'config.js'), 'utf8');
const scriptBlocks = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/gi)].map(m => m[1]).filter(s => s.trim());
assert.ok(scriptBlocks.length >= 1, 'expected inline game script');
for (const source of scriptBlocks) new vm.Script(source, { filename: 'index.html:inline-script' });

for (const rpcName of ['get_room_state', 'create_room', 'join_room', 'submit_answer', 'submit_final']) {
  assert.ok(sql.toLowerCase().includes(`function public.${rpcName}`), `missing SQL RPC ${rpcName}`);
}
for (const [stage, expected] of [[1, 'eye,moon,sun,star,key'], [2, '48'], [3, '37'], [4, 'c3'], [5, 'thủytinh'], [6, 'candle'], [7, '2'], [8, 'moon']]) {
  const stageAt = sql.indexOf(`when ${stage} then`);
  assert.ok(stageAt >= 0, `missing server check for stage ${stage}`);
  const snippet = sql.slice(stageAt, stageAt + 180).toLowerCase();
  assert.ok(snippet.includes(expected), `server answer for stage ${stage} does not match expected`);
}
assert.ok(sql.includes("if v_answer<>'3487'"), 'final lock must be checked on the server');
assert.ok(sql.includes('alter table public.game_rooms enable row level security'), 'RLS must be enabled');
assert.ok(sql.includes('revoke all on public.game_rooms from anon, authenticated'), 'direct table access must be revoked');
assert.ok(sql.includes('grant execute on function public.submit_answer'), 'RPC execute grant is missing');
assert.ok(sql.includes('v_role<>v_owner'), 'server must restrict which player submits each step');
assert.ok(/'clue',case when v_role='A'/.test(sql), 'private role clues must be distinct');
assert.ok(sql.includes("'gameVersion',4"), 'server must expose the game version for client/backend mismatch detection');
assert.ok(html.includes('hasCurrentPuzzleSchema'), 'frontend must detect a stale puzzle payload instead of showing an empty answer area');
assert.ok(html.includes('BACKEND CHƯA ĐỒNG BỘ'), 'frontend must explain how to repair a stale backend');

for (const id of ['clock', 'shelf', 'map', 'cipher', 'cabinet', 'desk', 'gears', 'vault']) {
  assert.ok(html.includes(`data-object="${id}"`), `missing scene hotspot ${id}`);
}
for (const kind of ["p.kind==='order'", "p.kind==='choice'", "p.kind==='text'", "p.kind==='grid'", "p.kind==='cipher'", "p.kind==='gears'", "p.kind==='letters'"]) {
  assert.ok(html.includes(kind), `missing interactive widget type: ${kind}`);
}
assert.ok(html.includes("rpc('submit_answer'"), 'answer must be submitted to the server RPC');
assert.ok(html.includes("rpc('submit_final'"), 'final lock must be submitted to the server RPC');
assert.ok(!/DEMO_PUZZLES|startDemo|isDemo|demoAdvance|switchDemoRole/i.test(html), 'production HTML must not contain offline demo paths');
assert.ok(!html.includes('3487'), 'final answer must not be shipped in production HTML');
assert.ok(!html.toLowerCase().includes('eye,moon,sun,star,key'), 'relic order answer must not be shipped in production HTML');
assert.ok(!/service_role\s*[:=]/i.test(config) && !/SUPABASE_.*service_role/i.test(config), 'public config must not assign a privileged key');

const perms = ['EYE', 'MOON', 'SUN', 'STAR', 'KEY'];
function permutations(xs) {
  if (xs.length < 2) return [xs];
  return xs.flatMap((x, i) => permutations(xs.filter((_, j) => i !== j)).map(rest => [x, ...rest]));
}
const valid = permutations(perms).filter(p => p[0] === 'EYE' && p[4] === 'KEY' && p.indexOf('STAR') === p.indexOf('SUN') + 1 && p.indexOf('MOON') < p.indexOf('SUN'));
assert.deepEqual(valid, [['EYE', 'MOON', 'SUN', 'STAR', 'KEY']], 'relic ordering must have exactly one solution');

assert.ok(!fs.existsSync(path.join(root, 'public', 'supabase.sql')), 'server answer SQL must stay outside the public output directory');
console.log('PASS: inline JS parses; all 8 stages and final lock have server checks; roles are restricted; direct table access is revoked; interactive scene/puzzle widgets exist; production HTML contains no offline answer checking; SQL stays outside public output; the ordering puzzle has one unique solution.');
console.log('NOTE: live Supabase SQL execution and two-device integration still require a configured Supabase project.');
