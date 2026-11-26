const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');

// Structural contract for #108 (two matches contest the same town; only the settlement that really flips it counts).
// The behaviour itself is proven by tests/faction_war_contest_runtime_probe.lua and
// tests/faction_war_contest_e2e_runtime_probe.lua in Maker; these tests pin the seams those probes drive.
const source = path => fs.readFileSync(path, 'utf8').replace(/\r\n/g, '\n');
const methods = text => [...text.matchAll(/^    method \w+ (\w+)\(/gm)].map(m => m[1]);
const body = (text, name) => text.match(new RegExp(`method \\w+ ${name}\\([^]*?(?=\\n    @|\\n    method|\\n    handler|\\nend)`))?.[0] || '';
const document = () => source('RootDesk/MyDesk/Formations/FactionWarTownDocument.mlua');
const attack = () => source('RootDesk/MyDesk/Formations/FactionWarAttack.mlua');
const storage = () => source('RootDesk/MyDesk/Formations/FormationStorage.mlua');
const flow = () => source('RootDesk/MyDesk/Matchmaking/MatchFlow.mlua');
const battle = () => source('RootDesk/MyDesk/Matchmaking/MatchedBattle.mlua');

test('the document uses the shared storage seam; the native adapter guards only first creation', () => {
  assert.doesNotMatch(document(), /_DataStorageService/, 'even Maker fixture writes use the seam');
  assert.doesNotMatch(attack(), /ReadTownsRaw|SwapTowns|WriteTowns|\.settled/, 'the attack flow never sees bytes or the history list');
  const guard = storage();
  assert.ok(methods(guard).includes('Storage'), 'the storage boundary resolves which storage an owner means');
  assert.match(body(guard, 'Storage'), /GetGlobalDataStorage/, 'a world-wide table is addressed through the same boundary');
  assert.match(body(guard, 'Storage'), /GetUserDataStorage\(owner\)/, 'a player profile still means that player\'s storage');
  assert.doesNotMatch(guard.replace(body(guard, 'Storage'), ''), /_DataStorageService:GetUserDataStorage\(/, 'no other call bypasses the resolver');
  const swapBody = body(guard, 'Swap');
  assert.match(swapBody, /UpdateAsync\(key, expected, raw,/, 'an existing document is arbitrated by the native conditional update');
  assert.doesNotMatch(swapBody, /BeginExclusive|StoreGuarded/, 'and takes no guard, so no guard can stay behind and block every later settlement');
  assert.match(swapBody, /expected == "" then self:Write\(/, 'only the first creation shares the guarded write');
  assert.match(swapBody, /code == 1000002 and 2000000 or code/, 'a changed document is one conflict code however the native layer words it');
});

test('a match is stamped with the board it was paired on, and the stamp travels with the ticket into the match room', () => {
  const text = attack();
  for (const name of ['Snapshot', 'Stamped', 'Combine']) assert.ok(methods(text).includes(name), `${name} exists`);
  assert.match(body(text, 'Snapshot'), /EpochOf\(towns, home\)[^]*EpochOf\(towns, away\)|EpochOf\(towns, matched\.homeOrigin\)/, 'both towns of the pairing are counted');
  assert.match(body(text, 'Snapshot'), /return false/, 'a lobby pairing or an unreadable board is an explicit "no stamp", not a zero count');
  assert.match(body(text, 'Stamped'), /homeEpoch = [^]*awayEpoch = /, 'the stamp is two plain numbers on a copy of the pairing');
  const matched = body(flow(), 'Matched');
  assert.match(matched, /ticket\.snapshot == nil then ticket\.snapshot = _FactionWarAttack:Snapshot\(matched\)/, 'the first reading of a ticket stands, so a deferred match never restamps later');
  assert.match(matched, /matched = _FactionWarAttack:Stamped\(matched, ticket\.snapshot\)/, 'the sealed pairing is the stamped copy');
  assert.ok(matched.indexOf('_FactionWarAttack:Snapshot(') > -1 && matched.indexOf('_FactionWarAttack:Snapshot(') < matched.indexOf('_FormationHandoff:Seal('), 'the board is read before anything yields into the seal');
  assert.ok(matched.indexOf('_FactionWarAttack:Stamped(') < matched.indexOf('_FormationHandoff:Commit('), 'and the commit stores the stamped pairing');
  const admission = body(flow(), 'RoomBattleAdmission');
  assert.match(admission, /epochs = _FactionWarAttack:Combine\(/, 'the room reads the stamps of the tickets it holds');
  assert.match(body(battle(), 'StartMatch'), /self\._T\.epochs = admission\.epochs/, 'the match room keeps them until the result');
  assert.match(body(battle(), 'OnUpdate'), /_FactionWarAttack:Settle\([^]*"HUMAN", function\(status, detail, outcome\)[^]*end, self\._T\.epochs\)/, 'and hands them to the settlement as the last argument, after the receipt callback');
});

test('settlement passes the pairing stamp into the document and announces only a confirmed flip', () => {
  const text = attack();
  assert.match(text, /method void Settle\(string matchKey, string homeTown, string awayTown, string homeResult, string kind, any complete, any snapshot\)/);
  assert.match(body(text, 'Settle'), /_FactionWarTownDocument:Settle\([^]*snapshot = snapshot/);
  assert.match(body(text, 'Finish'), /applied and outcome\.flipped then _FactionWar:AnnounceFall/);
});

// The stamp ordering, exact-byte retry, and re-evaluation are checked by running Apply/Settle,
// not by matching the implementation of Attempt.

test('experience and the match result never wait for the town settlement', () => {
  const session = source('RootDesk/MyDesk/Combat/BattleSession.mlua');
  assert.doesNotMatch(session, /_FactionWarAttack/, 'the battle session never asks the towns anything');
  assert.match(session, /_MonsterLevelStorage:Settle\(self\.HomeProfile, self\.MatchKey, self\._T\.deaths\.PLAYER\)/, 'the dead units of the home side are credited when the result is produced');
  assert.match(session, /_MonsterLevelStorage:Settle\(self\.AwayProfile, self\.MatchKey, self\._T\.deaths\.ENEMY\)/, 'and those of the away side');
  const update = body(battle(), 'OnUpdate');
  assert.ok(update.indexOf('PublishState(user.PlayerComponent.UserId, "RESULT_"') > -1 && update.indexOf('PublishState(user.PlayerComponent.UserId, "RESULT_"') < update.indexOf('_FactionWarAttack:Settle('),
    'every player is shown their win, loss or draw before the towns are touched');
});

// The live-board return and its retries are exercised through Judge in faction_war_landing_local.cjs.
