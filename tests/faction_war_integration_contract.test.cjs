const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');

// Structural contract for #110 (spec #103, 整合與發布環境雙帳號驗收): no new game rule, so this file pins the shape of the integration probes
// (own profiles, numbered steps, pass lines, cleanup, the guard clock), the production code the probes mirror because a script cannot call it
// directly (a Server method reads senderUserId), the log lines the probes tell the reader to look for, and the published-environment runbook.
// The behaviour itself is proven in Maker by the faction_war_integration_*_runtime_probe.lua files (see tests/README.md, "War integration (#110)").
const source = path => fs.readFileSync(path, 'utf8').replace(/\r\n/g, '\n');
const body = (text, name) => text.match(new RegExp(`(?:method|handler) \\w+ ${name}\\([^]*?(?=\\n    @|\\n    method|\\n    handler|\\nend)`))?.[0] || '';
// The tag is the line right above a method; pure helpers carry none.
const tag = (text, name) => text.match(new RegExp(`(@ExecSpace\\("\\w+"\\)\\n)?    method \\w+ ${name}\\(`))?.[1] || '';
const war = () => source('RootDesk/MyDesk/Formations/FactionWar.mlua');
const attack = () => source('RootDesk/MyDesk/Formations/FactionWarAttack.mlua');
const flow = () => source('RootDesk/MyDesk/Matchmaking/MatchFlow.mlua');
// The calls must appear in this order (a mirror in a probe is only honest while the production body still does them in this order).
const inOrder = (text, patterns, what) => {
  let at = 0;
  for (const pattern of patterns) {
    const found = text.slice(at).search(pattern);
    assert.ok(found >= 0, `${what}: ${pattern} appears after the previous call`);
    at += found + 1;
  }
};

// ---- the probes ---------------------------------------------------------------------------------------------------------------

// Profile codes wp2631-wp2639 belong to #110; wp2601-wp2626 are taken by the probes before it.
const OWN_PROFILES = Array.from({ length: 9 }, (_, index) => `wp${2631 + index}`);
const probes = {
  'faction_war_integration_journey_e2e_runtime_probe.lua': {
    prefix: 'Journey', joins: 6, guard: 600, profiles: ['wp2631', 'wp2632', 'wp2633', 'wp2634', 'wp2635'],
    steps: ['SEED', 'SETUP', 'ENTRY', 'GATE', 'OPTIONS', 'CANCEL', 'QUEUE', 'CAPTURE', 'RETURN', 'LANDING', 'RELOGIN', 'CLEANUP'],
    lines: ['SETUP PASS', 'ENTRY PASS', 'GATE PASS', 'OPTIONS PASS', 'CANCEL PASS', 'CAPTURE PASS', 'LANDING PASS', 'RELOGIN PASS', 'JOURNEY PASS'],
  },
  'faction_war_integration_capital_e2e_runtime_probe.lua': {
    prefix: 'Capital', joins: 2, guard: 10, profiles: ['wp2636', 'wp2637'],
    steps: ['SEED', 'SETUP', 'QUEUE1', 'ROOM1', 'CHECK1', 'QUEUE2', 'ROOM2', 'CHECK2', 'QUEUE3', 'ROOM3', 'CHECK3', 'CLEANUP'],
    lines: ['SETUP PASS', 'CAPITAL PASS', 'LOSS PASS', 'COUNTER PASS', 'E2E PASS'],
  },
  'faction_war_integration_interleave_e2e_runtime_probe.lua': {
    prefix: 'Interleave', joins: 2, guard: 10, profiles: ['wp2638', 'wp2639'],
    steps: ['SEED', 'SETUP', 'TRIAL1', 'ROOM1', 'CHECK1', 'TRIAL2', 'ROOM2', 'CHECK2', 'TRIAL3', 'ROOM3', 'CHECK3', 'TRIAL4', 'ROOM4', 'CHECK4', 'CLEANUP'],
    lines: ['SETUP PASS', 'RACE1 PASS', 'RACE2 PASS', 'RACE3 PASS', 'RACE4 PASS', 'E2E PASS'],
  },
};

const headerSteps = text => [...text.match(/^(?:--.*\n)+/)[0].matchAll(/^--\s+(\d+)\s+([A-Z][A-Z0-9_]*)/gm)].map(m => [Number(m[1]), m[2]]);
// A branch may serve several steps ("STEP == 4 or STEP == 7 then"): the set of numbers the code tests for.
const codeSteps = text => [...new Set([...text.matchAll(/STEP == (\d+)/g)].map(m => Number(m[1])))].sort((a, b) => a - b);

test('the #110 probes use their own profiles, say how many joins they cost, number their steps and end in a pass line', () => {
  for (const [name, spec] of Object.entries(probes)) {
    const text = source(`tests/${name}`);
    assert.match(text, /^-- /, `${name} starts with its instructions`);
    assert.ok(text.includes(`[VRF][${spec.prefix}]`), `${name} uses its own log prefix`);
    assert.match(text, /Expected \[VRF\] lines[^\n]*War integration \(#110\)/, `${name} says where the expected lines are`);
    for (const used of text.match(/wp26\d\d/g) || []) assert.ok(OWN_PROFILES.includes(used), `${name} uses only wp2631-wp2639, found ${used}`);
    for (const profile of spec.profiles) assert.ok(text.includes(profile), `${name} drives ${profile}`);
    assert.match(text, new RegExp(`Joins: ${spec.joins} of the 10 virtual players a Play allows`), `${name} says it uses ${spec.joins} joins (kicked players count too)`);
    assert.match(text, /^local STEP = 1$/m, `${name} is stepped by one variable`);
    const header = headerSteps(text);
    assert.deepEqual(header.map(s => s[1]), spec.steps, `${name} numbers the steps ${spec.steps.join(', ')}`);
    assert.deepEqual(header.map(s => s[0]), spec.steps.map((_, index) => index + 1), `${name} numbers them from 1 without gaps`);
    assert.deepEqual(codeSteps(text), header.map(s => s[0]), `${name} implements every numbered step`);
    for (const line of spec.lines) assert.ok(text.includes(`[VRF][${spec.prefix}] ${line}`), `${name} announces ${line}`);
    assert.match(text, /if not ok then log_error\("\[VRF\]\[\w+\] STEP "/, `${name} reports a failed step`);
    // The cleanup step is the last one: it puts the guard clock back and deletes the real town storage the match rooms wrote.
    const cleanup = text.slice(text.lastIndexOf(`STEP == ${spec.steps.length} then`));
    assert.match(cleanup, /_FactionWarGuard\.WaitSeconds = 10\b/, `${name} puts the guard clock back in CLEANUP`);
    assert.match(cleanup, /DeleteGlobalDataStorageAndWait\(_FactionWarTownDocument\.TownStorageName\)/, `${name} deletes the real town storage in CLEANUP`);
    assert.match(text, new RegExp(`_FactionWarGuard\\.WaitSeconds = ${spec.guard}\\b`), `${name} sets the guard clock it needs (${spec.guard} s) explicitly`);
    // The probes that start before the players exist wipe what an earlier run left, or a stale last town would place a fresh login.
    assert.match(text, /DeleteAndWait\(_FactionWar\.TownKey\)/, `${name} wipes the last-town key before the virtual players log in`);
  }
});

// ---- what a script cannot call is mirrored, and the mirror is pinned ---------------------------------------------------------------

const probeText = name => source(`tests/${name}`);
const luaFunction = (text, name) => text.match(new RegExp(`local function ${name}\\([^]*?\\n(?=local function |local ok, reason)`))?.[0] || '';
const journey = () => probeText('faction_war_integration_journey_e2e_runtime_probe.lua');

test('RequestEntry, RequestGate and OptionsFor read senderUserId, so the journey mirrors their bodies call for call', () => {
  const entry = body(war(), 'RequestEntry');
  const gate = body(war(), 'RequestGate');
  const options = body(attack(), 'OptionsFor');
  for (const [name, text] of [['RequestEntry', entry], ['RequestGate', gate]]) {
    assert.match(tag(war(), name), /@ExecSpace\("Server"\)/, `${name} is a Server method: a script cannot give it a sender`);
    assert.match(text, /senderUserId/, `${name} reads the sender`);
  }
  assert.match(body(attack(), 'RequestOptions'), /OptionsFor\(senderUserId\)/, 'the NPC dialog hands the sender to OptionsFor, which a script can call');
  assert.match(body(attack(), 'RequestAttack'), /AttackFor\(senderUserId, target\)/, 'and the attack request is AttackFor, which a script calls as it is');
  // The production order, then the same order in the probe's helper.
  inOrder(entry, [/CanEnterFromLobby\(player, userId\)/, /self\._T\.pending\[userId\] = player/, /self:ReadFaction\(profile/, /_FormationStorage:Write\(profile, self\.FactionKey, "", choice/, /self:EnterFrontline\(userId, player, choice\)/], 'RequestEntry');
  inOrder(gate, [/self:FindGate\(origin, destination\)/, /self:NearGate\(player, gate\)/, /_FactionWarAttack:IsEngaged\(userId\)/, /self:ReadFaction\(/, /_FactionWarTownDocument:Read\(/, /_FactionWarTownDocument:CanPass\(faction, origin, destination, towns\)/, /_FactionWarLanding:Judge\(userId, \{ kind = "CHECK", town = origin, board = towns \}\)/, /self:Move\(player, destination\)/], 'RequestGate');
  inOrder(options, [/self:Resolve\(/, /towns\[town\]\.owner ~= faction/, /"NOT_OWNED"/, /self:IsEngaged\(userId\)/, /self:Targets\(town, faction, towns\)/, /engaged and "ENGAGED" or "READY"/], 'OptionsFor');
  const text = journey();
  inOrder(luaFunction(text, 'entry'), [/CanEnterFromLobby\(user, userId\)/, /_T\.pending\[userId\] = user/, /readFaction\(profile\)/, /_FormationStorage:Write\(profile, _FactionWar\.FactionKey, "", choice/, /_FactionWar:EnterFrontline\(userId, user, faction\)/], 'the journey entry()');
  inOrder(luaFunction(text, 'gate'), [/_FactionWar:FindGate\(origin, destination\)/, /_FactionWar:NearGate\(user, door\)/, /_FactionWarAttack:IsEngaged\(userId\)/, /readFaction\(/, /readTowns\(\)/, /_FactionWarTownDocument:CanPass\(faction, origin, destination, towns\)/, /_FactionWarLanding:Judge\(userId, \{ kind = "CHECK", town = origin, board = towns \}\)/, /_FactionWar:Move\(user, destination\)/], 'the journey gate()');
  inOrder(luaFunction(text, 'options'), [/towns\[town\]\.owner ~= faction/, /"NOT_OWNED"/, /_FactionWarAttack:IsEngaged\(id\(user\)\) and "ENGAGED" or "READY"/, /_FactionWarAttack:Targets\(town, faction, towns\)/], 'the journey options()');
  // Everything a script can call, it calls as it is.
  for (const call of ['_FactionWarAttack:AttackFor(', '_MatchFlow:CancelForUser(', '_UserService:KickUser(', '_FactionWar:EnterFrontline(']) assert.ok(text.includes(call), `the journey calls ${call}`);
});

// A probe that cannot run in this repository must not invent an API: every method it calls and every global service it names is one the production
// code defines or one an earlier probe (run in Maker) already used. A name that is new to both needs a reason here.
const allProductionText = () => {
  const out = [];
  const walk = dir => fs.readdirSync(dir, { withFileTypes: true }).forEach(entry => {
    const path = `${dir}/${entry.name}`;
    if (entry.isDirectory()) walk(path); else if (entry.name.endsWith('.mlua')) out.push(source(path));
  });
  walk('RootDesk');
  return out.join('\n');
};
const earlierProbeText = () => fs.readdirSync('tests').filter(name => name.endsWith('.lua') && !name.startsWith('faction_war_integration_')).map(name => source(`tests/${name}`)).join('\n');
const NEW_ENGINE_NAMES = {};

test('the #110 probes call only methods and services that the production code or an earlier Maker probe already uses', () => {
  const known = new Set([...allProductionText().matchAll(/(?:method|handler) \w+ (\w+)\(/g)].map(m => m[1]));
  // Engine methods count when production code or a probe that ran in Maker already calls them.
  for (const m of earlierProbeText().matchAll(/[:.](\w+)\(/g)) known.add(m[1]);
  for (const m of allProductionText().matchAll(/[:.](\w+)\(/g)) known.add(m[1]);
  const services = new Set([...allProductionText().matchAll(/\b(_[A-Z]\w+)\b/g), ...earlierProbeText().matchAll(/\b(_[A-Z]\w+)\b/g)].map(m => m[1]));
  for (const name of Object.keys(probes)) {
    const text = probeText(name);
    for (const m of text.matchAll(/:(\w+)\(/g)) assert.ok(known.has(m[1]) || NEW_ENGINE_NAMES[m[1]], `${name} calls :${m[1]}( which nothing else uses (add it to NEW_ENGINE_NAMES with the reason if it is real)`);
    for (const m of text.matchAll(/\b(_[A-Z]\w+)\b/g)) assert.ok(services.has(m[1]), `${name} names ${m[1]} which nothing else uses`);
  }
});

// ---- the capital and counterattack guard fights ------------------------------------------------------------------------------------

const capital = () => probeText('faction_war_integration_capital_e2e_runtime_probe.lua');

test('the capital probe forces its results, says so, and runs the board the issue describes', () => {
  const text = capital();
  assert.match(text, /THE FIGHTS ARE NOT PLAYED/, 'the header says the results are forced, not played');
  assert.match(text, /ApplyResolvedDamage\(99999, nil, false, "", 0, 0\)/, 'a fight ends by killing one side with the production damage call');
  assert.match(text, /plan == "WIN" and "ENEMY" or "PLAYER"/, 'a forced win kills the guard, a forced loss kills the human');
  assert.match(text, /ROOM_PLAN = \{ \[4\] = "WIN", \[7\] = "LOSE", \[10\] = "WIN" \}/, 'a capital win, a guard loss, then the counterattack win, in this order');
  // B owns only Yancheng; Gushan is A at strength 10.
  assert.match(text, /towns\.gushan\.owner = "A"\n\s+towns\.gushan\.strength = 10/, 'Gushan is seeded A at 10');
  assert.match(text, /queue\("CAPITAL P gushan -> yancheng", p, "yancheng"\)/, 'the A player attacks the enemy capital');
  assert.match(text, /queue\("COUNTER Q yancheng -> gushan", q, "gushan"\)/, 'the B player counterattacks from its only town');
  assert.match(text, /string\.sub\(key, 1, 6\) == "guard-"/, 'every fight is a guard match');
  assert.match(text, /EpochOf\(towns, "gushan"\) == 2/, 'the flip is counted');
  assert.match(text, /a lost guard fight changes nothing/, 'a lost guard fight is asserted to change nothing');
});

test('the capital probe forces results through seams that exist: the side labels, the damage call and the rules that make each fight a no-change or a flip', () => {
  const session = source('RootDesk/MyDesk/Combat/BattleSession.mlua');
  assert.match(session, /local faction = side == 1 and "PLAYER" or "ENEMY"/, 'the home side is PLAYER and the away side is ENEMY');
  assert.match(source('RootDesk/MyDesk/Combat/BattleUnit.mlua'), /method void ApplyResolvedDamage\(integer amount, Entity attacker, boolean allowHitStop, string hitEffectRUID, number hitEffectOffsetX, number hitEffectOffsetY\)/, 'the damage call has the signature the probe passes');
  assert.match(body(attack(), 'Finish'), /AnnounceFall\(outcome\.loser, outcome\.owner\)/, 'the fall is announced to the static room');
  assert.match(body(war(), 'SweepFallen'), /_FactionWarLanding:Judge\(userId, \{ kind = "CHECK", town = town, board = towns \}\)/, 'and the idle player of the fallen town is enforced home');
});

// ---- the human-versus-guard timeout race ---------------------------------------------------------------------------------------------

const race = () => probeText('faction_war_integration_interleave_e2e_runtime_probe.lua');

test('the race probe queues the opposite ticket around the ten-second clock and measures what it really got', () => {
  const text = race();
  for (const offset of ['9.5', '9.9', '10.1']) assert.match(text, new RegExp(`offset = ${offset.replace('.', '\\.')}, delay = 0`), `a trial queues the second ticket at ${offset} s`);
  assert.match(text, /offset = 10\.5, delay = 2/, 'and one while the claim is in flight (the fault adapter delays every cancel)');
  assert.match(text, /_MatchFaults:ConfigureCancel\(0, trial\.delay\)/, 'the claim window is made by delaying the cancel the guard performs');
  assert.match(text, /ticketB\.guardStarted - t0/, 'the realized offset is read from the two tickets, not assumed');
  assert.match(text, /ticketA\.guarding == true/, 'the in-flight trial asserts that the claim really was in flight');
  assert.match(text, /A queues[^]*AttackFor\(idA, "gushan"\)[^]*AttackFor\(idB, "zuoying"\)/, 'A attacks Gushan first, B attacks Zuoying: opposite directions');
  assert.match(text, /count\(seen\.A\) == 1/, 'one match key per ticket');
  assert.match(text, /rooms == 1 and roomKeys\[1\] == keyA/, 'one room, the one of the match key');
  assert.match(text, /guardTimers\[idA\] == nil and _MatchFlow\._T\.guardTimers\[idB\] == nil/, 'a human match drops the guard claim: both clocks are gone');
  assert.match(text, /recordsOf\(towns, key\) == 1/, 'a decisive result leaves exactly one settlement record');
  assert.match(text, /FORCE = \{ HUMAN = false, GUARD = true \}/, 'a human fight is played, a guard fight is forced');
  assert.match(text, /A trial that pairs humans plays a WHOLE FIGHT/, 'the header says a human trial plays a whole fight');
  assert.match(text, /NOT reachable in Maker/, 'and what the local adapter cannot show');
});

test('the race probe stands on production rules that exist: one guard clock per ticket, a claimed ticket is not live, a pairing clears the clock, and the claim logs', () => {
  const flowText = flow();
  assert.match(body(flowText, 'StartGuardClock'), /ticket\.guardStarted ~= nil then return end[^]*ticket\.guardStarted = DateTime\.UtcNow\.Elapsed/, 'the clock starts once per ticket and stamps guardStarted (the probe reads it as t0)');
  assert.match(body(flowText, 'SubmitQueue'), /ticket\.data\.state == "QUEUED" and not ticket\.guarding and not ticket\.cancelConfirmed and self:Player\(userId\) ~= nil/, 'a ticket being claimed is not live in the queue');
  assert.match(body(flowText, 'SubmitQueue'), /StartGuardClock\(userId, ticket\)[^]*Poll\(\)/, 'the clock starts when the queue accepted the ticket, before the pairing poll');
  assert.match(body(flowText, 'Matched'), /self:ClearGuardClock\(userId\)/, 'a pairing clears the guard clock');
  const fire = body(flowText, 'GuardFire');
  for (const line of ['[VRF][Guard] ticket claimed by the', '[VRF][Guard] a human match stands; no guard fight', '[VRF][Guard] claim dropped; ticket gone during withdrawal', '[VRF][Guard] human result deferred until the guard claim settles']) {
    assert.ok(fire.includes(line) || flowText.includes(line), `the flow logs ${line}`);
  }
  assert.match(fire, /ticket\.guarding = true[^]*self:CancelMatching\(ticket\.data\.profile\)/, 'the claim holds the guarding mark while it withdraws from the queue');
  const local = source('RootDesk/MyDesk/Matchmaking/MatchQueueLocal.mlua');
  assert.match(body(local, 'Cancel'), /return true/, 'the local queue confirms every cancel (why the deferred-human-result path needs the native service)');
  assert.match(body(local, 'Pairs'), /origin == second\.target and first\.target == second\.origin/, 'tickets pair only in opposite directions');
  assert.match(body(source('RootDesk/MyDesk/Matchmaking/MatchFaults.mlua'), 'Cancel'), /wait\(self\._T\.cancelDelay\)/, 'the fault adapter can hold a cancel open');
  assert.match(source('RootDesk/MyDesk/Matchmaking/MatchedBattle.mlua'), /not self\._T\.published/, 'a room publishes its result once');
});

// ---- the published-environment runbook (AC4) ------------------------------------------------------------------------------------

const RUNBOOK = 'docs/Issue-110-War-Acceptance.md';
const runbook = () => source(RUNBOOK);
// The step table: one row per "| S<n> | ... |", six cells (#, step, expected, actual, evidence, status).
const runbookRows = () => runbook().split('\n').filter(line => /^[|] S[0-9]+ [|]/.test(line)).map(line => line.split('|').slice(1, -1).map(cell => cell.trim()));

test('the two-account runbook lists every step with an expected value, an empty actual column and a not-run status', () => {
  const text = runbook();
  assert.match(text, /^status: not run$/m, 'the document says in one line that nothing has run');
  assert.match(text, /[|] # [|] 步驟 [|] 預期值 [|] 實測 [|] 要記錄的證據 [|] 狀態 [|]/, 'the table has the expected, actual, evidence and status columns');
  const rows = runbookRows();
  assert.ok(rows.length >= 15, `the runbook has its steps, found ${rows.length}`);
  rows.forEach((cells, index) => {
    assert.equal(cells.length, 6, `${cells[0]} has six cells`);
    assert.equal(cells[0], `S${index + 1}`, 'steps are numbered S1, S2, ... without gaps');
    assert.ok(cells[1].length > 0 && cells[2].length > 0 && cells[4].length > 0, `${cells[0]} says what to do, what to expect and what to record`);
    assert.equal(cells[3], '', `${cells[0]} has an EMPTY actual column: nothing was run, so nothing is claimed`);
    assert.equal(cells[5], 'not run', `${cells[0]} is marked not run`);
  });
  assert.doesNotMatch(text, /^status: (?!not run)/m, 'no document-level status other than not run');
});

test('the runbook carries the steps of the acceptance criterion and of the #109 retention measurements', () => {
  const text = runbook();
  const rows = runbookRows().map(cells => cells.join(' '));
  const stepWith = pattern => rows.find(row => pattern.test(row));
  assert.ok(stepWith(/互選/) && stepWith(/differentSources/) && stepWith(/WarpMatchUser/), 'mutual pick, pairing across instances and the native warp are steps');
  assert.ok(stepWith(/QUEUE_RESULT_INVALID/), 'the same-town pairing gap of ADR 0010 is a step');
  assert.ok(stepWith(/AlreadyMatched/), 'the ten-second race on the native service (ADR 0011) is a step');
  assert.ok(stepWith(/swap code=/) && stepWith(/settle conflict/), 'two matches settling one town on the native service (ADR 0013) is a step');
  assert.ok(stepWith(/ADR 0012/) && stepWith(/另一個\*{0,2} WorldInstance/), 'the idle player on another instance (ADR 0012) is a step');
  assert.ok(stepWith(/flipped=true/) && stepWith(/鼓山降到 20/), 'the flip case is a step');
  assert.ok(stepWith(/reason=Disconnect/) && stepWith(/BattleCleanup/), 'retention measurement 1: the delay between the disconnect and the leave');
  assert.ok(stepWith(/recovers ticket/) && stepWith(/receipt re-armed/), 'retention measurement 2: a reconnect inside the retention');
  assert.ok(stepWith(/STALE_ROOM_RECOVERY/) && stepWith(/room=none/), 'retention measurement 3: past the retention, and a room of another instance');
  assert.ok(stepWith(/UserLeaveReason/) && stepWith(/native code=/), 'the leave reason and the native cancel after a leave are recorded');
  assert.ok(stepWith(/login placed user=/), 'the login landing by the live owner is a step');
  for (const phrase of ['Maker 與發布環境的存檔互不相通', '兩個 WorldInstance', '遮蔽 ProfileCode', '別名 A/B', 'WorldInstanceId', 'RoomKey', '「實測」欄一律留空']) assert.ok(text.includes(phrase), `the runbook states: ${phrase}`);
  assert.ok(text.includes('Issue-30-Matchmaking.md') && text.includes('tests/README.md'), 'it points at the matchmaking acceptance table and at the Maker probes');
  assert.match(source('docs/Issue-30-Matchmaking.md'), /Issue-110-War-Acceptance\.md/, 'the matchmaking acceptance table points at the war runbook');
});

test('the runbook steps say what two accounts can really do and what the code really writes', () => {
  const text = runbook();
  const row = n => runbookRows().map(cells => cells.join(' ')).find(line => line.startsWith(`S${n} `)) || '';
  // S18: a normal logout removes the entity, so the sweep cannot meet B; B needs the board flipped by A alone against a guard.
  assert.match(row(18), /正常關閉應用程式[^]*只有 A 排隊[^]*守衛[^]*鼓山 10 → 0/, 'S18: B logs out standing in Gushan at 10, A alone beats the guard and flips it');
  assert.match(row(18), /\(4\) 返回後 A 在左營/, 'S18: A returns to Zuoying after beating the guard');
  assert.match(runbookRows().find(([name]) => name === 'S18')[2], /A 返回左營[^]*奪下鼓山[^]*B 被放到鹽埕/, 'S18: the capture notice names Gushan without landing A there');
  assert.match(row(18), /不會有 `sweep skipped offline`[^]*網路切斷/, 'S18: sweep skipped offline is expected only for a network cut, not for a logout');
  // S6 and S8: the history holds the match key once; experience is the profile\'s own dead units, and 0 is valid.
  for (const n of [6, 8]) {
    assert.match(row(n), /自己陣亡的單位/, `S${n}: the experience is that profile\'s own dead units`);
    assert.match(row(n), /0 也是有效/, `S${n}: zero experience is valid`);
  }
  assert.doesNotMatch(text, /兩人都收到怪物經驗值|只有 A 的 profile 收到/, 'nobody "receives" experience in a way that says every profile earns some');
  // Prerequisite 6 and S9: four wins reach 20, the fifth flips, S6 and S7 already count for two.
  assert.match(text, /四場勝利把鼓山壓到 20[^\n]*100 → 80 → 60 → 40 → 20[^\n]*第五場勝利換旗[^\n]*S6、S7 已經算兩場/, 'prerequisite 6 counts the wins');
  assert.doesNotMatch(text, /連打五場真人戰勝（100/, 'the old five-wins-to-20 sentence is gone');
  assert.match(row(9), /第五場/, 'S9 is the fifth win');
  assert.match(runbookRows().find(([name]) => name === 'S9')[2], /A 返回左營[^]*奪下鼓山[^]*B 回鹽埕/, 'S9: the human capturer returns to Zuoying and the defender to its capital');
  // S12: the native code is mapped by FormationStorage; SwapTowns reads 2000000 or 1000007 as a conflict.
  assert.match(row(12), /1000002[^]*轉成 `2000000`[^]*`2000000` 或 `1000007`/, 'S12: native 1000002 becomes 2000000, a conflict is 2000000 or 1000007');
  assert.doesNotMatch(text, /程式以 `2000000` 與 `1000002` 判讀/, 'the old reading of the codes is gone');
  assert.match(source('RootDesk/MyDesk/Formations/FormationStorage.mlua'), /complete\(code == 1000002 and 2000000 or code\)/, 'FormationStorage does map the native code');
  assert.match(body(source('RootDesk/MyDesk/Formations/FactionWarTownDocument.mlua'), 'SwapTowns'), /code == 2000000 or code == 1000007/, 'and SwapTowns does read both codes as a conflict');
  // S17 / S19: a login in another WorldInstance does not see the departFailed mark that only lives in the first instance\'s memory.
  assert.match(row(19), /另一個 WorldInstance[^]*QUEUED[^]*`departFailed`[^]*記憶體/, 'S19: a cross-instance re-login finds a durable QUEUED ticket');
  assert.match(row(19), /`\[VRF\]\[MatchFlow\] world instance=`/, 'S19: the instance is read from the world instance line');
  // S2: no ambiguous phrases.
  assert.doesNotMatch(row(2), /沒有主城選項|沒有排隊時按鈕可按/, 'S2 no longer uses the two ambiguous phrases');
  assert.match(row(2), /READY/, 'S2 names the state of the attack button');
  // The world instance id and the leave reason are logged now, so the document says so.
  assert.doesNotMatch(text, /目前程式沒有任何一行日誌印出 WorldInstanceId|WorldInstanceId 沒有日誌|Leave 沒有日誌/, 'the open items no longer say these are not logged');
  assert.match(text, /未決事項[^]*`\[VRF\]\[MatchFlow\] world instance=`[^]*`\[VRF\]\[MatchDisconnect\] user=`/, 'the open items say where the instance id and a leave without a ticket are logged');
  assert.equal(runbookRows().length, 19, 'S1 to S19');
});

test('every log line the runbook asks the reader to find exists in the production code', () => {
  const production = allProductionText();
  const fragments = new Set();
  for (const m of runbook().matchAll(/`([^`]*[[]VRF[\]][^`]*)`/g)) fragments.add(m[1]);
  assert.ok(fragments.size >= 20, `the runbook quotes its log lines, found ${fragments.size}`);
  for (const quoted of fragments) {
    // A quoted line is checked up to its first placeholder (<..., "...") or first "=", the part the code writes literally.
    let literal = quoted;
    for (const cut of ['<', ' ... ', '=']) {
      const at = literal.indexOf(cut);
      if (at >= 0) literal = literal.slice(0, cut === '=' ? at + 1 : at);
    }
    literal = literal.trim();
    const report = literal.match(/^[[]VRF[\]][[]MatchFlow[\]] ([A-Z_]+)$/);
    if (report) assert.ok(production.includes(`code = "${report[1]}"`), `${quoted}: MatchFlow reports ${report[1]}`);
    else assert.ok(production.includes(literal), `${quoted}: the production code writes "${literal}"`);
  }
});

// ---- the README section ------------------------------------------------------------------------------------------------------------

const readmeSection = () => source('tests/README.md').match(/## War integration [(]#110[)][^]*?(?=\n## )/)?.[0] || '';

test('the README records the #110 probes, maps all four criteria to the probes that carry them, and is honest about what has not run', () => {
  const section = readmeSection();
  assert.ok(section.length > 0, 'the section "War integration (#110)" exists');
  assert.match(section, /[|] Probe [|] Context [|] Final line [|]/, 'the probes are listed in the table format of the earlier sections');
  for (const name of Object.keys(probes)) assert.ok(section.includes(name), `the section names ${name}`);
  assert.match(section, /faction_war_integration_contract\.test\.cjs/, 'and the contract test');
  for (const joins of ['six joins', 'two joins']) assert.ok(section.includes(joins), `the table says ${joins}`);
  assert.match(section, /at most 10 virtual players in total and kicked ones count/, 'the join limit and that kicked players count is stated');
  for (const ac of ['AC1', 'AC2', 'AC3', 'AC4']) assert.match(section, new RegExp(`[|] ${ac} `), `${ac} is mapped`);
  assert.match(section, /Verified in Maker \(2026-11-22/, 'it records the Maker run with its date');
  assert.doesNotMatch(section, /not yet run in Maker/, 'and no longer says the probes have not run');
  assert.match(section, /\nNot verified: /, 'and lists what is not verified');
  assert.match(section, /Issue-110-War-Acceptance/, 'and points at the runbook for the part Maker cannot run');
  assert.match(section, /Manual visual checklist/, 'what only a real client can do is a manual checklist');
  assert.match(section, /\nWhat Maker cannot do for #110: /, 'and what Maker cannot do is stated');
  assert.match(section, /THE FIGHTS ARE NOT PLAYED|The fights are forced, not played/, 'forced results are called forced');
  assert.match(section, /plays a whole fight \(about a minute\)/, 'a human trial of the race probe is said to play a whole fight');
  assert.match(section, /Order for the three probes/, 'the order the lead runs them in is given');
  assert.match(section, /Only trials 1 and 4 are decisive[^\n]*trials 2 and 3 fall inside the EITHER band/, 'the race probe says which trials decide and which fall in the EITHER band');
  assert.match(section, /`inClaim`\) is asserted only in trial 4[^\n]*trial 3 logs it without asserting it/, 'and that inClaim is asserted in trial 4 only');
  for (const step of ['STEP 1', 'STEP 12', 'STEP 15']) assert.ok(section.includes(step), `the order names ${step}`);
});

test('every file the README section names exists, every probe the criteria map is a real one, and the quoted log lines are real', () => {
  const section = readmeSection();
  for (const match of section.matchAll(/`([a-z0-9_]+[.](?:lua|cjs))`/g)) assert.ok(fs.existsSync(`tests/${match[1]}`), `tests/${match[1]} exists`);
  for (const match of section.matchAll(/`(docs\/[A-Za-z0-9_-]+[.]md)`/g)) assert.ok(fs.existsSync(match[1]), `${match[1]} exists`);
  // The mapped probes and steps: an earlier probe is named together with a step that its header numbers.
  const earlier = (name, step) => {
    const header = source(`tests/${name}`).match(/^(?:--.*\n)+/)?.[0] || '';
    assert.match(header, new RegExp(`--\\s+${step}\\s+[A-Z]`), `${name} has a STEP ${step}`);
  };
  earlier('faction_war_conquest_e2e_runtime_probe.lua', 2);
  earlier('faction_war_conquest_e2e_runtime_probe.lua', 3);
  earlier('faction_war_conquest_e2e_runtime_probe.lua', 6);
  earlier('faction_war_conquest_e2e_runtime_probe.lua', 7);
  earlier('faction_war_contest_e2e_runtime_probe.lua', 6);
  earlier('faction_war_contest_e2e_runtime_probe.lua', 5);
  earlier('faction_war_reconnect_guard_e2e_runtime_probe.lua', 4);
  earlier('faction_war_reconnect_guard_e2e_runtime_probe.lua', 8);
  earlier('faction_war_reconnect_queue_e2e_runtime_probe.lua', 2);
  earlier('faction_war_reconnect_queue_e2e_runtime_probe.lua', 5);
  assert.match(source('tests/faction_war_guard_e2e_runtime_probe.lua'), /STEP 2 queues against Gushan, cancels after 3 s/, 'the guard e2e STEP 2 is the cancel in place');
  // Log lines quoted in the "Lines" table: the production code writes them, or the new probe itself does.
  const production = allProductionText();
  // The probes build most of their lines as PREFIX .. "text": read that as the prefix followed by the text.
  const own = Object.entries(probes).map(([name, spec]) => probeText(name).split('PREFIX .. "').join(`[VRF][${spec.prefix}] `)).join('\n');
  const lines = section.slice(section.indexOf('Expected `[VRF]` lines'), section.indexOf('Manual visual checklist'));
  const quoted = [...lines.matchAll(/`([[]VRF[\]][^`]*)`/g)].map(m => m[1]);
  assert.ok(quoted.length >= 15, `the section quotes its log lines, found ${quoted.length}`);
  for (const line of quoted) {
    let literal = line;
    for (const cut of ['<', ' (', '=']) {
      const at = literal.indexOf(cut);
      if (at >= 0) literal = literal.slice(0, cut === '=' ? at + 1 : at);
    }
    literal = literal.trim();
    assert.ok(production.includes(literal) || own.includes(literal), `${line}: someone writes "${literal}"`);
  }
});

test('the other READMEs sections that the #110 section leans on are still there', () => {
  const readme = source('tests/README.md');
  for (const heading of ['## Disconnect and reconnect (#109)', '## Two matches contest one town (#108)', '## Capture, landing and eviction (#107)', '## Guard fight after ten seconds in the queue (#106)', '### Manual visual checklist']) assert.ok(readme.includes(heading), `${heading} exists`);
});
