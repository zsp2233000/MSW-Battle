const assert = require('node:assert/strict');
const test = require('node:test');
const { UIBuilder } = require('../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');

const ROW = 'BattleResultPanel/RowTemplate';
const ROW_CHILDREN = [
  'PortraitFrame/Portrait',
  'MonsterName',
  'Level',
  'BarBack/BarFill',
  'ProgressText',
  'StatsText',
  'LevelUpEffect/Motion/FrameTemplate',
];

test('the result list row template is hidden and has every part of one row', () => {
  const ui = UIBuilder.read('ui/BattleGroup.ui');
  assert.ok(ui.find(ROW), 'row template exists');
  assert.equal(ui.find(ROW).jsonString.enable, false);
  for (const child of ROW_CHILDREN) assert.ok(ui.find(`${ROW}/${child}`), child);
  assert.equal(ui.find('BattleResultPanel/CardTemplate'), null, 'the card template is retired');
});

test('the row template is 580x84 with a 480x8 progress bar and no interaction', () => {
  const ui = UIBuilder.read('ui/BattleGroup.ui');
  const size = path => ui.getComponent(path, 'MOD.Core.UITransformComponent').RectSize;
  assert.deepEqual([size(ROW).x, size(ROW).y], [580, 84]);
  assert.deepEqual([size(`${ROW}/PortraitFrame`).x, size(`${ROW}/PortraitFrame`).y], [72, 72]);
  assert.deepEqual([size(`${ROW}/PortraitFrame/Portrait`).x, size(`${ROW}/PortraitFrame/Portrait`).y], [64, 64]);
  assert.deepEqual([size(`${ROW}/BarBack`).x, size(`${ROW}/BarBack`).y], [480, 8]);
  for (const entity of ui.listEntities().filter(e => e.path.includes('/RowTemplate'))) {
    assert.equal(ui.getComponent(entity.path, 'MOD.Core.ButtonComponent'), null, entity.path);
    const sprite = ui.getComponent(entity.path, 'MOD.Core.SpriteGUIRendererComponent');
    if (sprite) assert.equal(sprite.RaycastTarget, false, entity.path);
  }
});

test('the portrait keeps its aspect ratio and the bar fill grows from the left edge', () => {
  const ui = UIBuilder.read('ui/BattleGroup.ui');
  const portrait = ui.getComponent(`${ROW}/PortraitFrame/Portrait`, 'MOD.Core.SpriteGUIRendererComponent');
  assert.equal(portrait.PreserveSprite, 1);
  const fill = ui.getComponent(`${ROW}/BarBack/BarFill`, 'MOD.Core.UITransformComponent');
  assert.equal(fill.Pivot.x, 0);
  assert.equal(fill.AnchorsMin.x, 0);
  assert.equal(fill.AnchorsMax.x, 0);
  assert.equal(ui.getComponent(`${ROW}/BarBack/BarFill`, 'MOD.Core.SpriteGUIRendererComponent').Type, 1);
});

test('row texts shrink to fit and the name ends with an ellipsis', () => {
  const ui = UIBuilder.read('ui/BattleGroup.ui');
  const text = child => ui.getComponent(`${ROW}/${child}`, 'MOD.Core.TextGUIRendererComponent');
  assert.equal(text('MonsterName').Overflow, 1, 'ellipsis');
  assert.equal(text('ProgressText').BestFit, true);
  assert.equal(text('StatsText').BestFit, true);
  assert.equal(text('Level').IsRichText, false);
});

test('the level-up effect sits over the portrait and does not hide row content', () => {
  const ui = UIBuilder.read('ui/BattleGroup.ui');
  const effect = ui.find(`${ROW}/LevelUpEffect`);
  assert.equal(effect.jsonString.enable, false);
  const portrait = ui.getComponent(`${ROW}/PortraitFrame`, 'MOD.Core.UITransformComponent').anchoredPosition;
  const origin = ui.getComponent(`${ROW}/LevelUpEffect`, 'MOD.Core.UITransformComponent').anchoredPosition;
  assert.ok(Math.abs(origin.x - portrait.x) <= 40, 'effect is horizontally on the portrait');
});
