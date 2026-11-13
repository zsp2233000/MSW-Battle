const assert = require('node:assert/strict');
const test = require('node:test');
const { UIBuilder } = require('../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');

test('result cards provide an initially hidden, noninteractive portrait, name and HP template', () => {
  const ui = UIBuilder.read('ui/BattleGroup.ui');
  const path = 'BattleResultPanel/CardTemplate';
  assert.ok(ui.find(path), 'result card template exists');
  assert.equal(ui.find(path).jsonString.enable, false);
  for (const child of ['PortraitViewport/Portrait', 'MonsterName', 'Identity']) {
    assert.ok(ui.find(`${path}/${child}`), child);
  }
  for (const entity of ui.listEntities().filter(e => e.path.includes('/CardTemplate'))) {
    assert.equal(ui.getComponent(entity.path, 'MOD.Core.ButtonComponent'), null);
    const sprite = ui.getComponent(entity.path, 'MOD.Core.SpriteGUIRendererComponent');
    if (sprite) assert.equal(sprite.RaycastTarget, false);
  }
});

test('the existing result card has a hidden text area for confirmed level changes', () => {
  const ui = UIBuilder.read('ui/BattleGroup.ui');
  const path = 'BattleResultPanel/CardTemplate/Progression';
  assert.equal(ui.find(path)?.jsonString.enable, false);
  const label = ui.getComponent(path, 'MOD.Core.TextGUIRendererComponent');
  assert.ok(label, 'progression uses the existing card rather than a new screen');
  assert.equal(label.IsRichText, false);
  assert.equal(ui.getComponent(path, 'MOD.Core.ButtonComponent'), null);
});
