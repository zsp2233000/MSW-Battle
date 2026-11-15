const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const { UIBuilder } = require('../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');

const root = path.join(__dirname, '..');
const read = p => fs.readFileSync(path.join(root, p), 'utf8');
const DEX_UI = 'ui/MonsterDexGroup.ui';
const MODULE = 'RootDesk/MyDesk/Dex/MonsterDex.mlua';
const RIGHT = 'Book/Page/RightPage';
const DETAILS = `${RIGHT}/Details`;
const HEADER = `${DETAILS}/DetailHeaderTemplate`;
const ROW = `${DETAILS}/DetailRowTemplate`;

const SPRITE = 'MOD.Core.SpriteGUIRendererComponent';
const TEXT = 'MOD.Core.TextGUIRendererComponent';
const SCROLL = 'MOD.Core.ScrollLayoutGroupComponent';
const UI_TRANSFORM = 'MOD.Core.UITransformComponent';

// The five action groups in reading order, each followed by its resource rows (and, for the attack, its timing rows).
// Written out here on purpose: the contract is "this exact fixed set of rows", not "whatever the module builds".
const GROUPS = [
  { group: 'idle', header: '待機', rows: [['stand', '待機動畫']] },
  { group: 'move', header: '移動', rows: [['move', '移動動畫']] },
  { group: 'attack', header: '攻擊', rows: [['attackAnimation', '攻擊動畫'], ['attackEffect', '出手特效'], ['hitEffect', '命中特效'],
    ['projectile', '投射物'], ['attackSound', '出手音效'], ['attackEffectFrame', '出手特效影格'], ['hitFrame', '命中影格'],
    ['attackDuration', '攻擊動畫長度'], ['projectileSpeed', '投射物速度']] },
  { group: 'hurt', header: '受傷', rows: [['hurtAnimation', '受傷動畫'], ['hurtSound', '受傷音效']] },
  { group: 'die', header: '死亡', rows: [['dieAnimation', '死亡動畫'], ['dieSound', '死亡音效']] },
];
const ROW_COUNT = GROUPS.reduce((sum, g) => sum + 1 + g.rows.length, 0);
const VALUE_ROW_COUNT = GROUPS.reduce((sum, g) => sum + g.rows.length, 0);

const dex = () => UIBuilder.read(DEX_UI);
const rect = (ui, entity) => ui.getComponent(entity, UI_TRANSFORM);
// Direct children by sibling order.
const childNames = (ui, parentPath) => ui.listEntities()
  .filter(e => e.path.startsWith(`/ui/MonsterDexGroup/${parentPath}/`) && e.path.slice(`/ui/MonsterDexGroup/${parentPath}/`.length).indexOf('/') < 0)
  .map(e => ({ name: e.path.split('/').pop(), order: ui.find(e.path).jsonString.displayOrder }))
  .sort((a, b) => a.order - b.order)
  .map(e => e.name);

function methodBody(source, name) {
  const match = source.match(new RegExp(`method [\\w<>, ]+ ${name}\\([^)]*\\)([\\s\\S]*?)\\n    end\\b`));
  assert.ok(match, `${name} must exist`);
  return match[1];
}

test('the lower right page holds a vertically scrollable detail list, the top is left free for the stage', () => {
  const ui = dex();
  const layout = ui.getComponent(DETAILS, SCROLL);
  assert.equal(layout.Type, 1, 'vertical list');
  assert.equal(layout.UseScroll, true);
  assert.equal(layout.VerticalScrollBarDirection, 2, 'BottomToTop keeps the handle in step with the content');
  const page = rect(ui, RIGHT);
  const list = rect(ui, DETAILS);
  assert.ok(list.RectSize.x <= page.RectSize.x, 'the list fits the page width');
  assert.ok(-list.anchoredPosition.y >= page.RectSize.y * 0.45, 'the list starts in the lower half so the stage keeps the top');
  assert.ok(-list.anchoredPosition.y + list.RectSize.y <= page.RectSize.y, 'the list ends inside the page');
  assert.equal(ui.getComponent(`${RIGHT}/DetailTitle`, TEXT).Text, '表現資源');
  assert.ok(-rect(ui, `${RIGHT}/DetailTitle`).anchoredPosition.y < -list.anchoredPosition.y, 'the title sits above the list');
});

test('the right page holds only the stage, the details title and the details', () => {
  assert.deepEqual(childNames(dex(), RIGHT).sort(), ['DetailTitle', 'Details', 'Stage']);
});

test('the list is authored as two hidden templates; the rows are cloned at runtime so the list measures and scrolls', () => {
  const ui = dex();
  assert.deepEqual(childNames(ui, DETAILS), ['DetailHeaderTemplate', 'DetailRowTemplate']);
  assert.equal(ui.find(HEADER).jsonString.enable, false, 'header template is hidden');
  assert.equal(ui.find(ROW).jsonString.enable, false, 'row template is hidden');
  assert.deepEqual(childNames(ui, ROW).sort(), ['Label', 'Value'], 'a row is a label plus a value text');
  assert.ok(ui.getComponent(HEADER, TEXT), 'a header carries its own text');
});

test('RUID values use a small font that fits a full 32 character RUID, labels are larger', () => {
  const ui = dex();
  const value = ui.getComponent(`${ROW}/Value`, TEXT);
  const label = ui.getComponent(`${ROW}/Label`, TEXT);
  assert.ok(value.FontSize <= 18, 'the value is small');
  assert.ok(label.FontSize >= value.FontSize, 'the label is not smaller than its value');
  // A conservative 0.6 em per hex digit must still fit inside the value rect.
  assert.ok(32 * value.FontSize * 0.6 <= rect(ui, `${ROW}/Value`).RectSize.x, 'the value rect holds 32 characters');
});

test('the fixed rows overflow the list, so it scrolls, and each row is a wheel-scroll hit target', () => {
  const ui = dex();
  const header = rect(ui, HEADER);
  const row = rect(ui, ROW);
  const list = rect(ui, DETAILS);
  const content = GROUPS.length * header.RectSize.y + VALUE_ROW_COUNT * row.RectSize.y;
  assert.ok(content > list.RectSize.y, `content ${content} overflows the view ${list.RectSize.y}`);
  for (const template of [HEADER, ROW]) {
    assert.equal(ui.getComponent(template, SPRITE).RaycastTarget, true, `${template} takes pointer hits`);
    assert.ok(rect(ui, template).RectSize.x <= list.RectSize.x - 12, `${template} leaves room for the scroll bar`);
  }
});

test('the module declares exactly the five action groups and rows, in order, with their labels', () => {
  const body = methodBody(read(MODULE), 'DetailSpecs');
  const entries = [...body.matchAll(/\{\s*(group = "(\w+)", header = "([^"]+)"|key = "(\w+)", label = "([^"]+)")/g)]
    .map(m => (m[2] ? { group: m[2], header: m[3] } : { key: m[4], label: m[5] }));
  const expected = GROUPS.flatMap(g => [{ group: g.group, header: g.header }, ...g.rows.map(([key, label]) => ({ key, label }))]);
  assert.deepEqual(entries, expected);
  assert.equal(entries.length, ROW_COUNT);
});

test('MonsterDex binds the detail list and templates and exposes details in its snapshot', () => {
  const source = read(MODULE);
  const ui = dex();
  for (const [property, entity] of [['detailLayout', DETAILS], ['headerTemplate', HEADER], ['detailTemplate', ROW]]) {
    const declared = source.match(new RegExp(`property \\w+ ${property} = "([^"]*)"`));
    assert.ok(declared, `${property} is declared`);
    assert.equal(declared[1], ui.getId(entity), `${property} -> ${entity}`);
  }
  assert.match(methodBody(source, 'GetSnapshot'), /\bdetails\b/, 'the snapshot carries the detail rows');
});

test('blank optional resources, an effect frame without an effect and a speed without a projectile read 未設定', () => {
  const source = read(MODULE);
  assert.match(source, /property string UnsetText = "未設定"/);
  const format = methodBody(source, 'DetailText') + methodBody(source, 'BuildDetails');
  assert.match(format, /UnsetText/);
  assert.match(format, /projectileRuid/, 'projectile speed depends on the projectile');
  assert.match(format, /attackEffectRuid/, 'effect frame depends on the effect');
});

test('rows are cloned when the server reply arrives, filled from the selected row, and destroyed with the module', () => {
  const source = read(MODULE);
  assert.match(methodBody(source, 'Observe'), /self:BuildDetailRows\(\)/);
  const build = methodBody(source, 'BuildDetailRows');
  assert.match(build, /headerTemplate:Clone\("Header_" \.\. spec\.group\)/);
  assert.match(build, /detailTemplate:Clone\("Detail_" \.\. spec\.key\)/);
  assert.match(methodBody(source, 'OnEndPlay'), /self:DestroyDetailRows\(\)/);
  assert.match(methodBody(source, 'RenderDetails'), /BuildDetails\(self:GetSelectedRow\(\)\)/);
  assert.match(methodBody(source, 'Render'), /self:RenderDetails\(\)/, 'selecting, opening and new replies all render');
});

test('the book never reads the table or the catalog itself and formatting is pure', () => {
  const source = read(MODULE);
  assert.doesNotMatch(source, /GetCatalog|MonsterData|_FormationService/);
  assert.doesNotMatch(methodBody(source, 'BuildDetails'), /_\w+Service|_Data|DataStorage/);
});

test('sibling order numbers inside the detail area are real sibling indexes (an out-of-range index made Maker drop the children)', () => {
  const ui = dex();
  for (const parent of [RIGHT, DETAILS, ROW]) {
    const names = childNames(ui, parent);
    const orders = names.map(name => ui.find(`${parent}/${name}`).jsonString.displayOrder);
    assert.deepEqual(orders, names.map((_, index) => index), `${parent} children are numbered 0..n-1`);
  }
});
