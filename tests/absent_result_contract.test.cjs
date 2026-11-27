const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');
const { UIBuilder } = require('../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');

// #122: the 上一場戰果 / 上一場對戰結果 window. The nodes AbsentResultUI binds by path exist in ui/AbsentResultGroup.ui, use the Cardgame art,
// and the seams (the room writes for sides that did not see the result, the static room delivers and ends the ticket, 確定 clears) sit where the issue says.
const read = (path) => fs.readFileSync(path, 'utf8').replace(/\r\n/g, '\n');
const body = (text, name) => text.match(new RegExp(`method \\w+ ${name}\\([^]*?(?=\\n    @|\\n    method|\\nend)`))?.[0] || '';
const absent = () => read('RootDesk/MyDesk/Matchmaking/AbsentResult.mlua');
const view = () => read('RootDesk/MyDesk/Matchmaking/AbsentResultUI.mlua');
const room = () => read('RootDesk/MyDesk/Matchmaking/MatchedBattle.mlua');
const flow = () => read('RootDesk/MyDesk/Matchmaking/MatchFlow.mlua');
const ui = () => UIBuilder.read('ui/AbsentResultGroup.ui');
const sprite = 'MOD.Core.SpriteGUIRendererComponent';
const button = 'MOD.Core.ButtonComponent';

const CARD_BUTTON = '9505617fb63c447c8ff9c15c18d88064';
const BASE_FRAME = 'ac319875b43f40ea86a069c468a1a26e';

test('the window is its own group above every other one, in Cardgame parts, with every node the script binds', () => {
  const file = ui();
  for (const path of ['Popup', 'Popup/Window', 'Popup/Window/Frame', 'Popup/Window/Title', 'Popup/Window/Result', 'Popup/Window/War',
    'Popup/Window/War/Origin', 'Popup/Window/War/Target', 'Popup/Window/War/Conclusion', 'Popup/Window/Confirm']) {
    assert.ok(file.find(path), `${path} exists`);
  }
  assert.equal(file.find('Popup').jsonString.enable, false, 'the dimmer is hidden until a record arrives');
  assert.equal(file.getComponent('Popup', sprite).RaycastTarget, true, 'and takes every click while it shows');
  assert.equal(file.getComponent('Popup/Window/Confirm', sprite).ImageRUID.DataId, CARD_BUTTON, 'the button is a Cardgame button');
  assert.equal(file.getComponent('Popup/Window/Confirm', button).Transition, 2, 'with SpriteSwap states');
  assert.equal(file.getComponent('Popup/Window/Frame', sprite).ImageRUID.DataId, BASE_FRAME, 'the hollow Base_4 frame');
  assert.equal(file.getComponent('Popup/Window/Frame', sprite).RaycastTarget, false, 'which takes no click');
  const group = file.find('/').jsonString['@components'].find((component) => /UIGroup/.test(component['@type']));
  const others = ['FactionWarGroup', 'WorldMapGroup', 'FormationGroup', 'GMPanelGroup', 'MatchGroup', 'MonsterDexGroup'].map((name) => {
    const other = UIBuilder.read(`ui/${name}.ui`).find('/').jsonString['@components'].find((component) => /UIGroup/.test(component['@type']));
    return other.GroupOrder;
  });
  assert.ok(group.GroupOrder > Math.max(...others), 'it draws above the town HUD, the lobby screen and the world map');
  assert.equal(group.DefaultShow, true, 'the group stays shown; the script toggles the dimmer');
  const script = view();
  for (const path of ['Popup', 'Popup/Window', 'Popup/Window/Confirm', 'Popup/Window/Title', 'Popup/Window/Result', 'Popup/Window/War',
    'Popup/Window/War/Origin', 'Popup/Window/War/Target', 'Popup/Window/War/Conclusion']) {
    assert.ok(script.includes(`"${path}"`), `the script uses ${path}`);
  }
});

test('the presentation: war title and block, lobby title and result only, never experience, towns highlighted', () => {
  const text = absent();
  const present = body(text, 'Present');
  assert.match(present, /title = "上一場對戰結果"/, 'the lobby window title');
  assert.match(present, /view\.title = "上一場戰果"/, 'the war window title');
  assert.match(present, /if war == nil then return view end/, 'a lobby record shows only the result');
  const code = (source) => source.split(/\r?\n/).filter((line) => !line.trim().startsWith('--')).join(' ');
  assert.doesNotMatch(code(text) + code(view()), /experience|經驗/i, 'no experience anywhere in the window');
  assert.match(body(text, 'StrengthLine'), /_FactionWarUI:HighlightedTownName\(town\)/, 'the shared highlight colours the town names');
  assert.match(present, /_FactionWarUI:HighlightedTownName\(war\.capturedTown\)/, 'including the captured town in the conclusion');
  assert.match(text, /ResultText = \{ WIN = "勝利", LOSE = "失敗", DRAW = "平手" \}/);
  assert.match(read('RootDesk/MyDesk/Formations/FactionWarUI.mlua'), /TownNameHighlightHex = "#4DFEE7"/, 'one highlight colour for every war surface');
  assert.match(view(), /_AbsentResult:RequestAcknowledge\(record\.id\)/, '確定 asks the server to forget the record');
  assert.match(body(view(), 'Confirm'), /popup:SetEnable\(false\)/, 'and closes at once');
});

test('the room writes the latest absent result for sides that did not see the result page, once, and takes it back when they do', () => {
  const text = room();
  assert.match(body(text, 'WriteAbsentResults'), /if self\._T\.absentDone then return end/, 'once per match');
  assert.match(body(text, 'WriteAbsentResults'), /not _FactionWarGuard:IsGuardProfile\(profile\) and not self\._T\.seen\[profile\]/, 'a guard and a side that saw the page get none');
  assert.match(body(text, 'WriteAbsentResults'), /_FactionWarTownDocument:Summarize\(side\.origin, side\.target, "", war\.outcome, nil\)/, 'the war block is the settled summary of the side\'s own towns');
  assert.match(body(text, 'WriteAbsentResults'), /_AbsentResult:Write\(profile, record[^]*_AbsentResult:Announce\(profile, matchKey\)/, 'announced once the record is saved');
  assert.match(body(text, 'TrackResultViewers'), /_AbsentResult:Clear\(profile, matchKey/, 'a late arrival who sees the result page takes its record back');
  assert.match(body(text, 'TrackResultViewers'), /absentWritten\[profile\] == "WRITTEN"/, 'a record that is still being saved is left to its own save callback');
  assert.match(body(text, 'WriteAbsentResults'), /elseif self\._T\.seen\[profile\] then[^]*_AbsentResult:Clear\(profile, matchKey/, 'which takes the record back when the save lands and the side was seen meanwhile');
  assert.match(body(text, 'WatchSettlement'), /outcome = \{ status = "FAILED" \}/, 'a settlement that never answers does not leave the absent side without its window');
  assert.match(body(text, 'WatchSettlement'), /self\.SettlementWatchSeconds/, 'after a configured time, not a literal');
  assert.match(body(text, 'OnEndPlay'), /ClearTimer\(self\._T\.watchdog\)/, 'and the watch ends with the room');
  const update = body(text, 'OnUpdate');
  assert.match(update, /self:TrackResultViewers\(battle, users\)[^]*not self\._T\.published/, 'viewers are counted before the result is published');
  assert.match(update, /self:WriteAbsentResults\(battle, war\)/, 'a war match writes once its settlement is known');
  assert.match(update, /else\n\s+self:WriteAbsentResults\(battle, nil\)/, 'a lobby match writes at once');
});

test('the static room delivers once per match, ends the ticket of the match first, and a login or a reconnect delivers too', () => {
  const text = absent();
  assert.match(body(text, 'RunDelivery'), /_MatchFlow:HintSettled\(userId\)[^]*_MatchFlow:Recover\(userId\)/, 'the ticket of that match is recovered (and ended) before the window');
  assert.match(body(text, 'RunDelivery'), /self\._T\.delivered\[userId\] == record\.id/, 'once per match');
  assert.match(body(text, 'RunDelivery'), /IsInstanceRoom\(\)/, 'never in a match room');
  assert.match(body(text, 'Deliver'), /self:RunDelivery\(userId, false\)/, 'a login or a reconnect shows the record without ending anything');
  assert.match(body(text, 'DeliverAfterSettle'), /self:RunDelivery\(userId, true\)/, 'a settlement ends the ticket first');
  assert.match(body(text, 'Notify'), /if _RoomService:IsInstanceRoom\(\) then return end/, 'only the static room holds an online absent player');
  assert.match(text, /handler HandleRoomAbsentResult\(AbsentResultEvent event\)/, 'the match room reaches the static room');
  assert.match(text, /handler HandleInstanceAbsentResult\(AbsentResultEvent event\)/, 'and every other world instance');
  assert.match(text, /handler HandleUserReconnectEvent\(UserReconnectEvent event\)[^]*self:Deliver\(event\.UserId\)/, 'a reconnect shows a waiting record again');
  assert.match(flow(), /self:PlaceAtLogin\(event\.UserId, "enter"\)\n\s+-- [^\n]*\n\s+_AbsentResult:Deliver\(event\.UserId\)/, 'a login shows a waiting record after its ticket was recovered and the player landed');
  assert.match(body(text, 'Clear'), /current\.id ~= matchKey then complete\(true\)/, 'a newer match is never cleared by an older acknowledgement');
  assert.match(body(text, 'Write'), /current\.id == record\.id then complete\(true\)/, 'writing the same match again changes nothing');
  assert.match(body(text, 'RequestAcknowledge'), /local userId = senderUserId/, 'the server derives the player from the sender, never from the client');
});

test('a ticket whose match settled without the player ends at once, through the same return and landing as Stop Entry (ADR 0016)', () => {
  const recover = body(flow(), 'Recover');
  assert.match(recover, /if self:AbsentResultEndsTicket\(userId, data\) then[^]*self:ReturnTicket\(userId, ticket, "ABSENT_RESULT_SETTLED", "RETURN_SAVE_FAILED"\)/,
    'it returns and restores like any ended ticket');
  assert.match(body(flow(), 'ReturnTicket'), /BeginReturn\(userId, ticket\)[^]*self:RestoreReturning\(userId, ticket\)/, 'and RestoreReturning lands by the origin rule');
  const settled = body(flow(), 'AbsentResultEndsTicket');
  assert.match(settled, /data\.state ~= "TRANSFER" and data\.state ~= "COMMITTING" and data\.state ~= "IN_ROOM" then return false end/, 'only a match the player never finished');
  assert.match(settled, /AbsentCheckSeconds \* 1000 then return false end/, 'a waiting ticket does not read the record on every recovery');
  assert.match(settled, /_AbsentResult:Standing\(data\.profile, data\.matchKey/, 'the record of that very match decides');
  assert.match(settled, /standing == "CLEARED" and data\.state ~= "IN_ROOM"/, 'a confirmed record ends a ticket that never entered, never one inside the room');
});

test('the e2e probe, the runbook and ADR 0017 carry the absent result', () => {
  const probe = read('tests/absent_result_e2e_runtime_probe.lua');
  assert.match(probe, /ONLINE/, 'the online push');
  assert.match(probe, /RELOGIN/, 'and the login after being offline');
  assert.match(read('docs/adr/0017-matched-battle-starts-without-the-absent-side.md'), /最近一場缺席戰果（#122）/);
  assert.match(read('tests/README.md'), /Absent result window \(ADR 0017, #122\)/);
});
