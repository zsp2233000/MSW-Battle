const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');
const { UIBuilder } = require('../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');

// One merged result panel: the war rows live inside the result window, the window grows upward by the
// war section's height when a war receipt is on screen, and the battle HUD steps aside for the result.
const window = 'BattleResultPanel/Window';
const war = `${window}/WarResult`;
const sprite = 'MOD.Core.SpriteGUIRendererComponent';
const text = 'MOD.Core.TextGUIRendererComponent';
const transform = 'MOD.Core.UITransformComponent';
const read = (path) => fs.readFileSync(path, 'utf8').replace(/\r\n/g, '\n');

const BASE_HEIGHT = 360;
const TOP_CENTER = 3;
const BOTTOM_CENTER = 6;
const CENTER = 0;
// Centres in window-centre coordinates (y up) in the plain, no-war window: what the lobby result always looked like.
const PLAIN = { Caption: 112, ResultWin: 34, ResultLose: 34, ResultDraw: 34, Divider: -25, PlayerStat: -85, EnemyStat: -85, TopAccent: 135.2292 };
const TOP_ANCHORED = ['Caption', 'ResultWin', 'ResultLose', 'ResultDraw', 'TopAccent'];
const BOTTOM_ANCHORED = ['Divider', 'PlayerStat', 'EnemyStat'];

const centreY = (ui, path, height) => {
  const t = ui.getComponent(path, transform);
  if (t.AlignmentOption === TOP_CENTER) return height / 2 + t.anchoredPosition.y;
  if (t.AlignmentOption === BOTTOM_CENTER) return -height / 2 + t.anchoredPosition.y;
  assert.equal(t.AlignmentOption, CENTER, `${path} uses a fixed anchor`);
  return t.anchoredPosition.y;
};
const extraHeight = () => Number(/property number WarExtraHeight = (\d+)/.exec(read('RootDesk/MyDesk/Combat/BattleUIController.mlua'))?.[1]);

test('the war rows are part of the result window, hidden by default, with no frame or click target of their own', () => {
  const ui = UIBuilder.read('ui/BattleGroup.ui');
  assert.equal(ui.find('BattleResultPanel/WarResult'), null, 'the separate card is gone');
  assert.equal(ui.find(war)?.jsonString.enable, false);
  assert.equal(ui.hasComponent(war, sprite), false, 'the window frame is the only frame');
  assert.deepEqual(ui.listEntities().filter(node => node.path.includes('/WarResult/')).map(node => node.path.split('/').pop()).sort(),
    ['Conclusion', 'Origin', 'Rule', 'Target', 'Title']);
  for (const node of ui.listEntities().filter(node => node.path.includes('/WarResult/'))) {
    if (ui.hasComponent(node.path, sprite)) assert.equal(ui.getComponent(node.path, sprite).RaycastTarget, false, node.path);
  }
  assert.equal(ui.getComponent(`${war}/Title`, text).Text, '戰果');
  assert.equal(ui.getComponent(`${war}/Rule`, sprite).ImageRUID.DataId, ui.getComponent(`${window}/Divider`, sprite).ImageRUID.DataId, 'same rule as the window divider');
});

test('the window keeps its plain look: top parts hang from the top edge, bottom parts stand on the bottom edge', () => {
  const ui = UIBuilder.read('ui/BattleGroup.ui');
  const frame = ui.getComponent(window, transform);
  assert.deepEqual([frame.RectSize.x, frame.RectSize.y, frame.anchoredPosition.y], [660, BASE_HEIGHT, 90]);
  for (const name of TOP_ANCHORED) assert.equal(ui.getComponent(`${window}/${name}`, transform).AlignmentOption, TOP_CENTER, name);
  for (const name of BOTTOM_ANCHORED) assert.equal(ui.getComponent(`${window}/${name}`, transform).AlignmentOption, BOTTOM_CENTER, name);
  for (const name of [...TOP_ANCHORED, ...BOTTOM_ANCHORED]) {
    assert.deepEqual(ui.getComponent(`${window}/${name}`, transform).Pivot, { x: 0.5, y: 0.5 }, `${name} is positioned by its centre`);
  }
  for (const [name, y] of Object.entries(PLAIN)) assert.ok(Math.abs(centreY(ui, `${window}/${name}`, BASE_HEIGHT) - y) < 0.001, `${name} stays at ${y}`);
});

test('growing the window by the war section keeps the stats put and fits the section between the result text and the divider', () => {
  const ui = UIBuilder.read('ui/BattleGroup.ui');
  const extra = extraHeight();
  assert.ok(extra > 0, 'WarExtraHeight is declared on the controller');
  const fromTop = (path, h) => h / 2 - centreY(ui, path, h);
  const size = (path) => ui.getComponent(path, transform).RectSize;
  const result = `${window}/ResultWin`;
  const description = ui.getComponent(`${result}/Description`, transform);
  const descriptionBottom = fromTop(result, BASE_HEIGHT) - description.anchoredPosition.y + description.RectSize.y / 2;
  const section = ui.getComponent(war, transform);
  assert.equal(section.AlignmentOption, TOP_CENTER, 'the section hangs from the window top like the other upper parts');
  assert.deepEqual(section.Pivot, { x: 0.5, y: 1 }, 'by its top edge, so shrinking it moves nothing above');
  const top = -section.anchoredPosition.y;
  const row = (name) => {
    const t = ui.getComponent(`${war}/${name}`, transform);
    assert.equal(t.AlignmentOption, TOP_CENTER, `${name} hangs from the section top`);
    assert.deepEqual(t.Pivot, { x: 0.5, y: 1 }, name);
    assert.ok(t.RectSize.x <= 560 && section.RectSize.x <= 560, `${name} stays inside the window interior`);
    return { top: -t.anchoredPosition.y, bottom: -t.anchoredPosition.y + t.RectSize.y };
  };
  const [rule, title, origin, target, conclusion] = ['Rule', 'Title', 'Origin', 'Target', 'Conclusion'].map(row);
  assert.ok(top >= descriptionBottom, `the section starts below the result text (${top} >= ${descriptionBottom})`);
  assert.ok(rule.top >= 0 && title.top >= rule.bottom && origin.top >= title.bottom && target.top >= origin.bottom && conclusion.top >= target.bottom, 'rows are stacked without overlap');
  assert.ok(conclusion.bottom <= section.RectSize.y, 'the last row stays inside the section');
  // Without strength rows (pending, failed, expired, capital) the conclusion takes the first row's place and the section is that much shorter.
  const shrink = conclusion.top - origin.top;
  assert.ok(shrink > 0 && origin.top + (conclusion.bottom - conclusion.top) <= section.RectSize.y - shrink, 'the conclusion fits the first row slot of the short section');
  for (const [mode, grow, sectionHeight] of [['rows', extra, section.RectSize.y], ['line', extra - shrink, section.RectSize.y - shrink]]) {
    const height = BASE_HEIGHT + grow;
    // Distances from the window's bottom and top edge do not change when the window grows upward.
    for (const name of BOTTOM_ANCHORED) assert.equal(height / 2 + centreY(ui, `${window}/${name}`, height), BASE_HEIGHT / 2 + centreY(ui, `${window}/${name}`, BASE_HEIGHT), `${mode} ${name}`);
    for (const name of TOP_ANCHORED) assert.equal(fromTop(`${window}/${name}`, height), fromTop(`${window}/${name}`, BASE_HEIGHT), `${mode} ${name}`);
    const dividerTop = fromTop(`${window}/Divider`, height) - size(`${window}/Divider`).y / 2;
    assert.ok(top + sectionHeight <= dividerTop, `${mode}: the section ends above the divider (${top + sectionHeight} <= ${dividerTop})`);
    // The grown window stays on the screen and keeps its bottom edge (the return panel hangs below it).
    const base = ui.getComponent(window, transform).anchoredPosition.y;
    const grownCentre = base + grow / 2;
    assert.equal(grownCentre - height / 2, base - BASE_HEIGHT / 2, `${mode}: bottom edge unchanged`);
    assert.ok(grownCentre + height / 2 <= 540 - 100, `${mode}: top edge clears the screen top`);
  }
});

test('the result controller binds the window and the war rows by UUID, resizes the window and hides the HUD for a result', () => {
  const ui = UIBuilder.read('ui/BattleGroup.ui');
  const script = read('RootDesk/MyDesk/Combat/BattleUIController.mlua');
  for (const [prop, path] of Object.entries({ resultWindow: window, warResult: war, warOrigin: `${war}/Origin`, warTarget: `${war}/Target`, warConclusion: `${war}/Conclusion` })) {
    const id = ui.getId(path);
    assert.ok(id, path);
    assert.ok(script.includes(`property Entity ${prop} = "${id}"`), prop);
    if (['warOrigin', 'warTarget', 'warConclusion'].includes(prop)) assert.equal(ui.getComponent(path, text).IsRichText, true);
  }
  assert.match(script, /receipt\.matchId ~= session\.MatchKey or receipt\.profile ~= profile/);
  assert.match(script, /self:RenderWarResult\(session, map,/);
  assert.match(script, /GetFirstChildComponentByTypeName\("script\.MatchedBattle", true\)/);
  assert.match(script, /_FactionWarTownDocument:StanceName\(town, stance\)/);
  assert.match(script, /_FactionWarTownDocument:ColoredConclusion\(receipt\.conclusion, receipt\)/);
  const layout = /method void SetWarLayout\(boolean grown, boolean rows\)([^]*?)\n\tend/.exec(script)?.[1] ?? '';
  assert.match(layout, /WarExtraHeight/, 'the window grows by the section height');
  assert.match(layout, /RectSize = Vector2\(base\.size\.x, base\.size\.y \+ extra\)/);
  assert.match(layout, /anchoredPosition = Vector2\(base\.x, base\.y \+ extra \/ 2\)/, 'and moves up so the bottom edge stays');
  const update = /method void OnUpdate\(number delta\)([^]*?)\n\tend/.exec(script)?.[1] ?? '';
  const result = update.indexOf('self:SetResult(viewerResult)');
  const hud = update.indexOf('self:SetEnabled(self.hud, phase ~= "CONFIG_ERROR" and self.OwnResult == "")');
  assert.ok(result > -1 && hud > result, 'the HUD is decided after the result, and only without a result window');
  const warUI = read('RootDesk/MyDesk/Formations/FactionWarUI.mlua');
  assert.match(warUI, /property string TownNameHighlightHex = "#4DFEE7"/);
});
