const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');
const { UIBuilder } = require('../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');

// #132: the faction-war world map opens nearly full screen. The behaviour on the real screen is proven by tests/faction_war_map_fullscreen_runtime_probe.lua in
// Maker; these tests pin what the authored file can say. Every rectangle is worked out from the authored anchors, pivots, sizes and scales the way the engine lays
// them out, and compared with the ticket's own numbers (40 px around the window, the map as tall as the window, a base scale of about 1.2), not with the builder's.
const source = path => fs.readFileSync(path, 'utf8').replace(/\r\n/g, '\n');
const body = (text, name) => text.match(new RegExp(`(?:method \\w+|handler) ${name}\\([^]*?(?=\\n    @|\\n    method|\\n    handler|\\nend)`))?.[0] || '';
const annotation = (text, name) => text.match(new RegExp(`((?:    @[^\\n]+\\n)+)    (?:method \\w+|handler) ${name}\\(`))?.[1] || '';
const ui = () => UIBuilder.read('ui/WorldMapGroup.ui');
const transform = 'MOD.Core.UITransformComponent';
const sprite = 'MOD.Core.SpriteGUIRendererComponent';
const button = 'MOD.Core.ButtonComponent';
const text = 'MOD.Core.TextGUIRendererComponent';
const TOWNS = ['nanzih', 'zuoying', 'gushan', 'yancheng'];
const CANVAS = { minX: -960, minY: -540, maxX: 960, maxY: 540, scale: 1 };
// The Cardgame palette (msw-ui-kit, Maple Duel): Base_4 (the hollow frame the dialogs use), the XButton and CardButton states, the HP gauge slice.
const CARDGAME = {
  frame: 'ac319875b43f40ea86a069c468a1a26e',
  close: { normal: 'e01ef74a1ecf444bbb013c4313a8d0a9', highlighted: 'f24a6333e4df404795e922ec2966e997', pressed: '5952570d481245a9a4fbe562f3c030c5' },
  card: { normal: '9505617fb63c447c8ff9c15c18d88064', highlighted: '398dfdb46d534ea2a2373e4f5d29ae2a', pressed: '1016088c7aca43c78cdd06c01645ab1b' },
  gauge: 'f0911af597259044aa624a11332c0595',
};
// The engine draws its own buttons over the top-right corner of every screen (ui-fundamentals.md §9.3): friends and menu, about 220 x 130.
const SYSTEM_BUTTONS = { minX: 960 - 220, minY: 540 - 130 };
const SIDE = 'Overlay/Window/Side';
const VIEW = 'Overlay/Window/Map';

// The viewport is drawn at BaseScale: FactionWarMapUI sets it when the map opens, because Maker's import ignores a UIScale written in the file (Maker run of #132).
const client = () => source('RootDesk/MyDesk/Formations/FactionWarMapUI.mlua');
const baseScale = () => Number(client().match(/property number BaseScale = ([\d.]+)/)[1]);

// The rectangle a node covers on the 1920 x 1080 canvas: a fixed anchor puts the pivot at the anchor point plus the offset, the size is scaled about the pivot, a
// stretch anchor fills its parent between the offsets. `scale` is what a child's own units are worth on the canvas.
function worldRect(file, path) {
  const parts = path.split('/');
  const parent = parts.length === 1 ? CANVAS : worldRect(file, parts.slice(0, -1).join('/'));
  const t = file.getComponent(path, transform);
  const width = parent.maxX - parent.minX;
  const height = parent.maxY - parent.minY;
  const own = path === VIEW ? baseScale() : t.UIScale.x;
  if (t.AnchorsMin.x !== t.AnchorsMax.x || t.AnchorsMin.y !== t.AnchorsMax.y) {
    return {
      minX: parent.minX + t.AnchorsMin.x * width + t.OffsetMin.x * parent.scale, minY: parent.minY + t.AnchorsMin.y * height + t.OffsetMin.y * parent.scale,
      maxX: parent.minX + t.AnchorsMax.x * width + t.OffsetMax.x * parent.scale, maxY: parent.minY + t.AnchorsMax.y * height + t.OffsetMax.y * parent.scale,
      scale: parent.scale * own,
    };
  }
  const sizeX = t.RectSize.x * parent.scale * own;
  const sizeY = t.RectSize.y * parent.scale * own;
  const minX = parent.minX + t.AnchorsMin.x * width + t.anchoredPosition.x * parent.scale - t.Pivot.x * sizeX;
  const minY = parent.minY + t.AnchorsMin.y * height + t.anchoredPosition.y * parent.scale - t.Pivot.y * sizeY;
  return { minX, minY, maxX: minX + sizeX, maxY: minY + sizeY, scale: parent.scale * own };
}
const centre = rect => ({ x: (rect.minX + rect.maxX) / 2, y: (rect.minY + rect.maxY) / 2 });
const near = (actual, expected, message, tolerance = 0.5) => assert.ok(Math.abs(actual - expected) <= tolerance, `${message}: ${actual} is not ${expected}`);
const inside = (inner, outer, tolerance = 0.5) => inner.minX >= outer.minX - tolerance && inner.maxX <= outer.maxX + tolerance && inner.minY >= outer.minY - tolerance && inner.maxY <= outer.maxY + tolerance;
const overlaps = (a, b) => a.minX < b.maxX && a.maxX > b.minX && a.minY < b.maxY && a.maxY > b.minY;
const order = file => file.build().ContentProto.Entities.map(entity => entity.path.replace('/ui/WorldMapGroup/', ''));
const sibling = (file, path) => file.find(path).jsonString.displayOrder;
const descendants = (file, root) => file.listEntities().map(node => node.path.replace('/ui/WorldMapGroup/', '')).filter(path => path.startsWith(`${root}/`));

test('an opaque deep-brown mask covers the whole screen, the town HUD and the siege panel included', () => {
  const file = ui();
  const mask = worldRect(file, 'Overlay');
  assert.deepEqual([mask.minX, mask.minY, mask.maxX, mask.maxY], [-960, -540, 960, 540], 'the mask is the whole 1920 x 1080 canvas');
  const paint = file.getComponent('Overlay', sprite);
  assert.equal(paint.Color.a, 1, 'nothing of the town shows through');
  assert.ok(paint.Color.r > paint.Color.g && paint.Color.g > paint.Color.b && paint.Color.r < 0.25, `a deep brown: ${JSON.stringify(paint.Color)}`);
  assert.equal(paint.RaycastTarget, true, 'it takes every click, so nothing in the town can be pressed through it');
  assert.equal(file.find('Overlay').jsonString.enable, false, 'the map still starts closed');
  assert.equal(file.find('Overlay/Backdrop'), null, 'the mask is its own backing: no second layer under the window');
  const group = name => UIBuilder.read(`ui/${name}.ui`).getComponent(`/ui/${name}`, 'MOD.Core.UIGroupComponent').GroupOrder;
  for (const below of ['FactionWarGroup', 'MatchGroup', 'FormationGroup', 'BattleGroup', 'MonsterDexGroup', 'GMPanelGroup']) {
    assert.ok(group('WorldMapGroup') > group(below), `the map's group is drawn above ${below}`);
  }
  assert.ok(UIBuilder.read('ui/FactionWarGroup.ui').find('SiegePanel'), 'the siege panel is in the group that the mask covers');
  const paths = order(file);
  assert.ok(paths.indexOf('OpenButton') < paths.indexOf('Overlay'), 'and the entry button is under the mask too');
});

test('the window leaves 40 px on every side of the screen and is centred', () => {
  const file = ui();
  const window = worldRect(file, 'Overlay/Window');
  for (const [side, margin] of [['left', window.minX + 960], ['right', 960 - window.maxX], ['bottom', window.minY + 540], ['top', 540 - window.maxY]]) {
    near(margin, 40, `${side} margin`, 4);
  }
  assert.equal(file.getComponent('Overlay/Window', sprite).ImageRUID.DataId, CARDGAME.frame, 'the Cardgame Base_4 frame, as the dialogs');
  assert.equal(file.getComponent('Overlay/Window', sprite).FillCenter, false, 'only its border is drawn: the mask shows through the middle');
  assert.equal(file.getComponent('Overlay/Window', sprite).RaycastTarget, true, 'and it takes the clicks that are not for a control');
});

test('the map at 1x fits the height of the window, is centred, and is drawn at the base scale of about 1.2 without being painted again', () => {
  const file = ui();
  const window = worldRect(file, 'Overlay/Window');
  const view = worldRect(file, VIEW);
  const content = worldRect(file, `${VIEW}/Content`);
  const scale = { x: baseScale(), y: baseScale() };
  assert.ok(file.hasComponent(VIEW, 'MOD.Core.MaskComponent'), 'the viewport clips the map');
  assert.ok(scale.x >= 1.15 && scale.x <= 1.25, `the base scale is about 1.2: ${scale.x}`);
  assert.equal(scale.x, require('../assets/worldmap/fullscreen_ui.cjs').BASE_SCALE, 'the script and the layout module agree on it');
  assert.deepEqual(file.getComponent(VIEW, transform).UIScale, { x: 1, y: 1, z: 1 }, 'the file holds no scale of its own (the import would ignore it, and it would be a second source of the number)');
  assert.match(body(client(), 'Reveal'), /self:ApplyBaseScale\(\)\s+self:SetMapView\(1, Vector2\(0, 0\)\)/, 'the map sets the scale when it opens, before the first view');
  assert.match(body(client(), 'ApplyBaseScale'), /view\.UITransformComponent\.UIScale = Vector3\(self\.BaseScale, self\.BaseScale, 1\)/, 'on the viewport');
  const layout = JSON.parse(source('assets/worldmap/layout.json'));
  assert.deepEqual(file.getComponent(`${VIEW}/Content`, transform).RectSize, { x: layout.size.w, y: layout.size.h }, 'the map keeps the size it was painted at');
  const height = content.maxY - content.minY;
  assert.ok(height / (window.maxY - window.minY) >= 0.95 && height <= window.maxY - window.minY, `the map is as tall as the window: ${height} of ${window.maxY - window.minY}`);
  near(centre(content).x, centre(window).x, 'the map is centred horizontally', 1);
  near(centre(content).y, centre(window).y, 'and vertically', 1);
  assert.ok(inside(content, view), 'the whole map is inside the viewport at 1x (the full overview)');
  assert.ok(inside(view, window), 'the viewport is inside the window');
  assert.ok((view.maxX - view.minX) / (window.maxX - window.minX) >= 0.95 && (view.maxY - view.minY) / (window.maxY - window.minY) >= 0.95, 'and fills it, so a zoomed map can slide under the panel and the corner controls');
  assert.deepEqual(file.getComponent(`${VIEW}/Content/Terrain`, transform).RectSize, file.getComponent(`${VIEW}/Content`, transform).RectSize, 'the terrain still fills the map');
  assert.deepEqual(file.getComponent(`${VIEW}/Input`, transform).RectSize, file.getComponent(VIEW, transform).RectSize, 'and the touch surface fills the whole viewport, not only the map');
  assert.ok(file.hasComponent(`${VIEW}/Input`, 'MOD.Core.UITouchReceiveComponent'), 'the drag is still read there');
});

test('the town list is a translucent floating panel: in the empty space right of the map at 1x, over the map when zoomed, and it takes the drag', () => {
  const file = ui();
  const window = worldRect(file, 'Overlay/Window');
  const view = worldRect(file, VIEW);
  const content = worldRect(file, `${VIEW}/Content`);
  const side = worldRect(file, SIDE);
  const paint = file.getComponent(SIDE, sprite);
  assert.ok(paint.Color.a > 0.3 && paint.Color.a < 0.95, `translucent: alpha ${paint.Color.a}`);
  assert.equal(paint.RaycastTarget, true, 'it takes a touch that lands on it, so a drag cannot pass through to the map under it');
  assert.ok(side.minX >= content.maxX + 8, `at 1x it does not cover the map: the panel starts at ${side.minX}, the map ends at ${content.maxX}`);
  assert.ok(inside(side, window) && inside(side, view), 'it floats inside the window and inside the viewport, so a zoomed map goes under it');
  assert.ok(side.maxY <= SYSTEM_BUTTONS.minY, 'and stays below the engine buttons in the top-right corner');
  const paths = order(file);
  assert.ok(sibling(file, SIDE) > sibling(file, VIEW) && paths.indexOf(SIDE) > paths.indexOf(`${VIEW}/Input`), 'drawn after the map (displayOrder and file order), so above it');
  for (const path of descendants(file, SIDE)) {
    if (!file.hasComponent(path, transform)) continue;
    assert.ok(inside(worldRect(file, path), side, 1), `${path} stays inside the panel`);
  }
  for (const id of TOWNS) {
    const row = `${SIDE}/Rows/${id}`;
    const size = file.getComponent(row, transform).RectSize;
    for (const part of ['Pick', 'Dim']) assert.equal(file.getComponent(`${row}/${part}`, transform).RectSize.x, size.x, `${id}/${part} covers the whole row`);
    assert.equal(file.getComponent(`${row}/Bar`, transform).RectSize.x, file.getComponent(`${row}/Bar/Fill`, transform).RectSize.x, `${id}: the fill starts as wide as its bar`);
    assert.equal(file.getComponent(`${row}/Bar/Fill`, sprite).ImageRUID.DataId, CARDGAME.gauge, `${id}: the Cardgame gauge slice`);
  }
  const barWidth = Number(source('RootDesk/MyDesk/Formations/FactionWarMapUI.mlua').match(/property number BarWidth = (\d+)/)[1]);
  assert.equal(file.getComponent(`${SIDE}/Rows/zuoying/Bar`, transform).RectSize.x, barWidth, 'FactionWarMapUI draws the fill as a share of the authored bar');
  const rows = worldRect(file, `${SIDE}/Rows`);
  for (const part of ['Legend', 'Note', 'Notice', 'Status']) assert.ok(worldRect(file, `${SIDE}/${part}`).maxY <= rows.minY || worldRect(file, `${SIDE}/${part}`).minY >= rows.maxY, `${part} does not sit on the rows`);
});

test('the title, the close button and the hints are fixed to the four corners, above the map and clear of the engine buttons', () => {
  const file = ui();
  const window = worldRect(file, 'Overlay/Window');
  const middle = centre(window);
  const corners = { Title: [-1, 1], Close: [1, 1], MapHint: [-1, -1], Hint: [1, -1] };
  const alignment = { Title: 4, Close: 5, MapHint: 7, Hint: 8 };
  const paths = order(file);
  for (const [name, [sx, sy]] of Object.entries(corners)) {
    const path = `Overlay/Window/${name}`;
    assert.ok(file.find(path), `${name} exists`);
    assert.equal(file.getComponent(path, transform).AlignmentOption, alignment[name], `${name} is anchored to its corner`);
    const rect = worldRect(file, path);
    assert.ok(Math.sign(centre(rect).x - middle.x) === sx && Math.sign(centre(rect).y - middle.y) === sy, `${name} is in its own corner of the window`);
    assert.ok(Math.abs(centre(rect).x - middle.x) > 0.25 * (window.maxX - window.minX) && Math.abs(centre(rect).y - middle.y) > 0.4 * (window.maxY - window.minY), `${name} is out at the corner, not near the middle`);
    assert.ok(inside(rect, window), `${name} is inside the window`);
    assert.ok(paths.indexOf(path) > paths.indexOf(`${VIEW}/Input`) && sibling(file, path) > sibling(file, VIEW), `${name} is drawn above the map`);
  }
  const close = worldRect(file, 'Overlay/Window/Close');
  assert.ok(close.maxX - close.minX >= 88 && close.maxY - close.minY >= 88, 'the close button is a full touch target');
  assert.ok(!(close.maxX > SYSTEM_BUTTONS.minX && close.maxY > SYSTEM_BUTTONS.minY), 'and does not sit under the engine buttons that would take its clicks');
  assert.ok(file.hasComponent('Overlay/Window/Close', button), 'it is still a button');
  for (const part of ['Title', 'MapHint', 'Hint']) assert.ok(!overlaps(worldRect(file, `Overlay/Window/${part}`), worldRect(file, SIDE)), `${part} does not sit on the town list`);
  for (const name of ['Title', 'MapHint', 'Hint']) {
    const plate = file.getComponent(`Overlay/Window/${name}`, sprite);
    assert.ok(plate.Color.a > 0.3 && plate.Color.a < 0.9 && plate.Color.r < 0.2, `${name} has a dark translucent plate, so it reads over the zoomed map`);
    assert.ok(plate.ImageRUID.DataId, `${name}'s plate has a sprite`);
    assert.equal(plate.RaycastTarget, false, `and takes no click: a drag that starts on it is the map's`);
  }
  assert.equal(file.getComponent('Overlay/Window/Title', text).Text, '國戰大地圖');
  assert.equal(file.getComponent('Overlay/Window/MapHint', text).Text, '高雄 38 區｜滾輪縮放・拖曳移動', 'the operation hint is unchanged');
  assert.match(file.getComponent('Overlay/Window/Hint', text).Text, /M 鍵/, 'and so is the hint about how to close');
});

test('the Cardgame parts of the window are the palette parts, and the close button keeps its three states', () => {
  const file = ui();
  const close = file.getComponent('Overlay/Window/Close', button).ImageRUIDs;
  assert.equal(file.getComponent('Overlay/Window/Close', sprite).ImageRUID.DataId, CARDGAME.close.normal);
  assert.equal(close.HighlightedSprite.DataId, CARDGAME.close.highlighted);
  assert.equal(close.PressedSprite.DataId, CARDGAME.close.pressed);
  assert.equal(file.getComponent('OpenButton', sprite).ImageRUID.DataId, CARDGAME.card.normal, 'the entry button is unchanged');
  for (const id of TOWNS) assert.equal(file.getComponent(`${SIDE}/Rows/${id}/Pick`, sprite).ImageRUID.DataId, CARDGAME.card.normal, `${id} pick button`);
});

test('the confirmation window and the message window stay on top of the whole map window', () => {
  const file = ui();
  const paths = order(file);
  const lastOfMap = Math.max(...paths.map((path, index) => (path === 'Overlay' || path.startsWith('Overlay/') ? index : -1)));
  assert.ok(paths.indexOf('Confirm') > lastOfMap, 'the confirmation window comes after every node of the map window in the file');
  assert.ok(paths.indexOf('Message') > paths.indexOf('Confirm'), 'and the message window after it');
  assert.ok(sibling(file, 'Confirm') > sibling(file, 'Overlay') && sibling(file, 'Message') > sibling(file, 'Confirm'), 'and in display order');
  for (const name of ['Confirm', 'Message']) {
    const cover = worldRect(file, name);
    assert.deepEqual([cover.minX, cover.minY, cover.maxX, cover.maxY], [-960, -540, 960, 540], `${name} still dims the whole screen`);
    assert.equal(file.getComponent(name, sprite).RaycastTarget, true, `${name} takes every click`);
  }
  assert.ok(paths.indexOf('Overlay/Window/Side/Notice') < paths.indexOf('Confirm'), 'and the side panel line is still under them');
});

test('the layout comes from one module: the full build and the delta build use it, and the delta keeps the entities of the file', () => {
  const layout = source('assets/worldmap/fullscreen_ui.cjs');
  assert.match(layout, /function applyFullscreenLayout\(b\)/, 'one function lays an existing file out');
  assert.match(source('assets/worldmap/build_fullscreen_ui.cjs'), /UIBuilder\.load\(uiFile\)[^]*applyFullscreenLayout\(b\)[^]*b\.write\(uiFile/, 'the delta script loads the file (Maker keeps the entities), lays it out and writes');
  assert.match(source('assets/worldmap/build_ui.cjs'), /require\('\.\/fullscreen_ui\.cjs'\)/, 'the full build uses the same module');
  assert.doesNotMatch(source('assets/worldmap/build_ui.cjs'), /Overlay\/Backdrop/, 'and no longer makes the backdrop');
});

test('the wheel over the town list is the list\'s, and the reach of a click is measured in the units of the scaled viewport', () => {
  const text = client();
  const file = ui();
  assert.match(annotation(text, 'IsOverTownList'), /@ExecSpace\("ClientOnly"\)/, 'the check runs on the client');
  assert.match(body(text, 'HandleWheel'), /if self:IsOverTownList\(screenPoint\) then return end\s+local cursor = _UILogic:ScreenToLocalUIPosition\(screenPoint, view\.UITransformComponent\)\s+self:ZoomMapAt/, 'the wheel is ignored on the list before it can zoom');
  assert.equal(text.match(/property string TownListPath = "([^"]+)"/)[1], SIDE, 'the list is the node the layout floats');
  assert.ok(file.find(SIDE), 'and it exists');
  assert.match(body(text, 'IsOverTownList'), /transform\.Pivot[^]*-size\.x \* pivot\.x[^]*size\.x \* \(1 - pivot\.x\)/, 'a point is on it inside its rectangle, measured from the pivot the conversion uses');
  assert.match(body(text, 'ScreenPixelsPerUnit'), /view\.UITransformComponent\.UIScale[^]*screenWidth \/ span \* scale/, 'a unit of the viewport is the screen pixels of a canvas unit times its scale');
  assert.match(body(text, 'ClickMap'), /self:HitRadius\(self\._T\.zoom, self:ScreenPixelsPerUnit\(\)\)/, 'the click reach uses it');
});

test('the #132 Maker client probe implements every step its header orders, measures on the screen, and the README, the ADR and the glossary say what the layout is', () => {
  const probe = source('tests/faction_war_map_fullscreen_runtime_probe.lua');
  const readme = source('tests/README.md');
  const order = probe.match(/^-- Order [^\n]*\n((?:--[^\n]*\n)+?)-- Regression/m)[1];
  const header = [...order.matchAll(/(?<![#\d])\b(\d{1,2}) ([A-Z_]{4,})/g)].map(match => [Number(match[1]), match[2]]);
  assert.deepEqual(header.map(step => step[0]), Array.from({ length: 8 }, (_, index) => index + 1), 'the header numbers 8 steps from 1 without gaps');
  const implemented = [...probe.matchAll(/(?:if|elseif) STEP == "([A-Z_]+)" then/g)].map(match => match[1]);
  for (const [, name] of header) {
    assert.ok(implemented.includes(name), `${name} is implemented`);
    assert.ok(probe.includes(`[VRF][MapFullscreen] ${name} PASS`), `${name} ends in a PASS line`);
    assert.ok(readme.includes(`\`${name}\``), `the README names ${name}`);
  }
  assert.equal(implemented.length, header.length, 'and nothing else is implemented');
  assert.match(probe, /_UILogic:ScreenToLocalUIPosition\(Vector2\(0, 0\), transform\)[^]*_UILogic:ScreenToLocalUIPosition\(Vector2\(100, 100\), transform\)/, 'every rectangle is measured on the screen from the real conversion');
  assert.match(probe, /UITouchDownEvent\(input, -1, p\)[^]*UITouchDragEvent[^]*UITouchUpEvent/, 'the drag is touch events on the real touch surface (maker_mouse_input does not reach it)');
  assert.match(probe, /STEP = "CLEANUP" in server_main LAST/, 'the header says to clean the isolated board up before stopping Play');
  assert.ok(readme.includes('## Near full-screen world map (#132, ADR 0015)') && readme.includes('faction_war_map_fullscreen_runtime_probe.lua') && readme.includes('docs/evidence/issue132/132-open.png'), 'the README has the section, the probe and the screenshots');
  for (const image of ['132-open', '132-zoom-cover', '132-select', '132-select-confirm', '132-message']) assert.ok(fs.existsSync(`docs/evidence/issue132/${image}.png`), `${image}.png is in the evidence folder`);
  const adr = source('docs/adr/0015-world-map-is-viewed-in-towns-and-pushed-by-settlement-events.md');
  for (const term of ['補記（#132）', 'BaseScale', 'IsOverTownList', 'fullscreen_ui.cjs']) assert.ok(adr.includes(term), `the ADR records ${term}`);
  const context = source('CONTEXT.md');
  assert.ok(context.includes('**城鎮列**:') && context.includes('不透明的遮罩') && context.includes('四個角落'), 'the glossary defines the town list and says how the world map opens');
});

test('a full rebuild gives the committed file, so the delta script and build_ui.cjs cannot drift apart', () => {
  const os = require('node:os');
  const path = require('node:path');
  const { execFileSync } = require('node:child_process');
  const out = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'worldmap-')), 'WorldMapGroup.ui');
  try {
    execFileSync(process.execPath, ['assets/worldmap/build_ui.cjs'], { env: { ...process.env, WORLDMAP_UI_OUT: out }, stdio: 'pipe' });
    const quiet = console.log;
    console.log = () => {};
    let built, committed;
    try { built = UIBuilder.read(out).build().ContentProto.Entities; committed = ui().build().ContentProto.Entities; } finally { console.log = quiet; }
    // Entity ids differ by design (a rebuild mints new ones) and so does the numbering of siblings after delta builds; everything else is the same.
    const plain = entity => JSON.stringify(entity.jsonString, (key, value) => (['id', 'Id', 'origin', 'revision', 'displayOrder'].includes(key) ? undefined : value));
    assert.deepEqual(built.map(entity => entity.path).sort(), committed.map(entity => entity.path).sort(), 'the same entities');
    const byPath = new Map(built.map(entity => [entity.path, entity]));
    for (const entity of committed) assert.equal(plain(entity), plain(byPath.get(entity.path)), `${entity.path} is the same in a full rebuild`);
    const siblings = list => list.map(entity => entity.path.replace('/ui/WorldMapGroup/', '')).filter(name => /^Overlay\/Window\/[^/]+$/.test(name));
    assert.deepEqual(siblings(committed), siblings(built), 'and the children of the window are in the same order');
  } finally {
    fs.rmSync(path.dirname(out), { recursive: true, force: true });
  }
});
