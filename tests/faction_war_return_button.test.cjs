const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');

const source = path => fs.readFileSync(path, 'utf8').replace(/\r\n/g, '\n');
const body = (text, name) => text.match(new RegExp(`method \\w+ ${name}\\([^]*?(?=\\n\\s*@|\\n\\s*method|\\nend)`))?.[0] || '';
const state = () => source('RootDesk/MyDesk/Matchmaking/MatchFlowState.mlua');
const input = () => source('RootDesk/MyDesk/Matchmaking/MatchFlowInput.mlua');
const ui = () => source('RootDesk/MyDesk/Combat/BattleUIController.mlua');

test('#119: the result page return button names the destination from the settlement receipt', () => {
  const plan = body(state(), 'ReturnPlan');
  assert.match(plan, /label = "返回 " \.\. destination/, 'the button reads 返回 <town>');
  assert.match(plan, /\.\. "已失守"/, 'a fallen departure town is announced');
  assert.match(plan, /label = "返回大廳"/, 'a lobby match keeps 返回大廳');
  assert.match(body(state(), 'Present'), /plan = self:ReturnPlan\(context\)/, 'the result and return states read the plan');
  const view = body(input(), 'View');
  assert.match(view, /_BattleUIController:CurrentWarResult\(\)/, 'the destination comes from the receipt the result page displays');
  assert.match(view, /receipt\.destination/, 'it is the receipt\'s destination');
  assert.match(view, /destination == "" and originName ~= "" then destination = origin/, 'until the receipt knows, the departure town is shown');
  assert.match(view, /HighlightedTownName\(destination\)/, 'the town name uses the shared highlight');
  assert.match(view, /originLost = receipt ~= nil and receipt\.originLost == true/, 'the fall notice follows the receipt, so a later change updates it');
  assert.match(body(ui(), 'CurrentWarResult'), /return self\._T\.warReceipt/, 'the controller hands out the receipt it displays');
});

test('#119: the actual return still judges ownership at the moment of return', () => {
  const flow = source('RootDesk/MyDesk/Matchmaking/MatchFlow.mlua');
  assert.match(body(flow, 'MoveHome'), /_FactionWarLanding:Judge\(userId, \{ kind = "RETURN"/, 'the return button never trusts the preview');
  assert.match(body(source('RootDesk/MyDesk/Formations/FactionWarLanding.mlua'), 'BattleDestination'), /_FactionWarTownDocument:Landing\(faction, origin, board\)/, 'ADR 0016 landing rule');
  const room = source('RootDesk/MyDesk/Matchmaking/MatchedBattle.mlua');
  assert.match(room, /HandleWarResultRoomBoardChanged[^]*RefreshWarResultBoard\(\)/, 'a board change reaching the room re-sends the receipt');
});
