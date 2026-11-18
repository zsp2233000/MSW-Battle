const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const read = name => fs.readFileSync(path.join(__dirname, '../RootDesk/MyDesk', name), 'utf8');

test('GM formation writes use the same document decoder as player loads', () => {
  const gm = read('GM/GMCommandService.mlua');
  const formations = read('Formations/FormationService.mlua');
  assert.match(gm, /_FormationSchema:DecodeDocument\(/);
  assert.match(formations, /_FormationSchema:DecodeDocument\(/);
  assert.doesNotMatch(gm, /"SAVE_HANDOFF"/);
});
