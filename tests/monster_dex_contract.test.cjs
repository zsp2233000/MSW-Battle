const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const read = p => fs.readFileSync(path.join(__dirname, '..', p), 'utf8');
const CATALOG = 'RootDesk/MyDesk/Combat/MonsterCatalog.mlua';
const SERVICE = 'RootDesk/MyDesk/Dex/MonsterDexService.mlua';

function methodBody(source, name) {
  const match = source.match(new RegExp(`method [\\w<>, ]+ ${name}\\([^)]*\\)([\\s\\S]*?)\\n    end\\b`));
  assert.ok(match, `${name} must exist`);
  return match[1];
}

// Statements of a method body with comments and blank lines removed.
function statements(body) {
  return body.split(/\r?\n/).map(line => line.trim()).filter(line => line && !line.startsWith('--'));
}

test('the catalog publishes one dex row per data row in table order', () => {
  const catalog = read(CATALOG);
  const dex = methodBody(catalog, 'GetDexRows');
  assert.doesNotMatch(dex, /table\.sort/, 'dex rows keep table order; only deployment options sort by id');
  assert.match(dex, /rowOrder/, 'dex rows walk the recorded table order');
  const load = methodBody(catalog, 'Load');
  assert.match(load, /rowOrder/, 'Load records the data table row order');
});

test('every presentation field of a dex row comes from the validated profile', () => {
  const dex = methodBody(read(CATALOG), 'GetDexRows');
  const fields = [
    'MonsterId', 'MonsterName',
    'StandAnimationRUID', 'MoveAnimationRUID', 'AttackAnimationRUID', 'HurtAnimationRUID', 'DieAnimationRUID',
    'AttackEffectRUID', 'AttackEffectFrame', 'HitEffectRUID', 'AttackDamageFrame',
    'AttackSoundRUID', 'HurtSoundRUID', 'DieSoundRUID',
    'ProjectileRUID', 'ProjectileSpeed',
    'AttackEffectDelaySeconds', 'ImpactDelaySeconds', 'AttackAnimationDurationSeconds',
    'AttackRange',
  ];
  for (const field of fields) assert.match(dex, new RegExp(`profile\\.${field}\\b`), `dex row must publish ${field}`);
  for (const key of ['scaleX', 'scaleY', 'bodyOffsetX', 'bodyOffsetY', 'order']) {
    assert.match(dex, new RegExp(`\\b${key}\\b`), `dex row must publish ${key}`);
  }
});

test('dex rows carry no combat numbers, so they cannot change with monster level', () => {
  const dex = methodBody(read(CATALOG), 'GetDexRows');
  for (const field of ['MaxHp', 'AttackDamageMin', 'AttackDamageMax', 'GrowthRate', 'MoveSpeed', 'KnockbackDistance']) {
    assert.doesNotMatch(dex, new RegExp(field), `${field} is not presentation data`);
  }
});

test('deployment options keep their id ordering and fields', () => {
  const options = methodBody(read(CATALOG), 'GetDeploymentOptions');
  assert.match(options, /table\.sort\(options, function\(left, right\) return left\.monsterId < right\.monsterId end\)/);
});

test('the body probe also records the model scale next to the scaled centre', () => {
  const measure = methodBody(read(CATALOG), 'MeasureBodyCenterOffset');
  assert.match(measure, /scaleX\s*=\s*math\.abs\(scale\.x\)/);
  assert.match(measure, /scaleY\s*=/);
});

test('MonsterData stays server only', () => {
  const dataset = JSON.parse(read('RootDesk/MyDesk/Data/MonsterData.userdataset'));
  assert.equal(dataset.ContentProto.Json.serveronly, true);
});

test('the dex request is refused first thing outside Maker Play and replies only to the sender', () => {
  const service = read(SERVICE);
  assert.match(service, /^@Logic\s*\nscript MonsterDexService extends Logic/m);
  assert.match(service, /@ExecSpace\("Server"\)\s*\n\s*method void RequestRows\(\)/);
  const body = statements(methodBody(service, 'RequestRows'));
  assert.equal(body[0], 'if not Environment:IsMakerPlay() then return end',
    'the published-environment refusal must be the first statement of the handler');
  assert.match(body.join('\n'), /self:Receive\(rows, senderUserId\)/);
});

test('the client keeps only the latest reply in memory and never persists it', () => {
  const service = read(SERVICE);
  assert.match(service, /@ExecSpace\("Client"\)\s*\n\s*method void Receive\(table rows\)/);
  const receive = methodBody(service, 'Receive');
  assert.match(receive, /self\._T\.latest = rows/, 'each reply replaces the cached one');
  assert.doesNotMatch(service, /DataStorage|@Sync|property table/, 'no persistent or synchronized copy');
});
