const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');

// Structural contract for #108 (two matches contest the same town; only the settlement that really flips it counts).
// The behaviour itself is proven by tests/faction_war_contest_runtime_probe.lua and
// tests/faction_war_contest_e2e_runtime_probe.lua in Maker; these tests pin the seams those probes drive.
const source = path => fs.readFileSync(path, 'utf8').replace(/\r\n/g, '\n');
const methods = text => [...text.matchAll(/^    method \w+ (\w+)\(/gm)].map(m => m[1]);
const body = (text, name) => text.match(new RegExp(`method \\w+ ${name}\\([^]*?(?=\\n    @|\\n    method|\\n    handler|\\nend)`))?.[0] || '';
const war = () => source('RootDesk/MyDesk/Formations/FactionWar.mlua');
const attack = () => source('RootDesk/MyDesk/Formations/FactionWarAttack.mlua');
const storage = () => source('RootDesk/MyDesk/Formations/FormationStorage.mlua');
const flow = () => source('RootDesk/MyDesk/Matchmaking/MatchFlow.mlua');
const battle = () => source('RootDesk/MyDesk/Matchmaking/MatchedBattle.mlua');

test('the town document counts how many times each town has changed hands', () => {
  const text = war();
  assert.ok(methods(text).includes('EpochOf'), 'the count is read through one helper that treats a missing field as zero');
  assert.match(body(text, 'EpochOf'), /or 0/, 'a document written before #108 has no count and reads as zero');
  const decode = body(text, 'DecodeTowns');
  assert.match(decode, /town\.e/, 'the decoder looks at the stored count');
  assert.match(decode, /town\.e % 1 ~= 0|town\.e < 0/, 'and refuses a count that is not a non-negative integer');
  assert.match(decode, /town\.strength < 1 or town\.strength > self\.FullStrength/, 'a stored zero strength is still refused');
  const settle = body(attack(), 'Attempt');
  assert.match(settle, /e = towns\[id\]\.e/, 'a town that did not change hands keeps its count as it was');
  assert.match(settle, /e = _FactionWar:EpochOf\(towns, operation\.loser\) \+ 1/, 'a flip is the one write that counts a town one more time');
});

test('the town document is replaced only if it still holds the bytes that were read', () => {
  const text = war();
  for (const name of ['ReadTownsRaw', 'SwapTowns', 'StorageOwner']) assert.ok(methods(text).includes(name), `${name} exists`);
  assert.match(body(text, 'ReadTownsRaw'), /_FormationStorage:Read\(/, 'reads go through the shared compare-and-swap storage boundary');
  assert.match(body(text, 'ReadTownsRaw'), /complete\(towns, raw\)|complete\(self:InitialTowns\(\), nil\)/, 'a reading hands out the decoded table and its exact bytes');
  const swap = body(text, 'SwapTowns');
  assert.match(swap, /_FormationStorage:Swap\(/, 'the swap is the storage boundary\'s compare-and-swap');
  assert.match(swap, /expected or ""/, 'a document that does not exist yet is created only if still absent');
  assert.match(swap, /2000000/, 'a changed document is reported as a conflict');
  assert.match(swap, /"OK"[^]*"CONFLICT"[^]*"FAILED"/, 'the caller tells success, conflict and failure apart');
  assert.match(body(text, 'ReadTowns'), /ReadTownsRaw/, 'every other reader sees the same bytes the settlement does');
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
  for (const name of ['Snapshot', 'Stamped', 'Combine', 'ChangedSince']) assert.ok(methods(text).includes(name), `${name} exists`);
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
  assert.match(body(battle(), 'OnUpdate'), /self\._T\.epochs = admission\.epochs/, 'the match room keeps them until the result');
  assert.match(body(battle(), 'OnUpdate'), /_FactionWarAttack:Settle\([^]*"HUMAN", nil, self\._T\.epochs\)/, 'and hands them to the settlement as the last argument');
});

test('a result whose towns changed hands since the pairing deducts nothing, even if a town was taken back', () => {
  const text = attack();
  assert.match(text, /method void Settle\(string matchKey, string homeTown, string awayTown, string homeResult, string kind, any complete, any snapshot\)/,
    'the stamp is an optional last argument, so older callers and probes keep working');
  assert.match(body(text, 'ChangedSince'), /EpochOf\(towns, homeTown\) ~= snapshot\.home or [^]*EpochOf\(towns, awayTown\) ~= snapshot\.away/,
    'a count that moved at all means the town changed hands, whoever owns it now');
  assert.match(body(text, 'ChangedSince'), /return false/, 'no stamp is the previous behaviour: the same-owner check still stands guard');
  const attempt = body(text, 'Attempt');
  const duplicate = attempt.indexOf('"DUPLICATE"');
  const exempt = attempt.indexOf('"EXEMPT"');
  const swap = attempt.indexOf('SwapTowns(');
  assert.ok(duplicate > -1 && exempt > duplicate, 'a repeat of an applied match is answered before the stamp is judged (its own flip moved the count)');
  assert.ok(exempt > -1 && swap > exempt, 'the exemption is decided before any document is built or written');
  assert.match(attempt.slice(attempt.indexOf('ChangedSince(')), /Finish\(operation, "EXEMPT", nil\)\s+return/, 'an exempt match finishes without touching storage');
  assert.match(attempt, /towns\[operation\.winner\]\.owner == towns\[operation\.loser\]\.owner/, 'the old same-owner check stays for results that carry no stamp');
  const settle = body(text, 'Settle');
  assert.match(settle, /snapshot = snapshot/, 'the operation remembers the stamp it was settled with');
  const finish = body(text, 'Finish');
  assert.match(finish, /applied and outcome\.flipped then _FactionWar:AnnounceFall/, 'only a settlement that flipped the town announces its fall');
  assert.match(finish, /EXEMPT/, 'an exempt result is an answer the room records like any other');
});

test('two settlements of one town race on the stored bytes: one swap wins, the other reads again', () => {
  const text = attack();
  const attempt = body(text, 'Attempt');
  assert.doesNotMatch(attempt, /WriteTowns\(/, 'a settlement never overwrites the document unconditionally');
  assert.equal(attempt.match(/SwapTowns\(/g).length, 1, 'ownership, strength and the match record are one swap');
  assert.match(attempt, /ReadTownsRaw\(function\(towns, raw\)/, 'the decision is made on the bytes the swap will name');
  assert.match(attempt, /SwapTowns\(raw, updated,/, 'the swap names exactly those bytes');
  assert.match(attempt, /result == "CONFLICT" then[^]*self:Retry\(operation, true\)/, 'a lost race reads again');
  assert.match(attempt, /self:Retry\(operation, false\)/, 'a failed write is retried on the slower clock');
  const retry = body(text, 'Retry');
  assert.match(retry, /operation\.conflicts/, 'lost races are counted apart from failures');
  assert.match(retry, /ConflictDelay\(/, 'a lost race reads again after a short, jittered pause');
  assert.match(retry, /"FAILED"/, 'both the lost races (by elapsed time) and the failures (by count) are bounded');
  assert.match(retry, /ConflictBudgetSeconds/, 'the lost races are bounded by time, see faction_war_review_contract.test.cjs');
  assert.match(text, /property number ConflictRetrySeconds = /);
});

test('experience and the match result never wait for the town settlement', () => {
  const session = source('RootDesk/MyDesk/Combat/BattleSession.mlua');
  assert.doesNotMatch(session, /_FactionWarAttack/, 'the battle session never asks the towns anything');
  assert.match(session, /_MonsterLevelStorage:Settle\(self\.HomeProfile, self\.MatchKey, self\._T\.deaths\.PLAYER\)/, 'the dead units of the home side are credited when the result is produced');
  assert.match(session, /_MonsterLevelStorage:Settle\(self\.AwayProfile, self\.MatchKey, self\._T\.deaths\.ENEMY\)/, 'and those of the away side');
  const update = body(battle(), 'OnUpdate');
  assert.ok(update.indexOf('PublishState(user.PlayerComponent.UserId, "RESULT_"') > -1 && update.indexOf('PublishState(user.PlayerComponent.UserId, "RESULT_"') < update.indexOf('_FactionWarAttack:Settle('),
    'every player is shown their win, loss or draw before the towns are touched');
});

test('a returning player is placed by the live board, which is read again before the departure town is trusted', () => {
  const text = attack();
  assert.match(text, /property integer LandingReadAttempts = \d+/, 'the number of tries is a property, not a magic number');
  const landing = body(text, 'ResolveLanding');
  assert.match(landing, /for attempt = 1, self\.LandingReadAttempts do/, 'an unreadable faction or town table is read again');
  assert.match(landing, /ReadFaction[^]*ReadTowns/, 'both come from storage on every return, never from the first delivery');
  assert.match(landing, /faction ~= nil and towns ~= nil then break/, 'only a missing answer is retried; "no faction" is an answer');
  assert.match(landing, /_FactionWar:Landing\(faction, preferred, towns\)/, 'ownership is judged on the board that was read');
  assert.match(landing, /self\._T\.outcomes\[matchKey\]/, 'who took a town still comes from the settlement outcome');
  assert.doesNotMatch(landing, /_T\.landing/, 'no landing is remembered between returns, so a retried return sees the newest owner');
});
