const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');

const source = path => fs.readFileSync(path, 'utf8').replace(/\r\n/g, '\n');
const body = (text, name) => text.match(new RegExp(`method \\w+ ${name}\\([^]*?(?=\\n    @|\\n    method|\\nend)`))?.[0] || '';
const flow = () => source('RootDesk/MyDesk/Matchmaking/MatchFlow.mlua');
const room = () => source('RootDesk/MyDesk/Matchmaking/MatchedBattle.mlua');
const state = () => source('RootDesk/MyDesk/Matchmaking/MatchFlowState.mlua');
const handoff = () => source('RootDesk/MyDesk/Formations/FormationHandoff.mlua');
const battle = () => source('RootDesk/MyDesk/Combat/BattleSession.mlua');

test('ADR 0017: the room copies the absent side\'s sealed roster and field it once the entry time is over', () => {
  const copy = body(handoff(), 'LoadAbsentRoster');
  assert.match(copy, /_FormationStorage:Read\(profile, self\.StorageKey/, 'the roster is read from the absent profile\'s own record');
  assert.match(copy, /data\.matchKey ~= matched\.key|_MatchFlow:Belongs\(data, matched\)/, 'only the ticket sealed for this very match is fielded');
  assert.match(copy, /DecodeTransfer\(data\.transfer, catalog\)/, 'levels are decoded like any sealed roster');
  assert.doesNotMatch(copy, /_T\.byId|_T\.records/, 'the copy is detached from the ticket cache, so closing the ticket cannot touch it');
  const hold = body(room(), 'HoldForAbsent');
  assert.match(hold, /LoadAbsentRoster\(/, 'the room starts the copy as soon as it sees a lone human');
  assert.match(hold, /if not timedOut then return end/, 'the match waits for the entry time');
  assert.match(hold, /slot\.status == "READY"[^]*StartMatch\(battle, admission, slot\.units\)/, 'then it starts with the copied roster');
  assert.match(hold, /AdmissionFailed = true/, 'a roster that cannot be copied fails the admission');
  assert.match(body(room(), 'StartMatch'), /admission\.absent == "home" and absentUnits/, 'either side can be the absent one');
});

test('a room with nobody who can play never starts, and a late opponent still starts at once', () => {
  const text = room();
  assert.match(body(text, 'OnUpdate'), /if #users == 0 then return end/, 'an empty room does nothing: no deduction, no experience');
  assert.match(body(text, 'OnUpdate'), /RoomBattleAdmission\(true\)[^]*admission\.absent == nil then[^]*StartMatch\(battle, admission, nil\)/, 'both here starts immediately');
  assert.match(body(text, 'OnUpdate'), /elseif battle\.Phase == "CONFIG_ERROR" or timedOut then[^]*AdmissionFailed = true/, 'no admission at the deadline is still an entry failure');
  const admission = body(flow(), 'RoomBattleAdmission');
  assert.match(admission, /allowAbsent ~= true then return nil end/, 'the strict admission is unchanged');
  assert.match(admission, /absent = home == nil and "home" or "away"/, 'the missing human side is reported, not guessed');
  assert.match(admission, /matched\.guard == true then[^]*away = \{ data = \{ profile = matched\.away, attempt = "" \} \}/, 'the guard stays the away side');
  const session = body(battle(), 'InitializeMatchedBattle');
  assert.match(session, /elseif not present\[homeProfile\] and not present\[awayProfile\] then/, 'the battle needs at least one human in the room');
  assert.match(session, /if guardAway then[^]*if not present\[homeProfile\] then return false end/, 'a guard fight still needs its one human');
});

test('the waiting human sees the countdown, and the entry time does not fail a room that waits', () => {
  const rules = state();
  assert.match(body(rules, 'PresentMatch'), /等待對手進入戰場…（" \.\. tostring\(remaining\) \.\. " 秒）"/);
  assert.match(body(rules, 'EntryFailed'), /state == "WAITING" and \(snapshot\.waitDeadline or 0\) > 0 then return false end/);
  assert.match(body(flow(), 'StateSnapshot'), /waitDeadline = isvalid\(flow\) and flow\.WaitDeadline or 0/);
  assert.match(room(), /@Sync property number WaitDeadline = 0/);
  assert.match(body(room(), 'HoldForAbsent'), /PublishState\(user\.PlayerComponent\.UserId, "WAITING_OPPONENT"\)/);
});

test('ADR 0017 and the glossary agree with the code', () => {
  const adr = source('docs/adr/0017-matched-battle-starts-without-the-absent-side.md');
  assert.match(adr, /30 秒內沒有進房/);
  assert.match(adr, /缺席方的本局編隊必須在開戰前就讀進比賽房/);
  const glossary = source('CONTEXT.md');
  assert.match(glossary, /\*\*缺席出戰\*\*/);
});
