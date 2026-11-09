const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const read = p => fs.readFileSync(path.join(__dirname, '..', p), 'utf8');

test('monster growth columns are required, nonnegative and initialized to 3.5 percent', () => {
  const [header, ...rows] = read('RootDesk/MyDesk/Data/MonsterData.csv')
    .replace(/^\uFEFF/, '').trim().split(/\r?\n/).map(line => line.split(','));
  const catalog = read('RootDesk/MyDesk/Combat/MonsterCatalog.mlua');
  for (const field of ['MaxHpGrowthRate', 'AttackDamageGrowthRate']) {
    const index = header.indexOf(field);
    assert.ok(index >= 0, `missing ${field}`);
    for (const row of rows) assert.equal(Number(row[index]), 0.035);
    assert.match(catalog, new RegExp(`profile\\.${field} = self:ReadNumber\\(row:GetItem\\("${field}"\\), "${field}", monsterId, 0\\)`));
    const required = catalog.match(/local requiredColumns = \{([\s\S]*?)\n        \}/)[1];
    assert.ok(required.includes(`"${field}"`), `${field} must be a required column`);
  }
});
