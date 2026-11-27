const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');

const source = path => fs.readFileSync(path, 'utf8').replace(/\r\n/g, '\n');
const body = (text, name) => text.match(new RegExp(`method \\w+ ${name}\\([^]*?(?=\\n    @|\\n    method|\\nend)`))?.[0] || '';
const flow = () => source('RootDesk/MyDesk/Matchmaking/MatchFlow.mlua');
const battle = () => source('RootDesk/MyDesk/Combat/BattleSession.mlua');

test('#121: a side that arrives after the fight began is let in, unless it stopped the entry or the room is gone', () => {
  const recover = body(flow(), 'Recover');
  assert.match(recover, /EntryFailed\(self:StateSnapshot\(userId, ""\), DateTime\.UtcNow\.Elapsed\) and not self:LateEntryOpen\(userId, ticket\)/,
    'an expired entry time or a failed move must not stop the walk-in while the room lives');
  const open = body(flow(), 'LateEntryOpen');
  assert.match(open, /ticket\.entryFailed == true then return false/, 'Stop Entry is final');
  assert.match(open, /closedMatches\[data\.matchKey\]/, 'a known closed room is final');
  assert.match(open, /_MatchFlowState:IsBrokenEntry\(code\)/, 'a broken handoff is final');
  const state = source('RootDesk/MyDesk/Matchmaking/MatchFlowState.mlua');
  assert.match(body(state, 'IsBrokenEntry'), /HANDOFF_SAVE_FAILED[^]*HANDOFF_SEAL_FAILED[^]*ROOM_CREATE_FAILED[^]*ADMISSION_SAVE_FAILED/, 'one list of them, shared with the entry-failed projection');
  assert.match(body(state, 'EntryFailed'), /self:IsBrokenEntry\(reason\) or reason == "ROOM_MOVE_FAILED"/);
  assert.match(open, /FindRoom\(data\.matchKey\) ~= nil/, 'the room has to live');
  assert.doesNotMatch(open, /Phase|IsBattleActive/, 'whether the fight has begun never decides the entry');
});

test('#121: a move that failed is tried again a few times by itself, until Stop Entry, a gone room or the limit', () => {
  const retry = body(flow(), 'RetryLateEntry');
  assert.match(retry, /failure\.code ~= "ROOM_MOVE_FAILED"/, 'only a failed move is retried');
  assert.match(retry, /not self:LateEntryOpen\(userId, ticket\)/, 'under the same conditions that let a late side in');
  assert.match(retry, /tries\.count >= self\.LateEntryRetries then return end/, 'a bounded number of times');
  assert.match(retry, /self\.LateEntryRetrySeconds/, 'spaced by a configured time');
  assert.match(retry, /current == nil or current\.data == nil or current\.data\.attempt ~= attempt or current\.entryFailed == true then return end/, 'a retry that fires after the ticket ended does nothing');
  assert.match(body(flow(), 'Recover'), /self:RetryLateEntry\(userId, ticket\)/);
  assert.match(body(flow(), 'Depart'), /self\._T\.lateTimers\)?\s*\}/, 'a departed player\'s retry is cleared');
  assert.match(body(flow(), 'OnEndPlay'), /self\._T\.lateTimers/, 'and so is every retry of a closing room');
});

test('#121: standing in a match comes from its sealed profiles, never from the time of arrival', () => {
  const side = body(battle(), 'ParticipantSide');
  assert.match(side, /profile == self\.HomeProfile then return "PLAYER"/);
  assert.match(side, /profile == self\.AwayProfile then return "ENEMY"/);
  assert.doesNotMatch(side, /UtcNow|ElapsedSeconds|UserEntities|CurrentMap/, 'no arrival time and no presence enter the decision');
  assert.match(body(battle(), 'ResultForProfile'), /self:ParticipantSide\(profile\) == ""/);
  assert.match(body(battle(), 'ResultForProfile'), /self:ParticipantSide\(profile\) == "PLAYER"/, 'the settled result is read from the same side');
  const view = source('RootDesk/MyDesk/Combat/BattleView.mlua');
  assert.match(body(view, 'GetLocalFaction'), /session:ParticipantSide\(/, 'the client asks the same function which side it is on');
  assert.doesNotMatch(view + source('RootDesk/MyDesk/Combat/BattleUIController.mlua'), /\bprofile (?:==|~=) session\.(?:Home|Away)Profile|session\.(?:Home|Away)Profile (?:==|~=) profile\b/, 'no display compares a player with the two profiles by itself any more');
  assert.match(body(battle(), 'PublishExperienceResults'), /local faction = self:ParticipantSide\(profile\)/);
  assert.match(body(flow(), 'StateSnapshot'), /battle:ParticipantSide\(ticket\.data\.profile\) ~= ""/);
  assert.match(body(flow(), 'ReturnForUser'), /battle:ParticipantSide\(profile\) ~= ""/);
});

test('#121: the e2e probe and the ADR carry the late arrival', () => {
  const probe = source('tests/late_arrival_e2e_runtime_probe.lua');
  assert.match(probe, /_MatchFaults:ConfigureAbsent\(idB, false\)/, 'the late side is released after the fight began');
  assert.match(probe, /ParticipantSide\(B_PROFILE\) == "ENEMY"/);
  assert.match(probe, /#\(towns\.settled or \{\}\) == 1/, 'one settlement');
  assert.match(source('docs/adr/0017-matched-battle-starts-without-the-absent-side.md'), /晚到者（#121）/);
});
