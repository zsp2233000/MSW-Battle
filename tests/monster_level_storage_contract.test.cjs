const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

test('monster levels own a versioned document separate from formation saves', () => {
  const source = fs.readFileSync(path.join(__dirname, '../RootDesk/MyDesk/Combat/MonsterLevelStorage.mlua'), 'utf8');
  assert.match(source, /property string StorageKey = "MonsterLevelsV1"/);
  assert.match(source, /schema = 1/);
  assert.match(source, /monsters = \{\}/);
  assert.match(source, /settled = \{\}/);
  assert.doesNotMatch(source, /_FormationService\.StorageKey|SetAndWait|SetAsync/);
});
