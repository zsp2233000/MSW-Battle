const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');
const { UIBuilder } = require('../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');

const panel = 'BattleResultPanel/WarResult';
const sprite = 'MOD.Core.SpriteGUIRendererComponent';
const text = 'MOD.Core.TextGUIRendererComponent';
const transform = 'MOD.Core.UITransformComponent';
const read = (path) => fs.readFileSync(path, 'utf8').replace(/\r\n/g, '\n');

test('the war block starts hidden, matches the Cardgame frame/brown surface, and has no click target', () => {
  const ui = UIBuilder.read('ui/BattleGroup.ui');
  assert.equal(ui.find(panel)?.jsonString.enable, false);
  const surface = ui.getComponent(panel, sprite);
  assert.equal(surface.ImageRUID.DataId, '2860136c06ab075439721c027de365af');
  assert.deepEqual(surface.Color, { r: 0.16, g: 0.11, b: 0.07, a: 0.88 });
  const frame = ui.getComponent(`${panel}/PackageFrame`, sprite);
  assert.equal(frame.ImageRUID.DataId, 'ac319875b43f40ea86a069c468a1a26e');
  assert.equal(frame.FillCenter, false);
  for (const node of ui.listEntities().filter(node => node.path.includes('/WarResult'))) {
    assert.equal(ui.getComponent(node.path, sprite).RaycastTarget, false);
  }
  const card = ui.getComponent(panel, transform);
  const window = ui.getComponent('BattleResultPanel/Window', transform);
  assert.ok(card.anchoredPosition.y - card.RectSize.y / 2 > window.anchoredPosition.y + window.RectSize.y / 2);
  assert.ok(card.RectSize.x / 2 <= 640 - 580 / 2, 'stays between the experience and survivor list columns');
  assert.ok(card.anchoredPosition.y + card.RectSize.y / 2 <= 540);
});

test('the result controller binds the war-only block and its rich-text labels by UUID', () => {
  const ui = UIBuilder.read('ui/BattleGroup.ui');
  const script = read('RootDesk/MyDesk/Combat/BattleUIController.mlua');
  for (const [prop, path] of Object.entries({ warResult: panel, warOrigin: `${panel}/Origin`, warTarget: `${panel}/Target`, warConclusion: `${panel}/Conclusion` })) {
    const id = ui.getId(path);
    assert.ok(id, path);
    assert.ok(script.includes(`property Entity ${prop} = "${id}"`), prop);
    if (prop !== 'warResult') assert.equal(ui.getComponent(path, text).IsRichText, true);
  }
  assert.equal(ui.getComponent(`${panel}/Title`, text).Text, '戰果');
  assert.match(script, /receipt\.matchId ~= session\.MatchKey or receipt\.profile ~= profile/);
  assert.match(script, /self:RenderWarResult\(session, map,/);
  assert.match(script, /GetFirstChildComponentByTypeName\("script\.MatchedBattle", true\)/);
  assert.match(script, /_FactionWarUI:HighlightedTownName\(/);
  const warUI = read('RootDesk/MyDesk/Formations/FactionWarUI.mlua');
  assert.match(warUI, /property string TownNameHighlightHex = "#4DFEE7"/);
});
