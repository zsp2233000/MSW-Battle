const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');
const { UIBuilder } = require('../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');

// #123: the siege panel replaces the queue bar. The presentation rules and the board push run in siege_panels_local.cjs (fengari);
// these tests pin what only the files can say: the authored UI, who may call what, and that nothing still points at the old bar.
const source = path => fs.readFileSync(path, 'utf8').replace(/\r\n/g, '\n');
const body = (text, name) => text.match(new RegExp(`method \\w+ ${name}\\([^]*?(?=\\n    @|\\nend)`))?.[0] || '';

test('the siege panel is a Cardgame card at the top centre with both towns, the status and one button', () => {
  const war = UIBuilder.read('ui/FactionWarGroup.ui');
  const card = war.find('SiegePanel');
  assert.ok(card, 'SiegePanel exists');
  assert.equal(card.jsonString.enable, false, 'hidden until a pairing owns the player');
  const transform = war.getComponent('SiegePanel', 'MOD.Core.UITransformComponent');
  assert.deepEqual([transform.AnchorsMin.x, transform.AnchorsMin.y, transform.AnchorsMax.x, transform.AnchorsMax.y], [0.5, 1, 0.5, 1], 'anchored top centre');
  assert.equal(war.getComponent('SiegePanel', 'MOD.Core.SpriteGUIRendererComponent').RaycastTarget, true, 'a click on the card never reaches the world behind it');
  for (const part of ['Origin', 'Versus', 'Target', 'Status']) {
    assert.ok(war.hasComponent(`SiegePanel/${part}`, 'MOD.Core.TextGUIRendererComponent'), `${part} is a text`);
  }
  assert.ok(war.hasComponent('SiegePanel/Cancel', 'MOD.Core.ButtonComponent'), 'one button');
  assert.ok(war.hasComponent('SiegePanel/Frame', 'MOD.Core.SpriteGUIRendererComponent'), 'the Cardgame frame');
  const size = war.getComponent('SiegePanel/Cancel', 'MOD.Core.UITransformComponent').RectSize;
  assert.ok(size.x >= 88 && size.y >= 88, 'a touch-sized button');
});

test('the siege panel is drawn under the team preview and above the town HUD', () => {
  const war = UIBuilder.read('ui/FactionWarGroup.ui');
  const order = name => war.find(name).jsonString.displayOrder;
  assert.ok(order('SiegePanel') < order('TeamPreview'), 'the team preview covers the siege panel');
  assert.ok(order('SiegePanel') > order('TownHUD'), 'the siege panel covers the town HUD');
});

test('nothing refers to the removed queue bar any more', () => {
  const war = UIBuilder.read('ui/FactionWarGroup.ui');
  assert.equal(war.find('QueueBar'), null);
  for (const file of ['RootDesk/MyDesk/Formations/FactionWarUI.mlua', 'assets/siege/build_siege_ui.cjs', 'assets/siege/build_siege_panel_ui.cjs']) {
    const text = source(file);
    // Only the siege panel's build script names the old bar, once, to remove it from files built before #123.
    const mentions = text.match(/QueueBar/g) || [];
    assert.equal(mentions.length, file.endsWith('build_siege_panel_ui.cjs') ? 1 : 0, `${file} mentions QueueBar`);
  }
  assert.doesNotMatch(source('RootDesk/MyDesk/Formations/FactionWarUI.mlua'), /RenderQueue|QueueView|CancelQueue/);
});

test('the siege panel shows only in a town and only while a war pairing owns the player', () => {
  const ui = source('RootDesk/MyDesk/Formations/FactionWarUI.mlua');
  const active = body(ui, 'SiegeActive');
  assert.match(active, /_FactionWar:IsTown\(map\)/, 'town only');
  assert.match(active, /snapshot\.target or ""\) ~= ""/, 'a war pairing (it has a target town)');
  assert.match(active, /snapshot\.state ~= "IDLE"/, 'not while idle');
  assert.match(body(ui, 'RenderSiege'), /self:SiegeActive\(map, snapshot\)/, 'the card follows that rule');
  assert.match(body(ui, 'PressSiege'), /self:SiegeActive\(/, 'and so does its button');
  assert.match(body(ui, 'RenderSiege'), /self:FollowSiege\(shown\)/, 'the board subscription follows what shows');
});

test('the siege subscription is a Server RPC that trusts only the sender and never leaks the map links or faction', () => {
  const map = source('RootDesk/MyDesk/Formations/FactionWarMap.mlua');
  for (const name of ['RequestSiegeOpen', 'RequestSiegeClose']) {
    assert.match(map, new RegExp(`@ExecSpace\\("Server"\\)\\n    method void ${name}\\(\\)`), `${name} is a Server RPC`);
    assert.match(body(map, name), /senderUserId/, `${name} identifies the caller on the server`);
  }
  assert.match(map, /@ExecSpace\("Client"\)\n    method void ReceiveSiegeBoard\(table towns\)/, 'the push carries towns only');
  assert.match(body(map, 'ReceiveSiegeBoard'), /_FactionWarUI:ShowSiegeBoard\(towns\)/);
  assert.match(body(map, 'Deliver'), /self:PushSiegeBoard\(board, changed, answering\)/, 'a board change reaches the siege viewers');
  assert.match(body(map, 'PushSiegeBoard'), /siegeViewers/, 'from their own set');
  assert.match(body(map, 'BoardChanged'), /siegeViewers/, 'a siege viewer alone is reason enough to read the board');
  assert.match(map, /handler HandleUserLeaveEvent[^]*siegeViewers\[event\.UserId\] = nil/, 'leaving the room ends the subscription');
});

test('the card never says who the opponent is', () => {
  const ui = source('RootDesk/MyDesk/Formations/FactionWarUI.mlua');
  for (const name of ['SiegeView', 'SiegeTown', 'SiegeSnapshotView', 'SiegeActive', 'RenderSiege', 'PressSiege']) {
    assert.doesNotMatch(body(ui, name), /守衛|取消入場|編隊/, `${name} keeps the glossary`);
  }
});
