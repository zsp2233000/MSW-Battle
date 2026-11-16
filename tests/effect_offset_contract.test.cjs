const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const read = p => fs.readFileSync(path.join(__dirname, '..', p), 'utf8');
const CATALOG = 'RootDesk/MyDesk/Combat/MonsterCatalog.mlua';
const csvRows = file => {
  const [header, ...rows] = read(file).replace(/^﻿/, '').trim().split(/\r?\n/).map(line => line.split(','));
  return { header, rows: rows.map(cells => Object.fromEntries(header.map((name, i) => [name, cells[i]]))) };
};
function methodBody(source, name) {
  const match = source.match(new RegExp(`method [\\w<>, ]+ ${name}\\([^)]*\\)([\\s\\S]*?)\\n    end\\b`));
  assert.ok(match, `${name} must exist`);
  return match[1];
}

test('EffectOffsetData is a server-only userdataset with EffectRUID, OffsetX and OffsetY columns', () => {
  const meta = JSON.parse(read('RootDesk/MyDesk/Data/EffectOffsetData.userdataset'));
  assert.equal(meta.ContentProto.Json.name, 'EffectOffsetData');
  assert.equal(meta.ContentProto.Json.serveronly, true);
  assert.equal(meta.EntryKey, `userdataset://${meta.ContentProto.Json.id}`);
  const monster = JSON.parse(read('RootDesk/MyDesk/Data/MonsterData.userdataset'));
  assert.notEqual(meta.ContentProto.Json.id, monster.ContentProto.Json.id, 'its own dataset id');
  assert.deepEqual(csvRows('RootDesk/MyDesk/Data/EffectOffsetData.csv').header, ['EffectRUID', 'OffsetX', 'OffsetY']);
});

test('shipped offsets are well formed: 32 hex RUIDs, unique, finite numbers', () => {
  const { rows } = csvRows('RootDesk/MyDesk/Data/EffectOffsetData.csv');
  assert.ok(rows.length >= 3);
  const seen = new Set();
  for (const row of rows) {
    assert.match(row.EffectRUID, /^[0-9a-f]{32}$/i);
    assert.ok(!seen.has(row.EffectRUID), `${row.EffectRUID} listed once`);
    seen.add(row.EffectRUID);
    for (const field of ['OffsetX', 'OffsetY']) assert.ok(Number.isFinite(Number(row[field])) && row[field] !== '', field);
  }
});

test('the three pixies hit effects are seeded to sit higher, with no sideways shift', () => {
  const offsets = Object.fromEntries(csvRows('RootDesk/MyDesk/Data/EffectOffsetData.csv').rows.map(r => [r.EffectRUID, r]));
  const monsters = Object.fromEntries(csvRows('RootDesk/MyDesk/Data/MonsterData.csv').rows.map(r => [r.MonsterId, r]));
  for (const id of ['monster_moon_pixie', 'monster_sun_pixie', 'monster_star_pixie']) {
    const entry = offsets[monsters[id].HitEffectRUID];
    assert.ok(entry, `${id} hit effect is registered`);
    assert.equal(Number(entry.OffsetX), 0);
    assert.ok(Number(entry.OffsetY) > 0, `${id} lifted`);
  }
});

test('the catalog loads the table with MonsterData and rejects bad data but tolerates a missing or empty table', () => {
  const source = read(CATALOG);
  assert.match(source, /property string EffectOffsetDataSetName = "EffectOffsetData"/);
  const load = methodBody(source, 'Load');
  assert.match(load, /self:LoadEffectOffsets\(\) == false/, 'a bad table fails the whole load');
  assert.ok(load.indexOf('LoadEffectOffsets') > load.indexOf('ValidateRoster'), 'loaded after the monster rows');
  const parse = methodBody(source, 'LoadEffectOffsetsFrom');
  assert.match(parse, /dataset == nil then return true/, 'missing table is not an error');
  assert.match(parse, /rowCount == nil or rowCount <= 0 then return true/, 'empty table is not an error');
  for (const message of ['duplicate EffectRUID', 'invalid EffectRUID', 'invalid numeric value']) {
    assert.ok(parse.includes(message) || source.includes(message), `${message} is reported`);
  }
  assert.match(source, /%x/, 'RUIDs are checked as hex');
  assert.match(methodBody(source, 'GetEffectOffset'), /return \{ x = 0, y = 0 \}|x = 0, y = 0/, 'unregistered effects read as zero');
});

test('profiles resolve their three offsets and the dex rows publish them', () => {
  const source = read(CATALOG);
  const resolve = methodBody(source, 'ResolveProfileOffsets');
  for (const field of ['AttackEffectOffsetX', 'AttackEffectOffsetY', 'HitEffectOffsetX', 'HitEffectOffsetY', 'ProjectileOffsetX', 'ProjectileOffsetY']) {
    assert.ok(resolve.includes(`profile.${field}`), field);
  }
  const rows = methodBody(source, 'GetDexRows');
  for (const field of ['attackEffectOffsetX', 'attackEffectOffsetY', 'hitEffectOffsetX', 'hitEffectOffsetY', 'projectileOffsetX', 'projectileOffsetY']) {
    assert.ok(rows.includes(`${field} =`), field);
  }
});

test('battle broadcasts the resolved offset with the effect RUID and attaches it as a local position', () => {
  const presentation = read('RootDesk/MyDesk/Combat/BattleHitEffectPresentation.mlua');
  assert.match(presentation, /method void PlayHitEffect\(string effectRUID, number offsetX, number offsetY\)/);
  assert.match(presentation, /method void PlayAttackEffect\(string effectRUID, number offsetX, number offsetY\)/);
  assert.match(presentation, /method void PlayAttachedEffect\(string effectRUID, string effectKind, number offsetX, number offsetY\)/);
  assert.match(presentation, /PlayEffectAttached\(effectRUID, target, Vector3\(/);
  const unit = read('RootDesk/MyDesk/Combat/BattleUnit.mlua');
  assert.match(unit, /presentation:PlayHitEffect\(hitEffectRUID, hitEffectOffsetX or 0, hitEffectOffsetY or 0\)/);
  assert.match(read('RootDesk/MyDesk/Combat/BattleSession.mlua'), /hitEffectOffsetX = policy\.hitEffectOffsetX/);
  const composition = read('RootDesk/MyDesk/Combat/BattleAttackComposition.mlua');
  assert.match(composition, /presentation:PlayAttackEffect\(self\._T\.profile\.AttackEffectRUID, self\._T\.profile\.AttackEffectOffsetX, self\._T\.profile\.AttackEffectOffsetY\)/);
  assert.match(composition, /ProjectileOffsetX/, 'the ball starts at the shifted point');
});

test('the dex stage shifts effects and the ball start by the published offsets and lists them in the details', () => {
  const dex = read('RootDesk/MyDesk/Dex/MonsterDex.mlua');
  const show = methodBody(dex, 'ShowEffect');
  assert.match(show, /OffsetX/);
  assert.match(show, /OffsetY/);
  assert.match(show, /pixelsPerUnit/, 'world units are scaled to canvas pixels');
  const flight = methodBody(dex, 'ProjectileFlight');
  assert.match(flight, /projectileOffsetX/);
  assert.match(flight, /projectileOffsetY/);
  assert.match(dex, /key = "effectOffset", label = "特效偏移", kind = "effectOffset"/);
  const detail = methodBody(dex, 'DetailText');
  for (const field of ['attackEffectOffsetX', 'hitEffectOffsetX', 'projectileOffsetX']) assert.match(detail, new RegExp(field));
  assert.match(detail, /UnsetText|unset/, 'all-zero offsets read as 未設定');
});
