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

test('S3: the branches that used to return silently now say which one was taken', () => {
  const landing = source('RootDesk/MyDesk/Formations/FactionWarLanding.mlua');
  assert.match(body(landing, 'BattleDestination'), /\[VRF\]\[FactionWarAttack\] landing unreadable/);
  assert.match(body(ui(), 'ShowTownNotice'), /arrivalNotice = [^\n]*\n\s+log\("\[VRF\]\[FactionWar\] notice kept/, 'a notice kept for the destination town is logged');
});

test('S4: no document points at a report or worktree that is not in the repository; the README records what was verified', () => {
  const dangling = /the #10[78] report|#10[78] worktree|probe plan in the #10[78]/;
  const files = ['tests/README.md', ...fs.readdirSync('tests').filter(name => /^faction_war_.*\.(lua|cjs)$/.test(name)).map(name => `tests/${name}`)];
  for (const file of files) assert.doesNotMatch(source(file), dangling, `${file} has no dangling reference`);
  const readme = source('tests/README.md');
  assert.doesNotMatch(readme, /both probes are written but not yet run in Maker/, 'the #107 / #108 status is no longer "not yet run"');
  // The 2026-11-22 Maker run recorded in the #109 section covers the review-fix probes, so the sections that waited for it say it ran.
  for (const stale of [/none of this has run yet/, /were not recorded in this repository/, /review-fix re-run below should record them/, /record the date and the `\[VRF\]` evidence here/]) assert.doesNotMatch(readme, stale, `the README no longer carries the stale status ${stale}`);
  for (const heading of ['Capture, landing and eviction (#107)', 'Two matches contest one town (#108)', 'Review fixes for #107 and #108']) {
    const section = readme.match(new RegExp(`## ${heading.replace(/[()#]/g, '\\$&')}[^]*?(?=\n## )`))?.[0] || '';
    assert.ok(section.length > 0, `${heading} exists`);
    assert.match(section, /2026-11-22/, `${heading} says when it was verified`);
    assert.match(section, /#disconnect-and-reconnect-109/, `${heading} points at the record`);
  }
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
  // The HUD asks the rule instead of repeating the two capitals.
  assert.doesNotMatch(ui(), /"nanzih"|"yancheng"/, 'the HUD names no town');
  assert.match(body(ui(), 'ShowTownStatus'), /_FactionWarTownDocument:IsCapital\(town\)/);
  // Town status and NPC reads revalidate their own reply; placement revalidates its slot separately.
  assert.ok(methods(war()).includes('StillIn'));
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

// C1/C2 (concurrent checks, lost leases and retaken towns) run through Judge in the local suite and the Maker conquest probe.

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
  assert.doesNotMatch(vacate, /CanCancel/, 'storage transition eligibility does not decide if a matchup exists');
  const cancel = body(text, 'CancelForUser');
  assert.match(cancel, /self:OpponentFound\(ticket\)[^]*CANCEL_MATCH_FOUND[^]*return end[^]*self:CancelMatching/, 'player cancellation uses the same recognized pairing boundary');
  assert.match(body(text, 'OpponentFound'), /ticket\.guardPairing[^]*_MatchFlowState:IsEntering/, 'covers a guard claim and SAVING onward');
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

test('ADR 0016: glossary, supersession notes and shared battle landing agree on origin ownership', () => {
  const glossary = source('CONTEXT.md');
  assert.match(glossary, /\*\*奪城\*\*:\n[^\n]*不會因此進入新城[^\n]*回出發城[^\n]*不屬己方就回主城/);
  for (const term of ['登入落點', '過期戰果']) {
    assert.match(glossary, new RegExp(`\\*\\*${term}\\*\\*:\\n[^\\n]*出發城[^\\n]*回出發城[^\\n]*回己方主城`));
  }
  assert.match(adr('0016'), /每個人返回時都回出發城[^\n]*不屬己方，就回己方主城/);
  assert.match(adr('0016'), /LandingWaitSeconds/);
  for (const prefix of ['0010', '0012', '0013', '0014']) {
    assert.match(adr(prefix), /由 ADR 0016 取代/, `ADR ${prefix} flags the superseded landing rule`);
  }

  const landing = source('RootDesk/MyDesk/Formations/FactionWarLanding.mlua');
  const destination = body(landing, 'BattleDestination').replace(/--.*$/gm, '');
  assert.match(destination, /IsSettling\(matchKey\)[^]*_FactionWarTownDocument:Landing\(faction, origin, board\)/);
  assert.doesNotMatch(destination, /outcome\.(flipped|winner|loser)/, 'capture fields cannot pick where to land');
  const rule = body(source('RootDesk/MyDesk/Formations/FactionWarTownDocument.mlua'), 'Landing');
  assert.match(rule, /\.owner == faction then return[^]*return self:CapitalOf\(faction\)/);
  assert.match(body(landing, 'PlaceAfterBattle'), /self:BattleDestination\([^]*if trigger\.kind == "RETURN" then return trigger\.move\(destination\)/);
});

test('C6: the return waits through the document conflict budget', () => {
  const doc = source('RootDesk/MyDesk/Formations/FactionWarTownDocument.mlua');
  const landing = source('RootDesk/MyDesk/Formations/FactionWarLanding.mlua');
  const landingWait = Number(landing.match(/property number LandingWaitSeconds = (\d+)/)[1]);
  const budget = Number(doc.match(/property number ConflictBudgetSeconds = (\d+)/)[1]);
  assert.ok(landingWait >= budget, 'a returning player outwaits a contended settlement');
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
  assert.match(e2e, /IsJudging/, 'C1: the second request while a check runs');
  assert.match(e2e, /EnforceLeaseSeconds/, 'C1: an old slot is taken over');
  assert.match(e2e, /Judge\([^]*retaken-town check finished/, 'C2: Judge on a board that was retaken');
  assert.match(probe('faction_war_contest_e2e_runtime_probe.lua'), /snapshot/, 'C5: the tickets hold their first reading');
});
