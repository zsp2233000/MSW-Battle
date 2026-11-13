const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const read = p => fs.readFileSync(path.join(__dirname, '..', p), 'utf8');
const { ModelBuilder } = require('../.agents/skills/msw-general/scripts/model/msw_model_builder.cjs');

test('battle actors reference one authored name tag model without appearance overrides', () => {
  const shared = ModelBuilder.read(path.join(__dirname, '../RootDesk/MyDesk/Models/MapObjects/BattleNameTag.model'));
  assert.ok(shared.hasComponent('MOD.Core.NameTagComponent'));
  assert.ok(shared.getValue('MOD.Core.NameTagComponent', 'FontSize', 0) > 0);
  assert.ok(shared.getValue('MOD.Core.NameTagComponent', 'OffsetY', 0) < 0);
  for (const file of ['Monsters/BattleUnit.model', 'MapObjects/BattleViewVisual.model']) {
    const model = ModelBuilder.read(path.join(__dirname, '../RootDesk/MyDesk/Models', file));
    assert.equal(model.hasComponent('MOD.Core.NameTagComponent'), false, file);
    const child = model.getChild('NameTag');
    assert.ok(child, file);
    assert.equal(child.Model.BaseModelId, shared.snapshot().model_id, file);
    assert.ok(!child.Model.Components.includes('MOD.Core.NameTagComponent'), file);
    assert.ok(!child.Model.Values.some(v => v.TargetType === 'MOD.Core.NameTagComponent'), file);
  }
  const unit = read('RootDesk/MyDesk/Combat/BattleUnit.mlua');
  const session = read('RootDesk/MyDesk/Combat/BattleSession.mlua');
  assert.doesNotMatch(unit + session, /AddComponent\("MOD\.Core\.NameTagComponent"\)/);
  const update = unit.match(/method void UpdateNameTag\(Entity display\)([\s\S]*?)\n    end/)[1];
  assert.doesNotMatch(update, /tag\.(?:FontSize|FontColor|Bold|FontOffset|OffsetY|NameTagRUID)\s*=/);
});

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
