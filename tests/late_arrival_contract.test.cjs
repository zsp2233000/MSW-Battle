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
  assert.match(open, /HANDOFF_SAVE_FAILED[^]*HANDOFF_SEAL_FAILED[^]*ROOM_CREATE_FAILED[^]*ADMISSION_SAVE_FAILED/, 'a broken handoff is final');
  assert.match(open, /FindRoom\(data\.matchKey\) ~= nil/, 'the room has to live');
  assert.doesNotMatch(open, /Phase|IsBattleActive/, 'whether the fight has begun never decides the entry');
});

test('#121: standing in a match comes from its sealed profiles, never from the time of arrival', () => {
  const side = body(battle(), 'ParticipantSide');
  assert.match(side, /profile == self\.HomeProfile then return "PLAYER"/);
  assert.match(side, /profile == self\.AwayProfile then return "ENEMY"/);
  assert.doesNotMatch(side, /UtcNow|ElapsedSeconds|UserEntities|CurrentMap/, 'no arrival time and no presence enter the decision');
  assert.match(body(battle(), 'ResultForProfile'), /self:ParticipantSide\(profile\) == ""/);
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
