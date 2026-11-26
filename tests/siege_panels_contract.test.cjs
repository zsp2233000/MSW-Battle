const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');
const { UIBuilder } = require('../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');

// #117 attack panel and #118 team preview: the nodes the scripts bind by path exist in ui/FactionWarGroup.ui, use the Cardgame art, and the
// source seams (one board read, panel viewers, ticket-frozen team, read-only preview) are where the issues say they are.
const read = (path) => fs.readFileSync(path, 'utf8').replace(/\r\n/g, '\n');
const body = (text, name) => text.match(new RegExp(`method \\w+ ${name}\\([^]*?(?=\\n    @|\\n    method|\\nend)`))?.[0] || '';
const attack = () => read('RootDesk/MyDesk/Formations/FactionWarAttack.mlua');
const mapLogic = () => read('RootDesk/MyDesk/Formations/FactionWarMap.mlua');
const townUi = () => read('RootDesk/MyDesk/Formations/FactionWarUI.mlua');
const teamLogic = () => read('RootDesk/MyDesk/Formations/FactionWarTeam.mlua');
const ui = () => UIBuilder.read('ui/FactionWarGroup.ui');
const sprite = 'MOD.Core.SpriteGUIRendererComponent';
const button = 'MOD.Core.ButtonComponent';
const textComponent = 'MOD.Core.TextGUIRendererComponent';

const CARD_BUTTON = '9505617fb63c447c8ff9c15c18d88064';
const X_BUTTON = 'e01ef74a1ecf444bbb013c4313a8d0a9';
const BASE_FRAME = 'ac319875b43f40ea86a069c468a1a26e';
const GAUGE = 'f0911af597259044aa624a11332c0595';

test('the attack panel is rebuilt with Cardgame parts: departure town card, two target cards with strength bars, close button', () => {
  const file = ui();
  const panel = 'AttackPanel/Window';
  for (const path of ['Frame', 'Title', 'Close', 'Origin', 'Origin/Label', 'Origin/Name', 'Origin/Capital', 'Origin/Value', 'Origin/Bar', 'Origin/Bar/Fill', 'Status']) {
    assert.ok(file.find(`${panel}/${path}`), `${path} exists`);
  }
  for (const row of ['Row1', 'Row2']) {
    for (const part of ['Name', 'Capital', 'Note', 'Value', 'Bar', 'Bar/Fill', 'Option']) assert.ok(file.find(`${panel}/${row}/${part}`), `${row}/${part} exists`);
    assert.equal(file.getComponent(`${panel}/${row}/Option`, sprite).ImageRUID.DataId, CARD_BUTTON, 'the target button is a Cardgame button');
    assert.equal(file.getComponent(`${panel}/${row}/Option`, button).Transition, 2, 'with SpriteSwap states');
    assert.equal(file.getComponent(`${panel}/${row}/Bar/Fill`, sprite).ImageRUID.DataId, GAUGE, 'the bar is the Cardgame gauge');
    assert.equal(file.find(`${panel}/${row}`).jsonString.enable, false, 'rows are hidden until the answer arrives');
  }
  assert.equal(file.getComponent(`${panel}/Close`, sprite).ImageRUID.DataId, X_BUTTON, 'the close button is the Cardgame X');
  assert.equal(file.getComponent(`${panel}/Frame`, sprite).ImageRUID.DataId, BASE_FRAME, 'the hollow Base_4 frame');
  assert.equal(file.getComponent(`${panel}/Frame`, sprite).FillCenter, false, 'it only draws the border');
  assert.equal(file.getComponent(`${panel}/Frame`, sprite).RaycastTarget, false, 'and takes no click');
  assert.equal(file.getComponent('AttackPanel', sprite).RaycastTarget, true, 'the dimmer blocks the town behind it');
  assert.equal(file.find('AttackPanel').jsonString.enable, false, 'closed by default');
});

test('the team button sits beside the world map button and the preview is read-only', () => {
  const file = ui();
  assert.ok(file.find('TeamButton'), 'TeamButton exists');
  assert.equal(file.getComponent('TeamButton', textComponent).Text, '隊伍');
  assert.equal(file.getComponent('TeamButton', sprite).ImageRUID.DataId, CARD_BUTTON);
  assert.equal(file.find('TeamButton').jsonString.enable, false, 'only the town script shows it, never the lobby');
  const map = UIBuilder.read('ui/WorldMapGroup.ui').getComponent('OpenButton', 'MOD.Core.UITransformComponent');
  const team = file.getComponent('TeamButton', 'MOD.Core.UITransformComponent');
  assert.equal(team.AlignmentOption, map.AlignmentOption, 'anchored to the same corner');
  assert.equal(team.anchoredPosition.y, map.anchoredPosition.y, 'on the same row');
  // Both are right-anchored with the pivot on the right edge, so x is the distance of the right edge from the screen edge.
  assert.ok(team.anchoredPosition.x <= map.anchoredPosition.x - map.RectSize.x, 'to the left of the map button, without overlapping it');
  for (const path of ['Frame', 'Title', 'Close', 'Field', 'Field/Empty', 'Hint', 'Note']) assert.ok(file.find(`TeamPreview/Window/${path}`), `${path} exists`);
  for (let index = 1; index <= 6; index++) {
    for (const part of ['', '/Portrait', '/Lv']) assert.ok(file.find(`TeamPreview/Window/Field/Unit${index}${part}`), `Unit${index}${part} exists`);
  }
  const buttons = file.listEntities().filter(node => node.path.startsWith('/ui/FactionWarGroup/TeamPreview/') && file.hasComponent(node.path, button));
  assert.deepEqual(buttons.map(node => node.path.split('/').pop()), ['Close'], 'the only control is Close: nothing can be changed or replaced here');
  const texts = file.listEntities().filter(node => node.path.includes('/TeamPreview') || node.path.endsWith('/TeamButton') || node.path.includes('/AttackPanel'))
    .filter(node => file.hasComponent(node.path, textComponent)).map(node => file.getComponent(node.path, textComponent).Text);
  assert.ok(texts.every(value => !value.includes('編隊')), 'the glossary says 隊伍, never 編隊');
});

test('the attack answer carries strengths from the one board read and the panel follows pushes', () => {
  const text = attack();
  assert.match(body(text, 'Targets'), /strength = towns\[id\]\.strength, owner = towns\[id\]\.owner/, 'each target carries strength and owner from the same board');
  assert.match(body(text, 'Targets'), /capital = _FactionWarTownDocument:IsCapital\(id\)/, 'and the capital flag');
  assert.match(body(text, 'Header'), /strength = town\.strength/, 'the departure town header');
  const options = body(text, 'OptionsFor');
  assert.match(options, /header\.target = _MatchFlow:TargetForUser\(userId\)/, 'a queued player\'s panel names the target');
  assert.match(options, /_FactionWarMap:WatchPanel\(userId, player\)/, 'a ready panel is a viewer');
  assert.equal((options.match(/_FactionWarTownDocument:Read|self:Resolve\(/g) || []).length, 1, 'OptionsFor reads the town table once, through Resolve');
  assert.match(text, /method void ReceiveOptions\(string town, table options, string status, table header\)/, 'the reply carries the header');
  const map = mapLogic();
  assert.match(body(map, 'WatchPanel'), /panelViewers\[userId\] = player/, 'panel viewers are their own table, so the map\'s subscription is unchanged');
  assert.match(body(map, 'Deliver'), /panelViewers[^]*ReceivePanelBoard\(board\.towns, userId\)/, 'a changed board is pushed to them');
  assert.match(body(map, 'Deliver'), /ReceiveBoard\(board\.towns, board\.links, userId\)/, 'the map viewers still get the map board');
  assert.match(body(map, 'BoardChanged'), /next\(self\._T\.viewers\) == nil and next\(self\._T\.panelViewers\) == nil/, 'a panel alone is enough to read the board');
  assert.match(map, /handler HandleUserLeaveEvent[^]*panelViewers\[event\.UserId\] = nil/, 'leaving the room ends the push');
  assert.match(body(map, 'RequestPanelClose'), /panelViewers\[senderUserId\] = nil/, 'closing the panel ends the push');
  const client = townUi();
  assert.match(body(client, 'CloseAttack'), /_FactionWarMap:RequestPanelClose\(\)/, 'closing the panel unsubscribes');
  assert.match(body(client, 'EnterMap'), /self:CloseAttack\(\)/, 'so does arriving in another map');
  assert.match(body(client, 'ShowAttackBoard'), /_FactionWarAttack:RequestOptions\(\)/, 'a changed owner relists the targets');
  assert.match(body(client, 'RenderAttack'), /_FactionWarMapUI:OwnerColor|SetBar/, 'the bars take the faction colour');
  assert.match(client, /HighlightedTownName\(option\.town\)/, 'target names use the shared highlight');
  assert.match(client, /HighlightedTownName\(header\.town\)/, 'and so does the departure town');
});

test('the team preview shows the ticket\'s frozen team while queued, the saved active team otherwise, and nothing can be changed', () => {
  const text = teamLogic();
  assert.match(body(text, 'TicketTeam'), /_FormationHandoff:Roster\(ticketId\)/, 'the frozen units and levels come from the server\'s ticket');
  assert.match(body(text, 'TicketTeam'), /StateForUser\(userId\) == "IDLE" then return \{ status = "NONE"/, 'no ticket: the client uses its own saved team');
  assert.match(body(text, 'TeamFor'), /_FactionWar:IsTown\(player\.CurrentMapName\)/, 'answered only inside a town');
  assert.match(body(text, 'Present'), /view\.title = "本局隊伍"/);
  assert.match(body(text, 'Present'), /view\.hint = "要更換出戰隊伍，請找大廳 NPC"/);
  assert.match(body(text, 'Present'), /view\.empty = "尚未選定出戰隊伍"/);
  assert.doesNotMatch(text, /編隊/, 'the glossary says 隊伍');
  assert.doesNotMatch(text, /SaveForUser|ActivateForUser|RequestSave|RequestActivate|RequestEdit/, 'the preview has no way to change or replace a team');
  assert.match(body(townUi(), 'OnUpdate'), /_FactionWarTeam:Sync\(name\)/, 'the town script keeps the button in step with the map');
  assert.match(townUi(), /self:Bind\("TeamButton", function\(\) _FactionWarTeam:Open\(\) end\)/);
  assert.match(body(text, 'Sync'), /_FactionWar:IsTown\(map\) and not _FormationLobby:IsTownPanelOpen\(\)/, 'never in the game lobby');
  assert.match(read('RootDesk/MyDesk/Matchmaking/MatchFlow.mlua'), /method string TicketIdForUser/, 'the coordinator names the ticket without exposing its payload');
});
