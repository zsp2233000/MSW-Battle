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
    assert.match(cleanup, /DeleteGlobalDataStorageAndWait\(_FactionWar\.TownStorageName\)/, `${name} deletes the real town storage in CLEANUP`);
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
  inOrder(gate, [/self:FindGate\(origin, destination\)/, /self:NearGate\(player, gate\)/, /_FactionWarAttack:IsEngaged\(userId\)/, /self:ReadFaction\(/, /self:ReadTowns\(/, /self:CanPass\(faction, origin, destination, towns\)/, /self:Enforce\(userId, origin, towns\)/, /self:Move\(player, destination\)/], 'RequestGate');
  inOrder(options, [/self:Resolve\(/, /towns\[town\]\.owner ~= faction/, /"NOT_OWNED"/, /self:Targets\(town, faction, towns\)/, /self:IsEngaged\(userId\) and "ENGAGED" or "READY"/], 'OptionsFor');
  const text = journey();
  inOrder(luaFunction(text, 'entry'), [/CanEnterFromLobby\(user, userId\)/, /_T\.pending\[userId\] = user/, /readFaction\(profile\)/, /_FormationStorage:Write\(profile, _FactionWar\.FactionKey, "", choice/, /_FactionWar:EnterFrontline\(userId, user, faction\)/], 'the journey entry()');
  inOrder(luaFunction(text, 'gate'), [/_FactionWar:FindGate\(origin, destination\)/, /_FactionWar:NearGate\(user, door\)/, /_FactionWarAttack:IsEngaged\(userId\)/, /readFaction\(/, /readTowns\(\)/, /_FactionWar:CanPass\(faction, origin, destination, towns\)/, /_FactionWar:Enforce\(userId, origin, towns\)/, /_FactionWar:Move\(user, destination\)/], 'the journey gate()');
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
  // BLUE owns only Yancheng; Gushan is RED at strength 10.
  assert.match(text, /towns\.gushan\.owner = "RED"\n\s+towns\.gushan\.strength = 10/, 'Gushan is seeded RED at 10');
  assert.match(text, /queue\("CAPITAL P gushan -> yancheng", p, "yancheng"\)/, 'the RED player attacks the enemy capital');
  assert.match(text, /queue\("COUNTER Q yancheng -> gushan", q, "gushan"\)/, 'the BLUE player counterattacks from its only town');
  assert.match(text, /string\.sub\(key, 1, 6\) == "guard-"/, 'every fight is a guard match');
  assert.match(text, /EpochOf\(towns, "gushan"\) == 2/, 'the flip is counted');
  assert.match(text, /a lost guard fight changes nothing/, 'a lost guard fight is asserted to change nothing');
});

test('the capital probe forces results through seams that exist: the side labels, the damage call and the rules that make each fight a no-change or a flip', () => {
  const session = source('RootDesk/MyDesk/Combat/BattleSession.mlua');
  assert.match(session, /local faction = side == 1 and "PLAYER" or "ENEMY"/, 'the home side is PLAYER and the away side is ENEMY');
  assert.match(source('RootDesk/MyDesk/Combat/BattleUnit.mlua'), /method void ApplyResolvedDamage\(integer amount, Entity attacker, boolean allowHitStop, string hitEffectRUID, number hitEffectOffsetX, number hitEffectOffsetY\)/, 'the damage call has the signature the probe passes');
  const rules = attack();
  assert.match(rules, /property table Capitals = \{ nanzih = true, yancheng = true \}/, 'both capitals are exempt');
  assert.match(body(rules, 'Deduction'), /result ~= "WIN" or self:IsCapital\(target\)[^]*return 0/, 'a win over a capital takes nothing');
  assert.match(body(rules, 'Settle'), /homeResult == "LOSE" and kind ~= "GUARD"/, 'a lost guard fight names no winner, so it takes nothing');
  assert.match(rules, /property integer GuardDeduction = 10/, 'one guard win takes the 10 the board is seeded with');
  assert.match(body(rules, 'Attempt'), /flipped = remaining <= 0/, 'zero strength flips');
  assert.match(body(rules, 'Attempt'), /strength = _FactionWar\.FullStrength, e = _FactionWar:EpochOf\(towns, operation\.loser\) \+ 1/, 'and refills to the full strength with one more count');
  assert.match(body(attack(), 'Finish'), /AnnounceFall\(outcome\.loser, outcome\.owner\)/, 'the fall is announced to the static room');
  assert.match(body(war(), 'SweepFallen'), /self:Enforce\(userId, town, towns\)/, 'and the idle player of the fallen town is enforced home');
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
  assert.match(body(flowText, 'SubmitQueue'), /ticket\.data\.state == "QUEUED" and not ticket\.guarding and self:Player\(userId\) ~= nil/, 'a ticket being claimed is not live in the queue');
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
