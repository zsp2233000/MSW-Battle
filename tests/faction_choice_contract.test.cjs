// #126 (ADR 0018): the faction choice screen has two colourless Cardgame buttons, "A 方" and "B 方", that look the same and are told apart by their
// text alone. The screen is built by assets/siege/build_faction_choice_ui.cjs; every path below is found by FactionWarUI.mlua.
// Run: node --test tests/faction_choice_contract.test.cjs
const assert = require('node:assert/strict');
const test = require('node:test');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { UIBuilder } = require('../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');

const read = file => readFileSync(join(__dirname, '..', file), 'utf8').replace(/\r\n/g, '\n');
const SPRITE = 'MOD.Core.SpriteGUIRendererComponent';
const BUTTON = 'MOD.Core.ButtonComponent';
const TEXT = 'MOD.Core.TextGUIRendererComponent';
// Cardgame theme parts, the same ones every other war screen uses (assets/siege/build_siege_ui.cjs).
const CARD_BUTTON = { normal: '9505617fb63c447c8ff9c15c18d88064', highlighted: '398dfdb46d534ea2a2373e4f5d29ae2a', pressed: '1016088c7aca43c78cdd06c01645ab1b' };
const BASE_FRAME = 'ac319875b43f40ea86a069c468a1a26e';
const DEFAULT_SKIN = '2860136c06ab075439721c027de365af';
const war = () => UIBuilder.read('ui/FactionWarGroup.ui');
const choiceNodes = ui => ui.listEntities().filter(entity => entity.path.includes('/FactionChoice'));
const ruid = (ui, path) => ui.getComponent(path, SPRITE).ImageRUID.DataId;

test('the choice buttons say "A 方" and "B 方", nothing more', () => {
  const ui = war();
  assert.equal(ui.getComponent('FactionChoice/Window/A', TEXT).Text, 'A 方');
  assert.equal(ui.getComponent('FactionChoice/Window/B', TEXT).Text, 'B 方');
});

test('the A and B buttons are the same Cardgame button, untinted, so only their text tells them apart', () => {
  const ui = war();
  for (const node of ['A', 'B']) {
    const path = `FactionChoice/Window/${node}`;
    const sprite = ui.getComponent(path, SPRITE);
    assert.equal(sprite.ImageRUID.DataId, CARD_BUTTON.normal, `${node} uses the Cardgame button art`);
    assert.deepEqual([sprite.Color.r, sprite.Color.g, sprite.Color.b, sprite.Color.a], [1, 1, 1, 1], `${node} is not tinted`);
    const button = ui.getComponent(path, BUTTON);
    assert.equal(button.Transition, 2, `${node} swaps sprites`);
    assert.deepEqual(
      [button.ImageRUIDs.HighlightedSprite.DataId, button.ImageRUIDs.PressedSprite.DataId, button.ImageRUIDs.DisabledSprite.DataId],
      [CARD_BUTTON.highlighted, CARD_BUTTON.pressed, CARD_BUTTON.pressed], `${node} swaps to the Cardgame highlight and pressed art`);
    assert.equal(ui.find(path).jsonString.enable, false, `${node} stays hidden until the server says CHOOSE`);
  }
  const strip = path => {
    const entity = war().find(path).jsonString;
    return entity['@components'].map(component => JSON.stringify(component, (key, value) => (key === 'anchoredPosition' || key === 'Position' || key === 'OffsetMin' || key === 'OffsetMax' ? undefined : value)))
      .map(text => text.replace(/"Text":"[^"]*"/, '"Text":""'));
  };
  assert.deepEqual(strip('FactionChoice/Window/A'), strip('FactionChoice/Window/B'), 'every component of A and B is identical except the text and the position');
  const a = ui.getComponent('FactionChoice/Window/A', 'MOD.Core.UITransformComponent');
  const b = ui.getComponent('FactionChoice/Window/B', 'MOD.Core.UITransformComponent');
  assert.deepEqual([a.RectSize, a.anchoredPosition.y], [b.RectSize, b.anchoredPosition.y], 'same size on the same row');
  assert.ok(a.anchoredPosition.x < 0 && b.anchoredPosition.x > 0, 'A on the left, B on the right');
});

test('the window is a Cardgame window: frame art, a Cardgame close button, no default grey skin left on a button', () => {
  const ui = war();
  assert.equal(ruid(ui, 'FactionChoice/Window/Frame'), BASE_FRAME, 'the Cardgame frame');
  assert.equal(ui.getComponent('FactionChoice/Window/Frame', SPRITE).FillCenter, false, 'the frame draws only its border');
  assert.equal(ui.getComponent('FactionChoice/Window/Frame', SPRITE).RaycastTarget, false, 'and takes no click');
  assert.equal(ruid(ui, 'FactionChoice/Window/Close'), CARD_BUTTON.normal, 'close is a Cardgame button too');
  for (const node of ['A', 'B', 'Close']) assert.notEqual(ruid(ui, `FactionChoice/Window/${node}`), DEFAULT_SKIN, `${node} is not the default grey skin`);
  const order = ['Frame', 'Title', 'Status', 'A', 'B', 'Close'].map(name => ui.find(`FactionChoice/Window/${name}`).jsonString.displayOrder);
  assert.deepEqual(order, [...order].sort((x, y) => x - y), 'the frame is drawn beneath the content');
  assert.equal(new Set(order).size, order.length, 'every sibling has its own order');
  // Maker takes render order from the order of the entities in the file, not from the numbers (tests/README.md, #123).
  const inFile = ui.entities.map(entity => entity.jsonString.path.replace('/ui/FactionWarGroup/FactionChoice/Window/', '')).filter(name => ['Frame', 'Title', 'Status', 'A', 'B', 'Close'].includes(name));
  assert.deepEqual(inFile, ['Frame', 'Title', 'Status', 'A', 'B', 'Close'], 'and so does the file: the frame comes first');
});

test('no node of the choice screen is named after a colour, and the dimmer and window keep their paths', () => {
  const ui = war();
  const paths = choiceNodes(ui).map(entity => entity.path.replace('/ui/FactionWarGroup/', ''));
  assert.deepEqual(paths.filter(path => /(red|blue)/i.test(path)), [], 'no Red / Blue node');
  for (const path of ['FactionChoice', 'FactionChoice/Window', 'FactionChoice/Window/Title', 'FactionChoice/Window/Status', 'FactionChoice/Window/A', 'FactionChoice/Window/B', 'FactionChoice/Window/Close']) {
    assert.ok(paths.includes(path), `${path} exists`);
  }
  assert.equal(ui.find('FactionChoice').jsonString.enable, false, 'hidden until the lobby entry opens it');
  assert.equal(ui.getComponent('FactionChoice', SPRITE).RaycastTarget, true, 'the dimmer blocks the lobby behind the window');
  assert.equal(ui.getComponent('FactionChoice/Window/Title', TEXT).Text, '加入國戰');
});

test('the script sends A or B from the two buttons and never colours them', () => {
  const script = read('RootDesk/MyDesk/Formations/FactionWarUI.mlua');
  assert.match(script, /Bind\("FactionChoice\/Window\/A", function\(\) self:Request\("A"\) end\)/);
  assert.match(script, /Bind\("FactionChoice\/Window\/B", function\(\) self:Request\("B"\) end\)/);
  const entry = script.slice(script.indexOf('method void ShowEntryControls'), script.indexOf('method boolean IsCurrentTown'));
  assert.match(entry, /for _, id in ipairs\(\{ "A", "B" \}\) do/, 'both buttons are driven by the same loop');
  assert.doesNotMatch(entry, /Color|ImageRUID/, 'the entry controls change enable state and text only');
});

test('the build script and the Maker probe are in the tree and name each other', () => {
  const build = read('assets/siege/build_faction_choice_ui.cjs');
  for (const name of ['FactionChoice/Window/A', 'FactionChoice/Window/B', 'FactionChoice/Window/Close', 'FactionChoice/Window/Frame']) assert.ok(build.includes(name), name);
  assert.match(build, /'A 方'/);
  assert.match(build, /'B 方'/);
  const probe = read('tests/faction_war_faction_choice_client_runtime_probe.lua');
  assert.match(probe, /\[VRF\]\[FactionChoice\] CLIENT PASS/);
  assert.match(probe, /\[VRF\]\[FactionChoice\] SERVER PASS/);
});
