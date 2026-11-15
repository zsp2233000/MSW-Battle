const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const { UIBuilder } = require('../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');

const root = path.join(__dirname, '..');
const read = p => fs.readFileSync(path.join(root, p), 'utf8');
const CATALOG = 'RootDesk/MyDesk/Combat/MonsterCatalog.mlua';
const MODULE = 'RootDesk/MyDesk/Dex/MonsterDex.mlua';
const SERVICE = 'RootDesk/MyDesk/Dex/MonsterDexService.mlua';
const CSV = 'RootDesk/MyDesk/Data/MonsterData.csv';
const UI_FILES = ['ui/MonsterDexGroup.ui', 'ui/FormationGroup.ui'];
// Delays the catalog derives at load time; they are not data table columns.
const DERIVED_PROFILE_FIELDS = ['AttackEffectDelaySeconds', 'ImpactDelaySeconds', 'AttackAnimationDurationSeconds'];

function methodBody(source, name) {
  const match = source.match(new RegExp(`method [\\w<>, ]+ ${name}\\([^)]*\\)([\\s\\S]*?)\\n    end\\b`));
  assert.ok(match, `${name} must exist`);
  return match[1];
}

const statements = body => body.split(/\r?\n/).map(line => line.trim()).filter(line => line && !line.startsWith('--'));
const dexRowBody = () => methodBody(read(CATALOG), 'GetDexRows');
const csvColumns = () => read(CSV).replace(/^﻿/, '').split(/\r?\n/)[0].split(',');

test('every data field a dex row copies is a data table column (or a documented load-time delay)', () => {
  const columns = csvColumns();
  const fields = [...new Set([...dexRowBody().matchAll(/profile\.(\w+)/g)].map(m => m[1]))];
  assert.ok(fields.length >= 15, 'the dex row reads the presentation fields');
  for (const field of fields) {
    if (DERIVED_PROFILE_FIELDS.includes(field)) continue;
    assert.ok(columns.includes(field), `${field} is a MonsterData column`);
  }
  const catalog = read(CATALOG);
  for (const field of DERIVED_PROFILE_FIELDS) assert.match(catalog, new RegExp(`${field}\\s*=`), `${field} is derived by the catalog`);
});

test('every row field the book reads is published by GetDexRows', () => {
  const published = new Set([...dexRowBody().matchAll(/\b(\w+)\s*=/g)].map(m => m[1]));
  const consumed = new Set();
  for (const source of [read(MODULE), read(SERVICE)]) {
    for (const m of source.matchAll(/\brow\.(\w+)/g)) consumed.add(m[1]);
    for (const m of source.matchAll(/\b(?:field|sound) = "(\w+)"/g)) consumed.add(m[1]);
  }
  assert.ok(consumed.size >= 24, 'the book reads many row fields');
  for (const field of consumed) assert.ok(published.has(field), `row.${field} is published by GetDexRows`);
});

test('every entity property of MonsterDex names an entity authored in the dex or lobby ui', () => {
  const ids = new Set();
  for (const file of UI_FILES) {
    const ui = UIBuilder.read(file);
    for (const entity of ui.listEntities()) {
      const relative = entity.path.split('/').slice(3).join('/');
      if (relative) ids.add(ui.getId(relative));
    }
  }
  const bound = [...read(MODULE).matchAll(/property (\w+) (\w+) = "([0-9a-f-]{36})"/g)];
  assert.ok(bound.length >= 20, 'MonsterDex has its authored bindings');
  for (const [, type, name, id] of bound) assert.ok(ids.has(id), `${name} (${type}) -> ${id} exists in the ui files`);
});

test('the published world gets neither the entry nor a served reply', () => {
  const module = read(MODULE);
  assert.match(methodBody(module, 'OnUpdate'), /local shown = Environment:IsMakerPlay\(\)/, 'the lobby entry is hidden outside Maker Play');
  assert.equal(statements(methodBody(module, 'Open'))[0], 'if not Environment:IsMakerPlay() then return false end');
  const service = read(SERVICE);
  const server = [...service.matchAll(/@ExecSpace\("Server"\)\s*\n\s*method \w+ (\w+)/g)].map(m => m[1]);
  assert.deepEqual(server, ['RequestRows'], 'no other Server method can be called by a client');
  assert.equal(statements(methodBody(service, 'RequestRows'))[0], 'if not Environment:IsMakerPlay() then return end', 'nothing runs before the guard');
  assert.doesNotMatch(read(CATALOG), /@ExecSpace\("(Server|Client)"\)\s*\n\s*method table GetDexRows/, 'GetDexRows is not directly callable by a client');
});
