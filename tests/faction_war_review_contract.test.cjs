const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');

// Structural contract for the review of #107 / #108 (spec #103): standards findings S1-S7 and spec findings C1-C6.
// The behaviour is proven in Maker by the probes this file names in its last test (see tests/README.md, "Review fixes");
// these tests pin the seams those probes drive, and the documents that have to agree with the code.
const source = path => fs.readFileSync(path, 'utf8').replace(/\r\n/g, '\n');
const methods = text => [...text.matchAll(/^    method \w+ (\w+)\(/gm)].map(m => m[1]);
const body = (text, name) => text.match(new RegExp(`method \\w+ ${name}\\([^]*?(?=\\n    @|\\n    method|\\n    handler|\\nend)`))?.[0] || '';
const war = () => source('RootDesk/MyDesk/Formations/FactionWar.mlua');
const attack = () => source('RootDesk/MyDesk/Formations/FactionWarAttack.mlua');
const ui = () => source('RootDesk/MyDesk/Formations/FactionWarUI.mlua');
const storage = () => source('RootDesk/MyDesk/Formations/FormationStorage.mlua');
const flow = () => source('RootDesk/MyDesk/Matchmaking/MatchFlow.mlua');
const adr = prefix => source(`docs/adr/${fs.readdirSync('docs/adr').find(name => name.startsWith(prefix))}`);

// Every early `return false` of `text` has a [VRF] log on the line before it (or on its own line).
const silentReturns = text => {
  const lines = text.split('\n');
  const silent = [];
  lines.forEach((line, index) => {
    if (!/\breturn false\b/.test(line)) return;
    if (/\[VRF\]/.test(line) || /\[VRF\]/.test(lines[index - 1] || '')) return;
    silent.push(line.trim());
  });
  return silent;
};

// ---- S: standards ------------------------------------------------------------------------------------------------------------

test('S1: the ADRs speak the glossary: 換旗次數 and 過期戰果, never 世代 / 失效戰果 / 免扣 as a name', () => {
  const glossary = source('CONTEXT.md');
  const avoided = term => {
    const entry = glossary.match(new RegExp(`\\*\\*${term}\\*\\*:[^]*?_Avoid_: ([^\\n]+)`));
    assert.ok(entry, `${term} is in the glossary`);
    return entry[1].replace(/（.*$/, '').split('、').map(word => word.trim()).filter(Boolean);
  };
  // The glossary's own _Avoid_ lists, plus the two spellings the review found in ADR 0013 (免扣 covers 免扣兵 and 免扣場次).
  const forbidden = [...avoided('換旗次數'), ...avoided('過期戰果'), '失效戰果', '免扣'];
  for (const prefix of ['0010', '0011', '0012', '0013']) {
    const text = adr(prefix);
    for (const word of forbidden) assert.ok(!text.includes(word), `ADR ${prefix} does not use "${word}" (the glossary names it)`);
  }
  assert.match(adr('0013'), /過期戰果/, 'ADR 0013 names the concept the way the glossary does');
  assert.match(adr('0012'), /換旗次數/, 'ADR 0012 calls the per-town count 換旗次數');
});

test('S2: StorageOwner is a pure string builder, so it carries no ExecSpace', () => {
  assert.ok(methods(war()).includes('StorageOwner'));
  assert.doesNotMatch(war(), /@ExecSpace\("\w+"\)\n    method string StorageOwner\(/, 'pure helpers (IsTown, CapitalOf, EpochOf, StorageOwner) are untagged');
});

test('S3: the branches that used to return silently now say which one was taken', () => {
  assert.deepEqual(silentReturns(body(war(), 'Evict')), [], 'every early return of Evict logs a [VRF] line first');
  assert.match(body(attack(), 'LandingFor'), /origin == "" or not isvalid\(player\) then\n\s+log\("\[VRF\]\[FactionWarAttack\] landing skipped/, 'LandingFor logs why it returns the departure town untouched');
  assert.match(body(ui(), 'ShowTownNotice'), /arrivalNotice = [^\n]*\n\s+log\("\[VRF\]\[FactionWar\] notice kept/, 'a notice kept for the destination town is logged');
});

test('S4: no document points at a report or worktree that is not in the repository; the README records what was verified', () => {
  const dangling = /the #10[78] report|#10[78] worktree|probe plan in the #10[78]/;
  const files = ['tests/README.md', ...fs.readdirSync('tests').filter(name => /^faction_war_.*\.(lua|cjs)$/.test(name)).map(name => `tests/${name}`)];
  for (const file of files) assert.doesNotMatch(source(file), dangling, `${file} has no dangling reference`);
  const readme = source('tests/README.md');
  assert.doesNotMatch(readme, /both probes are written but not yet run in Maker/, 'the #107 / #108 status is no longer "not yet run"');
  assert.match(readme, /REDELIVER[^]*?room is recycled/, 'the README says why redelivery cannot run after RETURN');
  const e2e = source('tests/faction_war_contest_e2e_runtime_probe.lua');
  assert.doesNotMatch(e2e, /before or after RETURN/, 'the e2e header no longer claims STEP 5 can run after RETURN');
  assert.match(e2e, /REDELIVER[^\n]*BEFORE RETURN|BEFORE (STEP 4|RETURN)/, 'it says STEP 5 runs before RETURN');
});

test('S5: ADR 0010 says only snapshot is new on Settle (complete was already there)', () => {
  const text = adr('0010');
  assert.doesNotMatch(text, /多兩個選填參數/, 'two new parameters is no longer claimed');
  assert.match(text, /snapshot/);
  assert.match(attack(), /method void Settle\(string matchKey, string homeTown, string awayTown, string homeResult, string kind, any complete, any snapshot\)/, 'the signature itself is unchanged');
});

test('S6: a settlement keeps no attempts counter that nothing reads', () => {
  const text = attack();
  assert.doesNotMatch(text, /\battempts = 0\b|operation\.attempts/, 'conflicts and failures are the bounds now');
});

test('S7: shared rules are written once', () => {
  const text = attack();
  // The flip count comes from the one default-zero rule.
  assert.match(body(text, 'Attempt'), /e = _FactionWar:EpochOf\(towns, operation\.loser\) \+ 1/);
  assert.doesNotMatch(body(text, 'Attempt'), /\.e or 0/, 'no second spelling of "a missing count is zero"');
  // One definition of the full strength, owned by the module that owns the document rules.
  assert.match(war(), /property integer FullStrength = 100\b/);
  assert.doesNotMatch(text, /property integer FullStrength/, 'the attack module reads it from FactionWar');
  assert.match(body(text, 'Attempt'), /strength = _FactionWar\.FullStrength/);
  for (const name of ['DecodeTowns', 'InitialTowns']) {
    assert.doesNotMatch(body(war(), name), /\b100\b/, `${name} has no literal 100`);
    assert.match(body(war(), name), /self\.FullStrength/, `${name} uses the constant`);
  }
  // The HUD asks the rule instead of repeating the two capitals.
  assert.doesNotMatch(ui(), /"nanzih"|"yancheng"/, 'the HUD names no town');
  assert.match(body(ui(), 'ShowTownStatus'), /_FactionWarAttack:IsCapital\(town\)/);
  // One bounded poll loop.
  assert.ok(methods(text).includes('WaitWhile'));
  assert.match(body(text, 'Await'), /self:WaitWhile\(/);
  assert.match(body(text, 'LandingFor'), /self:WaitWhile\(/);
  assert.doesNotMatch(body(text, 'LandingFor'), /wait\(0\.1\)/, 'LandingFor no longer repeats the loop');
  // One "is the player still in that town" guard, used by the town status, the eviction and the NPC reads.
  assert.ok(methods(war()).includes('StillIn'));
  assert.match(body(war(), 'Evict'), /self:StillIn\(/);
  assert.match(body(war(), 'RequestTownStatus'), /self:StillIn\(/);
  assert.match(body(text, 'Resolve'), /_FactionWar:StillIn\(/);
  assert.doesNotMatch(text, /method boolean StillHere\(/, 'the attack module had its own copy');
  // One Maker fault-injection block for the two compare-and-swap writers; the storage boundary's keys are owners, not profiles.
  const guard = storage();
  assert.ok(methods(guard).includes('MakerWriteFault'));
  for (const name of ['Write', 'Swap']) {
    assert.match(body(guard, name), /self:MakerWriteFault\(\)/, `${name} takes its fault from the shared helper`);
    assert.doesNotMatch(body(guard, name), /_T\.writeDelay|_T\.writeFailures/, `${name} no longer copies the injection block`);
  }
  assert.match(guard, /method void Read\(string owner, string key, any complete\)/);
  assert.match(guard, /method void Write\(string owner, string key, string expected, string raw, any complete\)/);
});

// ---- C: spec correctness -----------------------------------------------------------------------------------------------------

test('C1: a check that arrives while another runs is not dropped, and the running slot is always released', () => {
  const text = war();
  assert.match(text, /property number EnforceLeaseSeconds = \d+/, 'a slot that was never released expires');
  const enforce = body(text, 'Enforce');
  assert.match(enforce, /running\.again = town/, 'a request that finds a check running marks it to run again');
  assert.doesNotMatch(enforce, /or self\._T\.evicting\[userId\] then return end/, 'it is no longer simply discarded');
  assert.match(enforce, /EnforceLeaseSeconds \* 1000/, 'an old slot is taken over');
  assert.match(enforce, /pcall\(function\(\) self:Evict\(/, 'an error inside the check cannot keep the slot');
  assert.ok(enforce.indexOf('pcall(') < enforce.indexOf('self._T.evicting[userId] = nil\n'), 'the slot is cleared after the guarded call');
  assert.match(enforce, /self\._T\.evicting\[userId\] ~= check then return end/, 'an abandoned or departed check does nothing late');
  assert.match(enforce, /check\.again ~= nil and self:StillIn\(player, userId, check\.again\) then self:Recheck\(userId, check\.again\)/, 'the marked request runs once the check is over, unless the player already left that town');
  assert.ok(methods(text).includes('Recheck'));
  assert.match(body(text, 'Recheck'), /ReadTowns\([^]*self:Enforce\(userId, town, towns\)/, 'the second look is taken on a freshly read board, not on the one the request carried');
  assert.match(text, /handler HandleUserLeaveEvent[^]*evicting\[event\.UserId\] = nil/, 'a leaver frees the slot');
});

test('C2: a player is moved only on the board read after the last yield, so a town taken back keeps its people', () => {
  const evict = body(war(), 'Evict');
  const vacate = evict.indexOf('_MatchFlow:Vacate(userId)');
  const reread = evict.indexOf('ReadTowns(done)');
  const second = evict.indexOf('self:Landing(faction, town, live)');
  const move = evict.indexOf('self:Move(player, destination)');
  assert.ok(vacate > -1 && reread > vacate, 'the board is read again after the cancellation has yielded');
  assert.ok(second > reread && move > second, 'the destination is judged on that board, then the player moves');
  assert.match(evict, /live == nil then[^]*return false/, 'a board that cannot be read again moves nobody');
  assert.match(evict, /if destination == town then[^]*holds it again[^]*return false/, 'a retaken town keeps the player');
  assert.ok(evict.indexOf('self:StillIn(') > reread && evict.indexOf('self:StillIn(') < move, 'the player is checked once more after the last yield');
});

test('C3: Vacate tries again a bounded number of times for the passing ticket states', () => {
  const text = flow();
  assert.match(text, /property integer VacateAttempts = \d+/);
  assert.match(text, /property number VacateRetrySeconds = /);
  const vacate = body(text, 'Vacate');
  assert.match(vacate, /for attempt = 1, self\.VacateAttempts do/, 'the number of tries is bounded');
  assert.match(vacate, /wait\(self\.VacateRetrySeconds\)/, 'with a pause between them');
  assert.match(vacate, /ticket\.data ~= nil and not ticket\.cancelling and not self\._T\.busy\[userId\]/, 'a cancellation is only started when nothing else owns the ticket');
  assert.doesNotMatch(vacate, /ticket\.data == nil or not/, 'a ticket without data is no longer a permanent refusal');
  assert.match(vacate, /vacate gave up/, 'giving up is logged');
  assert.match(vacate, /vacate cancelled=true/, 'the line the conquest e2e reads is kept');
});

test('C4: Vacate cancels only a ticket still waiting for an opponent; a matched one (SAVING onward) keeps its place', () => {
  const text = flow();
  assert.ok(methods(text).includes('IsWaiting'));
  assert.doesNotMatch(text, /@ExecSpace\("\w+"\)\n    method boolean IsWaiting\(/, 'the waiting rule is a pure function of the ticket, so it is untagged');
  const waiting = body(text, 'IsWaiting').replace(/--.*$/gm, '');
  for (const state of ['QUEUED', 'RENEWING', 'QUEUE_ERROR']) assert.match(waiting, new RegExp(state), `${state} is waiting`);
  for (const state of ['SAVING', 'COMMITTING', 'TRANSFER', 'IN_ROOM']) assert.doesNotMatch(waiting, new RegExp(state), `${state} is a match`);
  const vacate = body(text, 'Vacate').replace(/--.*$/gm, '');
  assert.match(vacate, /not self:IsWaiting\(ticket\)[^]*vacate held[^]*return false/, 'a matched ticket is refused without a cancellation');
  assert.doesNotMatch(vacate, /CanCancel/, 'CanCancel also allows SAVING (the player\'s own button), so it does not decide here');
  // The player's own cancel button keeps its reach (ADR 0011's accepted gap).
  assert.match(body(source('RootDesk/MyDesk/Formations/FormationHandoff.mlua'), 'CanCancel'), /state == "SAVING"/);
});

test('C5: the war board is read as soon as the pairing is known, before any wait that precedes the seal', () => {
  const matched = body(flow(), 'Matched');
  const lookup = matched.indexOf('QueueAdapter():Lookup(ticket.data.profile)');
  const stamp = matched.indexOf('_FactionWarAttack:Snapshot(matched)');
  const deferred = matched.indexOf('matched response deferred until cancellation settles');
  const published = matched.indexOf('PublishState(userId, "MATCHED")');
  const stamped = matched.indexOf('_FactionWarAttack:Stamped(');
  const sealed = matched.indexOf('_FormationHandoff:Seal(');
  assert.ok(lookup > -1 && stamp > lookup, 'the pairing is looked up, then stamped');
  assert.ok(stamp < deferred && stamp < published && stamp < sealed, 'a cancellation that is still answering or the save can no longer delay the reading');
  assert.ok(stamped > deferred && stamped < sealed, 'the sealed pairing is still the stamped copy');
  assert.match(matched, /ticket\.snapshot == nil then ticket\.snapshot = /, 'a match that resumes keeps its first reading');
  assert.match(matched, /ticket\.data == nil or ticket\.data\.state ~= "SAVING" then return end[^]*matched response deferred/, 'the ticket is re-checked after the reading yields, before the cancellation check');
});

test('C6: a lost race backs off with jitter and is bounded by time, not by a count a crowd can exhaust', () => {
  const text = attack();
  for (const name of ['ConflictRetrySeconds', 'ConflictBackoffCap', 'ConflictBudgetSeconds']) assert.match(text, new RegExp(`property number ${name} = `), `${name} is a property`);
  assert.doesNotMatch(text, /SettleConflicts/, 'the old count of ten is gone');
  assert.ok(methods(text).includes('ConflictDelay'));
  assert.doesNotMatch(text, /@ExecSpace\("\w+"\)\n    method number ConflictDelay\(/, 'the delay rule is pure');
  assert.match(body(text, 'ConflictDelay'), /2 \^ \(conflicts - 1\)/, 'the pause doubles');
  assert.match(body(text, 'ConflictDelay'), /math\.min\(self\.ConflictBackoffCap/, 'up to a cap');
  assert.match(body(text, 'ConflictDelay'), /\(0\.5 \+ 0\.5 \* roll\)/, 'with the upper half jittered');
  const retry = body(text, 'Retry');
  assert.match(retry, /ConflictDelay\(operation\.conflicts, _UtilLogic:RandomDouble\(\)\)/, 'every lost race draws its own jitter');
  assert.match(retry, /ConflictBudgetSeconds/, 'the bound is elapsed time');
  assert.match(retry, /\[VRF\]\[FactionWarAttack\] settle gave up/, 'giving up says so');
  assert.match(body(text, 'Settle'), /started = DateTime\.UtcNow\.Elapsed/, 'the clock starts with the settlement');
  assert.match(body(text, 'Settle'), /self\._T\.settling\[matchKey\] = operation/, 'a running settlement can be observed (and still reads as "settling")');
  assert.match(text, /property number LandingWaitSeconds = (\d+)/, 'the landing wait is a property');
  const landingWait = Number(text.match(/property number LandingWaitSeconds = (\d+)/)[1]);
  const budget = Number(text.match(/property number ConflictBudgetSeconds = (\d+)/)[1]);
  assert.ok(landingWait >= budget, 'a returning player outwaits a contended settlement, so the conqueror is placed with the finished outcome');
  assert.match(body(text, 'Finish'), /conflicts = operation\.conflicts/, 'the outcome says how often the settlement lost a race');
});

test('every C item has a probe step in the Maker probes', () => {
  const probe = name => source(`tests/${name}`);
  const conquest = probe('faction_war_conquest_runtime_probe.lua');
  assert.match(conquest, /Vacate/, 'C3 / C4: Vacate on a matched ticket and on passing states');
  assert.match(conquest, /"SAVING"/, 'C4: a matched ticket is refused');
  const contest = probe('faction_war_contest_runtime_probe.lua');
  assert.match(contest, /ConflictDelay/, 'C6: the delay rule');
  assert.match(contest, /conflicts > 10/, 'C6: a settlement that lost more races than the old bound still lands once');
  assert.match(contest, /settle gave up|"FAILED"[^]*budget/i, 'C6: the time budget');
  const e2e = probe('faction_war_conquest_e2e_runtime_probe.lua');
  assert.match(e2e, /EVICTRACE/, 'C1 / C2: the check race and the double flip');
  assert.match(e2e, /enforce queued|evicting/, 'C1: the second request while a check runs');
  assert.match(e2e, /EnforceLeaseSeconds/, 'C1: an old slot is taken over');
  assert.match(e2e, /Evict\(/, 'C2: Evict on a board that was retaken');
  assert.match(probe('faction_war_contest_e2e_runtime_probe.lua'), /snapshot/, 'C5: the tickets hold their first reading');
});
