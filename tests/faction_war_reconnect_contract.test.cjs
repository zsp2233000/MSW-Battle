const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');

// Structural contract for #109 (spec #103, 「斷線重返」): a player who leaves and comes back is put where the war says they belong.
// The behaviour is proven in Maker by the faction_war_reconnect_*_runtime_probe.lua files (see tests/README.md, "Disconnect and reconnect (#109)");
// these tests pin the seams those probes drive, and the documents that have to agree with the code.
const source = path => fs.readFileSync(path, 'utf8').replace(/\r\n/g, '\n');
const methods = text => [...text.matchAll(/^    method \w+ (\w+)\(/gm)].map(m => m[1]);
const body = (text, name) => text.match(new RegExp(`method \\w+ ${name}\\([^]*?(?=\\n    @|\\n    method|\\n    handler|\\nend)`))?.[0] || '';
const handler = (text, name) => text.match(new RegExp(`handler ${name}\\([^]*?(?=\\n    @|\\n    method|\\n    handler|\\nend)`))?.[0] || '';
const war = () => source('RootDesk/MyDesk/Formations/FactionWar.mlua');
const attack = () => source('RootDesk/MyDesk/Formations/FactionWarAttack.mlua');
const flow = () => source('RootDesk/MyDesk/Matchmaking/MatchFlow.mlua');
const battle = () => source('RootDesk/MyDesk/Combat/BattleSession.mlua');
const adr = prefix => source(`docs/adr/${fs.readdirSync('docs/adr').find(name => name.startsWith(prefix))}`);
// The tag is the line right above a method; pure helpers carry none.
const tag = (text, name) => text.match(new RegExp(`(@ExecSpace\\("\\w+"\\)\\n)?    method \\w+ ${name}\\(`))?.[1] || '';

// ---- the outcome of a match is rebuilt from the stored record ------------------------------------------------------------------

test('the outcome of a match is read from the stored record by one pure reader, shared by the repeat answer and the landing', () => {
  const text = attack();
  assert.ok(methods(text).includes('OutcomeFrom'), 'OutcomeFrom exists');
  assert.equal(tag(text, 'OutcomeFrom'), '', 'a pure reader carries no ExecSpace');
  const reader = body(text, 'OutcomeFrom');
  assert.match(reader, /towns\.settled/, 'it reads the settled list of the town document');
  assert.match(reader, /EntryKey\(entry\)/, 'it matches on the same key rule as the settlement');
  for (const field of ['entry.w', 'entry.l', 'entry.s', 'entry.o']) assert.ok(reader.includes(field), `it rebuilds from ${field}`);
  assert.match(reader, /flipped = /, 'it says whether the town changed flag');
  assert.match(body(text, 'Attempt'), /self:OutcomeFrom\(towns, operation\.matchKey\)/, 'a repeated result answers with what the first delivery did, through the reader');
  assert.doesNotMatch(body(text, 'Attempt'), /entry\.o ~= nil/, 'the repeat answer no longer reads the record by hand');
});

test('the landing falls back to the stored record when this room did not settle the match, and keeps its pinned shape', () => {
  const landing = body(attack(), 'ResolveLanding');
  assert.match(landing, /self\._T\.outcomes\[matchKey\]/, 'the room that settled the match remembers it');
  assert.match(landing, /self:OutcomeFrom\(towns, matchKey\)/, 'any other room rebuilds it from the town document it has just read');
  assert.ok(landing.indexOf('OutcomeFrom') > landing.indexOf('ReadTowns'), 'the record is read after the board, never from a stale copy');
  assert.match(landing, /outcome\.flipped and outcome\.winner == origin/, 'only the side that won the flipping match walks into the conquered town');
  assert.match(landing, /_FactionWar:Landing\(faction, preferred, towns\)/, 'ownership is still judged on the live board');
  assert.doesNotMatch(landing, /\bwait\(/, 'no waiting loop of its own: a room that did not settle has nothing to wait for');
});

test('the landing says how it was decided: a table with the destination, the outcome and whether it could be read, and LandingFor is a thin wrapper', () => {
  const text = attack();
  assert.ok(methods(text).includes('ResolveLanding'), 'ResolveLanding exists');
  assert.equal(tag(text, 'ResolveLanding'), '@ExecSpace("ServerOnly")\n', 'it reads storage and waits, so it is a server method');
  assert.match(text, /method table ResolveLanding\(string userId, any ticket\)/, 'it answers with one table, never a second return value');
  const landing = body(text, 'ResolveLanding');
  assert.match(landing, /return \{ destination = destination, outcome = outcome, reliable = true \}/, 'a decided landing is reliable and carries the outcome that decided it');
  assert.equal((landing.match(/reliable = false/g) || []).length, 2, 'both fallbacks to the departure town (nothing to land, unreadable board) are marked unreliable');
  const code = landing.replace(/--.*$/gm, '');
  assert.doesNotMatch(code, /return (origin|destination)\s*$/m, 'every exit returns the table');
  assert.doesNotMatch(code, /^\s*return [^{\n][^\n]*,/m, 'no second return value');
  const wrapper = body(text, 'LandingFor');
  assert.equal(tag(text, 'LandingFor'), '@ExecSpace("ServerOnly")\n', 'it yields through ResolveLanding, so it keeps its tag');
  assert.match(wrapper, /return self:ResolveLanding\(userId, ticket\)\.destination/, 'the in-room return gets exactly the destination it always got');
  assert.equal(wrapper.replace(/--.*$/gm, '').split('\n').filter(line => line.trim()).length, 3, 'a wrapper (signature, one return, end), with no logic of its own');
});

// Every early `return` of `text` has a [VRF] log on its own line or the line before it.
const silentExits = text => {
  const lines = text.split('\n');
  const silent = [];
  lines.forEach((line, index) => {
    if (!/\breturn\b/.test(line) || /^\s*--/.test(line)) return;
    if (/\[VRF\]/.test(line) || /\[VRF\]/.test(lines[index - 1] || '')) return;
    silent.push(line.trim());
  });
  return silent;
};

test('a queue request that is refused says why instead of returning silently', () => {
  const queue = body(attack(), 'AttackFor');
  assert.deepEqual(silentExits(queue.split('\n').slice(0, 14).join('\n')), [], 'every refusal before the read logs a [VRF] line');
  for (const reason of ['ENGAGED', 'UNAVAILABLE', 'INVALID']) {
    assert.match(queue, new RegExp(`log\\("\\[VRF\\]\\[FactionWarAttack\\] queue refused[^\\n]*${reason}`), `${reason} is logged`);
  }
});

test('a player who comes back after the room is gone is told what the last match did to the towns, from the stored record only', () => {
  const text = attack();
  assert.ok(methods(text).includes('NoticeText'), 'the notice has a pure wording rule');
  assert.ok(!methods(text).includes('ResultNotice'), 'and no reader of its own: the outcome comes from the landing that decided the destination (no second board read)');
  assert.equal(tag(text, 'NoticeText'), '', 'the wording is a pure helper');
  assert.match(body(text, 'NoticeText'), /上一場戰果/, 'it speaks of the 戰果 of the glossary');
  assert.doesNotMatch(body(text, 'NoticeText'), /勝利|落敗|平手/, 'the record holds no win or loss for the player, so the text claims none');
});

// ---- the last town a player stood in is kept, so a login can bring them back ---------------------------------------------------

test('the last town is one small per-profile key written through the storage boundary, best effort, one write at a time', () => {
  const text = war();
  assert.match(text, /property string TownKey = "CountryWarTownV1"/, 'a key of its own next to the faction key');
  for (const name of ['ReadTown', 'Remember', 'StoreTown']) assert.ok(methods(text).includes(name), `${name} exists`);
  // The faction and the last town are the same kind of small per-profile value, so one reader serves both.
  assert.ok(methods(text).includes('ReadProfileKey') && methods(text).includes('IsMissing'), 'one reader of a per-profile key and one rule for "nothing stored yet"');
  assert.equal(tag(text, 'IsMissing'), '', 'the missing-value rule is pure');
  assert.match(body(text, 'ReadTown'), /self:ReadProfileKey\(profile, self\.TownKey, function\(raw\) return self:IsTown\(raw\) end, complete\)/, 'it reads through the same boundary as the faction');
  assert.match(body(text, 'ReadFaction'), /self:ReadProfileKey\(profile, self\.FactionKey, function\(raw\) return raw == "RED" or raw == "BLUE" end, complete\)/, 'the faction is the same reader with its own accepted values');
  const reader = body(text, 'ReadProfileKey');
  assert.match(reader, /_FormationStorage:Read\(profile, storageKey/, 'it reads through FormationStorage');
  assert.match(reader, /complete\(""\)[^]*complete\(raw\)[^]*complete\(nil\)/, 'nothing stored reads as "", a value that is accepted as itself, a storage error or any other value as unreadable, never as a guess');
  assert.equal((text.match(/code == 0 and raw == nil/g) || []).length, 1, 'the "nothing stored yet" test is written once, in IsMissing');
  assert.match(body(text, 'IsMissing'), /code == 1000002 or \(code == 0 and raw == nil\)/);
  for (const name of ['ReadTownsRaw', 'StoreTown']) assert.match(body(text, name), /self:IsMissing\(code, raw\)/, `${name} asks the one rule`);
  assert.deepEqual(silentExits(body(text, 'Remember')), [], 'a request that is refused or coalesced says so instead of returning silently');
  assert.match(body(text, 'Remember'), /town remember skipped[^\n]*\n\s+return/, 'the invalid input is logged');
  assert.match(body(text, 'Remember'), /town remember coalesced[^\n]*\n\s+return/, 'the write that is already running is logged');
  const store = body(text, 'StoreTown');
  assert.match(store, /_FormationStorage:Write\(profile, self\.TownKey/, 'the write goes through FormationStorage');
  assert.match(store, /raw == town/, 'an unchanged town costs no write');
  assert.match(store, /\[VRF\]\[FactionWar\] town not remembered/, 'a failed write is logged, never raised');
  assert.match(body(text, 'Remember'), /_T\.remembering\[profile\]/, 'one write per profile runs at a time; the newest town is written afterwards');
  assert.match(body(text, 'Move'), /self:Remember\(/, 'every teleport inside the static room ends in a remembered town');
});

test('the fall sweep leaves a disconnected player where they are; they are judged when they come back', () => {
  const sweep = body(war(), 'SweepFallen');
  assert.match(sweep, /_MatchFlow:IsOffline\(/, 'the sweep asks the flow whether the player is online');
  assert.match(sweep, /\[VRF\]\[FactionWar\] sweep skipped offline/, 'the skip is logged');
  assert.match(body(war(), 'Enforce'), /_MatchFlow:IsOffline\(userId\)[^]*enforce skipped offline/, 'the per-player check skips a disconnected player too (a queued re-check may outlive the connection)');
  assert.match(body(war(), 'Evict'), /_MatchFlow:IsOffline\(userId\)[^]*evict dropped/, 'and a move that was decided before the player went offline is dropped');
  assert.equal(tag(flow(), 'IsOffline'), '@ExecSpace("ServerOnly")\n', 'the offline query is a server method of the flow');
  assert.match(body(flow(), 'IsOffline'), /self\._T\.offline\[userId\] == true/, 'it answers from the flow\'s own offline table');
});

// ---- the login placement: judged once per login, after the ticket has had its say ------------------------------------------------

test('FactionWar judges a returning player once per login: the town they stand in, or the last town for a fresh arrival in the lobby', () => {
  const text = war();
  assert.equal(tag(text, 'PlaceAtLogin'), '@ExecSpace("ServerOnly")\n', 'a server method');
  const entry = body(text, 'PlaceAtLogin');
  assert.match(entry, /IsInstanceRoom\(\)/, 'a match room never places anybody');
  assert.match(entry, /self\._T\.placing\[userId\]/, 'one placement runs per player: the enter and the reconnect event of one login both ask');
  assert.match(entry, /pcall\(/, 'the slot is released whatever happens inside');
  assert.match(entry, /\[VRF\]\[FactionWar\] login placement already running/, 'the second asker is logged');
  const place = body(text, 'PlaceOnce');
  assert.match(place, /_FactionWarAttack:WaitWhile\(/, 'it polls until the entity and its map exist instead of trusting the first event');
  assert.match(place, /LoginReadySeconds/, 'the wait is bounded by a property');
  assert.match(place, /_MatchFlow:IsOffline\(userId\)/, 'a disconnected player is judged when they reconnect, not now');
  assert.match(place, /self:IsTown\(here\)[^]*self:Remember\(profile, here\)/, 'a player who stands in a town has it remembered');
  assert.match(place, /self:Enforce\(userId, here, board\)/, 'a player in a town is judged by the same check as every other town action');
  assert.match(place, /local held = owned or _FormationHandoff:IsLockedForUser\(userId\)/, 'a player the handoff still locks is held by a ticket even when the flow has not recorded one yet (a recovery that timed out, a failed open)');
  assert.match(place, /if held then\n\s+log\("\[VRF\]\[FactionWar\] login placement left to the ticket/, 'a player in a town who is held keeps the town and is not judged');
  assert.match(place, /cause ~= "enter" or here ~= "formationlobby" or held/, 'only a fresh arrival in the lobby that no ticket holds is brought to a town');
  assert.doesNotMatch(place, /if owned then|or owned then/, 'the flow\'s hint is only an input of held');
  assert.match(place, /self:Landing\(faction, home, towns\)/, 'home if the faction still holds it (or holds it again), else the capital');
  const lobby = place.slice(place.indexOf('cause ~= "enter"'));
  assert.ok(lobby.indexOf('ReadFaction') < lobby.indexOf('ReadTown(') && lobby.indexOf('ReadTown(') < lobby.indexOf('ReadTowns'), 'faction first, then the last town, then the board');
  assert.match(place, /faction == "" or home == ""/, 'a player with no faction or no last town stays where they are');
  assert.match(place, /login placement unreadable/, 'unreadable data does nothing and says so');
  assert.doesNotMatch(text, /Environment:/, 'no environment branch');
  assert.match(handler(text, 'HandleUserLeaveEvent'), /placing\[event\.UserId\] = nil/, 'a leaver frees the slot');
});

test('the match room\'s battle session is looked up in one place', () => {
  const text = flow();
  assert.ok(methods(text).includes('Battle') && methods(text).includes('MatchMap'), 'one lookup of the match map and one of its battle');
  assert.equal((text.match(/"\/maps\/matchprobe"/g) || []).length, 1, 'the path is written once');
  assert.equal((text.match(/script\.BattleSession/g) || []).length, 1, 'and so is the component');
  for (const name of ['PublishState', 'RearmExperience', 'ReturnForUser']) assert.match(body(text, name), /self:Battle\(\)/, `${name} asks Battle()`);
  assert.match(body(text, 'RearmExperience'), /isvalid\(battle\)[^]*RearmExperienceReceipt\(userId\)/, 'a room without a battle is still logged and skipped');
});

test('MatchFlow hands every login to FactionWar after its own recovery, once the ticket state is settled', () => {
  const text = flow();
  assert.match(handler(text, 'HandleUserEnterEvent'), /self:Recover\(event\.UserId\)[^]*self:PlaceAtLogin\(event\.UserId, "enter"\)/, 'the arrival timer places after the recovery');
  const reconnect = handler(text, 'HandleUserReconnectEvent');
  assert.match(reconnect, /self:Recover\(event\.UserId\)[^]*self:PlaceAtLogin\(event\.UserId, "reconnect"\)/, 'a reconnect in the static room places after the recovery');
  const wrapper = body(text, 'PlaceAtLogin');
  assert.match(wrapper, /IsInstanceRoom\(\)/, 'only the static room holds the towns');
  assert.match(wrapper, /_FactionWarAttack:WaitWhile\(function\(\) return self\._T\.busy\[userId\] or self\._T\.pendingRecover\[userId\] end, _FactionWar\.LoginReadySeconds\)/, 'it waits for a recovery that is still running, with the one bounded poll and the one login wait');
  assert.doesNotMatch(wrapper, /\bwait\(|waited/, 'no polling loop of its own');
  assert.match(wrapper, /if not settled then[^]*\[VRF\]\[MatchFlow\] login placement[^\n]*recovery[^]*owned = true/, 'a recovery that outlasts the wait is logged and the player is treated as owned');
  assert.match(wrapper, /self\._T\.arrival\[userId\] == true/, 'a ticket that owns the player (a queue, a room, a return) keeps them');
  assert.match(wrapper, /_FormationHandoff:IsLockedForUser\(userId\)/, 'so does a handoff that still locks the profile');
  assert.match(wrapper, /_FactionWar:PlaceAtLogin\(userId, cause, owned\)/, 'the town judgement is FactionWar\'s');
});

test('Recover records that a ticket owns an arriving player, so a lobby match return stays in the lobby', () => {
  const text = flow();
  assert.match(text, /self\._T\.arrival = \{\}/, 'the hint is per room and starts empty');
  const recover = body(text, 'Recover');
  assert.match(recover, /self\._T\.arrival\[userId\] = nil/, 'a terminal or missing ticket owns nobody');
  assert.match(recover, /self\._T\.arrival\[userId\] = true\n/, 'a live ticket owns the player: a yes or no, nothing reads which kind of ticket it is');
  assert.doesNotMatch(text, /_T\.arrival\[userId\] = [^\n]*"(WAR|LOBBY)"/, 'no kind is stored that nothing reads');
  assert.doesNotMatch(body(text, 'RestoreReturning'), /local war = \{ data = \{[^\n]*profile/, 'the landing copy of the ticket holds only what the landing reads');
  assert.match(body(text, 'Depart'), /self\._T\.arrival\[userId\] = nil/, 'a new login never inherits the last one\'s hint');
});

// ---- a leave and a reconnect -------------------------------------------------------------------------------------------------

test('a war ticket whose leave cleanup failed is cancelled again on reconnect instead of being resumed', () => {
  const text = flow();
  const depart = body(text, 'Depart');
  assert.match(depart, /ticket\.departFailed = true/, 'a cleanup that did not finish marks the ticket');
  assert.match(depart, /ticket\.data ~= nil and ticket\.data\.matchKey or ""/, 'a ticket whose reservation never filled in does not break the final log');
  assert.match(depart, /\[VRF\]\[MatchDisconnect\][^\n]*reason=/, 'the leave reason is logged');
  const recover = body(text, 'Recover');
  assert.match(recover, /current\.departFailed and \(current\.data\.origin or ""\) ~= "" and self:IsWaiting\(current\)/, 'only a war ticket that was still waiting for an opponent');
  assert.match(recover, /self:CancelForUser\(userId\)[^]*return/, 'it cancels through the ordinary cancel and does not resume');
  assert.ok(recover.indexOf('departFailed') < recover.indexOf('Reclaim(userId, current.data, true)'), 'before the live ticket is judged HELD and resumed');
  assert.match(handler(text, 'HandleUserLeaveEvent'), /self:Depart\(event\.UserId, tostring\(event\.LeaveReason\)\)/, 'the leave reason reaches the log');
});

test('a leave with no ticket is logged with its reason, and each room says which world instance it belongs to', () => {
  const text = flow();
  assert.match(body(text, 'Depart'), /if ticket == nil then\n\s+log\("\[VRF\]\[MatchDisconnect\][^\n]*no ticket[^\n]*reason=" \.\. tostring\(reason or ""\)\)\n\s+return\n/, 'a player with no ticket still leaves a line with the leave reason');
  assert.match(body(text, 'OnBeginPlay'), /log\("\[VRF\]\[MatchFlow\] world instance=" \.\. tostring\(_WorldInstanceService\.WorldInstanceId\)/, 'the room boot logs the world instance id (the one API there is: _WorldInstanceService.WorldInstanceId), so a cross-instance re-login can be read from the logs');
});

test('an admission clears its moving mark even when the move raises', () => {
  const admit = body(flow(), 'Admit');
  assert.match(admit, /pcall\(function\(\) return self:TransferAdapter\(\):MoveToMatch\(slot\.room, userId\) end\)/, 'the native move runs under pcall');
  assert.ok(admit.indexOf('pcall(') > admit.indexOf('self._T.moving[userId] = ticket') && admit.indexOf('pcall(') < admit.indexOf('self._T.moving[userId] = nil'), 'the mark is set before it and cleared right after it, whatever happened');
  assert.match(admit, /if not ok then\n\s+log_error\("\[VRF\]\[MatchTransfer\][^\n]*move raised[^\n]*\n\s+moved = false\n\s+end/, 'a raise is logged and counts as a move that did not happen, so the admission is withdrawn like any failed move');
});

test('a reconnect inside the match room recovers the ticket and sends the experience receipt again', () => {
  const reconnect = handler(flow(), 'HandleUserReconnectEvent');
  assert.match(reconnect, /if _RoomService:IsInstanceRoom\(\) then[^]*RearmExperience\(event\.UserId\)[^]*self:Recover\(event\.UserId\)[^]*return\n\s+end/, 'the room branch re-arms the receipt and recovers, then ends');
  assert.match(reconnect, /\[VRF\]\[MatchDisconnect\] match room reconnect recovers ticket/, 'the branch is logged');
  assert.doesNotMatch(reconnect, /Admit|MoveToMatch/, 'a reconnect never re-admits; the retained entity is already in the room');
  assert.match(body(flow(), 'RearmExperience'), /isvalid\(battle\)[^]*RearmExperienceReceipt\(userId\)/, 'the flow asks the room\'s battle');
  const session = body(battle(), 'RearmExperienceReceipt');
  assert.match(session, /self\._T\.experienceSent\[user\] = nil/, 'the once-per-entity mark is cleared');
  assert.match(session, /GetUserEntityByUserId\(userId\)/, 'for the entity of that user only');
  assert.match(session, /\[VRF\]\[BattleSession\] experience receipt re-armed/, 'and logged');
  assert.doesNotMatch(session, /MonsterLevelStorage|Settle/, 'a receipt is not a settlement: nothing is credited again');
});

// ---- a re-login while the ticket still says IN_ROOM ---------------------------------------------------------------------------

test('a re-login with a ticket that says IN_ROOM goes back into the room while it runs, else the ticket is closed and the landing follows the match', () => {
  const text = flow();
  const recover = body(text, 'Recover');
  assert.match(recover, /data\.state == "IN_ROOM" and not _RoomService:IsInstanceRoom\(\) then\n(\s+--[^\n]*\n)*\s+if self:Rejoin\(userId, data\) then/, 'the static room tries the live room first');
  assert.ok(recover.indexOf('self:Rejoin(userId, data)') < recover.indexOf('STALE_ROOM_RECOVERY"'), 'and only then closes the ticket as before');
  const rejoin = body(text, 'Rejoin');
  assert.match(rejoin, /self:TransferAdapter\(\):FindRoom\(data\.matchKey\)/, 'the room is looked up behind the transfer adapter');
  assert.match(rejoin, /self:TransferAdapter\(\):MoveToMatch\(room, userId\)/, 'and entered through the same boundary as an admission');
  assert.match(rejoin, /self\._T\.moving\[userId\]/, 'an admission that is still moving the player is not raced');
  assert.match(rejoin, /\[VRF\]\[MatchFlow\] rejoin match=/, 'both outcomes are logged');
  assert.doesNotMatch(rejoin, /Phase|BattleSession/, 'the static room cannot read another room\'s battle phase, so a finished battle is rejoined too');
  assert.match(body(text, 'Admit'), /self\._T\.moving\[userId\] = ticket[^]*MoveToMatch[^]*self\._T\.moving\[userId\] = nil/, 'an admission marks the player as moving around the move');
});

test('a war ticket closed in the static room puts the player where the match leaves them, once, and says so only when it moved them', () => {
  const text = flow();
  assert.match(body(text, 'RestoreReturning'), /self:LandAfterRestore\(userId, [^)]*\)/, 'a finished restore lands the player');
  assert.ok(body(text, 'RestoreReturning').indexOf('Close') < body(text, 'RestoreReturning').indexOf('LandAfterRestore'), 'after the ticket is closed, from a copy taken before it was');
  const landing = body(text, 'LandAfterRestore');
  assert.match(landing, /IsInstanceRoom\(\)/, 'only in the static room');
  assert.match(landing, /local result = _FactionWarAttack:ResolveLanding\(userId, war\)/, 'the landing is the same rule the room-side return uses, with its reliability');
  assert.match(landing, /not result\.reliable then\n(\s+--[^\n]*\n)*\s+log\("\[VRF\]\[MatchFlow\] landing after restore left in place[^\n]*\n\s+return/, 'a landing that could not be read moves nobody (the departure town it falls back to is no destination) and says so');
  assert.ok(landing.indexOf('result.reliable') < landing.indexOf('_FactionWar:Move('), 'and that is decided before anybody is moved');
  assert.match(landing, /here == destination[^]*landing in place/, 'a player who already stands there is left alone, so a normal return is not moved twice');
  assert.match(landing, /_FactionWar:Move\(player, destination\)/, 'a move inside the static room is a teleport, not another room change');
  assert.match(landing, /_FactionWarAttack:NoticeText\(result\.outcome, origin\)/, 'the notice is built from the outcome that decided the destination');
  assert.doesNotMatch(landing, /ReadTowns|ResultNotice|LandingFor/, 'no second board read and no second decision');
  assert.match(landing, /ReceiveTownNotice\(destination, /, 'it reaches the player through the town notice');
  assert.doesNotMatch(landing, /MoveToLobby|MoveToTown/, 'the lobby-or-town decision stays in MoveHome');
  assert.match(body(text, 'MoveHome'), /_FactionWarAttack:LandingFor\(userId, ticket\)/, 'the room-side return is unchanged');
});

// ---- the documents agree with the code ---------------------------------------------------------------------------------------

test('ADR 0014 records the decisions in glossary vocabulary, and ADR 0011 / 0012 no longer leave #109 open', () => {
  const glossary = source('CONTEXT.md');
  assert.match(glossary, /\*\*登入落點\*\*:/, 'the glossary names the concept');
  const entry = term => glossary.match(new RegExp(`\\*\\*${term}\\*\\*:[^]*?_Avoid_: ([^\\n]+)`));
  const avoided = term => entry(term)[1].replace(/（.*$/, '').split('、').map(word => word.trim()).filter(Boolean);
  const forbidden = [...avoided('換旗次數'), ...avoided('過期戰果'), ...avoided('登入落點'), '失效戰果', '免扣'];
  const text = adr('0014');
  for (const word of forbidden) assert.ok(!text.includes(word), `ADR 0014 does not use "${word}"`);
  for (const name of ['登入落點', '戰果', '奪城', '過期戰果', '守衛']) assert.ok(text.includes(name), `ADR 0014 speaks of ${name}`);
  for (const symbol of ['CountryWarTownV1', 'PlaceAtLogin', 'IsOffline', 'RearmExperienceReceipt', 'Rejoin', 'FindRoom', 'OutcomeFrom', 'LandAfterRestore', 'NoticeText', 'departFailed']) assert.ok(text.includes(symbol), `ADR 0014 names ${symbol}`);
  assert.match(text, /#110/, 'what stays open goes to #110');
  assert.doesNotMatch(text, /`WAR`|`LOBBY`/, 'the arrival hint is a yes or no, so no ticket kind is named as stored');
  assert.match(text, /FactionWarAttack:WaitWhile/, 'the login wait is the shared bounded poll');
  assert.match(text, /IsLockedForUser/, 'a handoff that still locks the profile also holds the player');
  assert.doesNotMatch(adr('0011'), /屬 #109。/, 'ADR 0011 no longer says the guard ticket details belong to #109');
  assert.match(adr('0011'), /ADR 0014/, 'ADR 0011 points at the decision');
  assert.match(adr('0012'), /OutcomeFrom/, 'ADR 0012 says the record rebuilds the outcome');
  assert.match(adr('0012'), /IsOffline/, 'ADR 0012 says the sweep leaves a disconnected player alone');
});

// ---- the probes ---------------------------------------------------------------------------------------------------------------

const probes = {
  'faction_war_reconnect_runtime_probe.lua': { prefix: 'FactionWarReconnect', pass: /\[VRF\]\[FactionWarReconnect\] PROBE PASS/, profiles: ['wp2621'] },
  'faction_war_reconnect_queue_e2e_runtime_probe.lua': { prefix: 'ReconnectQueue', pass: /E2E PASS/, profiles: ['wp2621'], steps: ['SETUP PASS', 'EIGHT PASS', 'RECONNECT PASS', 'RECANCEL PASS', 'AGAIN PASS', 'CLEANUP'], guard: 10 },
  'faction_war_reconnect_guard_e2e_runtime_probe.lua': { prefix: 'ReconnectGuard', pass: /LANDING PASS/, profiles: ['wp2622'], steps: ['SETUP PASS', 'DISCONNECT PASS', 'RESULT PASS', 'RECONNECT PASS', 'REDELIVER PASS', 'LANDING PASS', 'CLEANUP'], guard: 10 },
  'faction_war_reconnect_human_e2e_runtime_probe.lua': { prefix: 'ReconnectHuman', pass: /LANDING PASS/, profiles: ['wp2623', 'wp2624'], steps: ['SETUP PASS', 'DISCONNECT PASS', 'RESULT PASS', 'RECONNECT PASS', 'REDELIVER PASS', 'LANDING PASS', 'CLEANUP'], guard: 600 },
  'faction_war_reconnect_login_runtime_probe.lua': { prefix: 'ReconnectLogin', pass: /<CASE> PASS|" PASS"/, profiles: ['wp2625', 'wp2626'], steps: ['FRIENDLY', 'FALLEN', 'RETAKEN', 'NOFACTION', 'NOTOWN', 'OFFLINE_FALL', 'OFFLINE_RETAKEN', 'CLEANUP'] },
  'faction_war_reconnect_relogin_e2e_runtime_probe.lua': { prefix: 'ReconnectRelogin', pass: /STALE PASS/, profiles: ['wp2625'], steps: ['SETUP PASS', 'ABORTED PASS', 'STALE PASS', 'CLEANUP'], guard: 10 },
  'faction_war_reconnect_rejoin_e2e_runtime_probe.lua': { prefix: 'ReconnectRejoin', pass: /LANDING PASS/, profiles: ['wp2623', 'wp2624'], steps: ['SETUP PASS', 'REJOIN PASS', 'RESULT PASS', 'LANDING PASS', 'CLEANUP'], guard: 600 },
};

test('the #109 probes use their own profiles and storage, number their steps and end in a pass line, as the e2e probes before them do', () => {
  for (const [name, spec] of Object.entries(probes)) {
    const text = source(`tests/${name}`);
    assert.match(text, /^-- /, `${name} starts with its instructions`);
    assert.match(text, /\[VRF\]\[/, `${name} logs [VRF] lines`);
    assert.ok(text.includes(`[VRF][${spec.prefix}]`), `${name} uses its own prefix`);
    assert.match(text, spec.pass, `${name} has its pass line`);
    assert.match(text, /Expected \[VRF\] lines[^\n]*Disconnect and reconnect \(#109\)|isolated/, `${name} says where the expected lines are, or is a rules probe`);
    for (const used of text.match(/wp26\d\d/g) || []) assert.ok(['wp2621', 'wp2622', 'wp2623', 'wp2624', 'wp2625', 'wp2626'].includes(used), `${name} uses only wp2621-wp2626, found ${used}`);
    for (const profile of spec.profiles) assert.ok(text.includes(profile), `${name} drives ${profile}`);
    for (const step of spec.steps || []) assert.ok(text.includes(step), `${name} announces ${step}`);
    if (spec.steps) assert.match(text, /^local STEP = 1$/m, `${name} is stepped by one variable`);
    if (spec.guard) {
      assert.match(text, new RegExp(`_FactionWarGuard\\.WaitSeconds = ${spec.guard}\\b`), `${name} sets the guard clock it needs (${spec.guard} s) explicitly`);
      if (spec.guard === 600) assert.match(text, /STEP == (?:8|9) then\n\s+_FactionWarGuard\.WaitSeconds = 10/, `${name} puts the clock back in CLEANUP`);
    }
    if (/e2e/.test(name)) assert.match(text, /DeleteGlobalDataStorageAndWait\(_FactionWar\.TownStorageName\)/, `${name} deletes the real town storage it wrote`);
  }
  const rules = source('tests/faction_war_reconnect_runtime_probe.lua');
  assert.match(rules, /war\.TownStorageName = STORAGE/, 'the rules probe isolates the town storage');
  assert.match(rules, /war\.TownKey = TOWN_KEY/, 'and the last-town key');
  assert.match(rules, /DeleteGlobalDataStorageAndWait\(STORAGE\)/, 'and deletes both afterwards');
  const login = source('tests/faction_war_reconnect_login_runtime_probe.lua');
  assert.match(login, /KickUser\(/, 'the login probe uses a true leave');
  assert.match(login, /add_virtual_player -profile_code wp2625/, 'and a true login');
  assert.match(login, /_FactionWar\.TownStorageName = STORAGE/, 'on an isolated town board');
  assert.match(source('tests/faction_war_reconnect_relogin_e2e_runtime_probe.lua'), /ConfigureRooms\(true\)/, 'the stale-room mode hides the rooms through the fault adapter');
});

test('the README records the #109 probes and is honest about what has not run', () => {
  const readme = source('tests/README.md');
  const section = readme.match(/## Disconnect and reconnect \(#109\)[^]*?(?=\n## )/)?.[0] || '';
  assert.ok(section.length > 0, 'the section exists');
  for (const name of Object.keys(probes)) assert.ok(section.includes(name), `the section names ${name}`);
  assert.match(section, /faction_war_reconnect_contract\.test\.cjs/, 'and the contract test');
  assert.match(section, /\| Probe \| Context \| Final line \|/, 'in the table format of the earlier sections');
  assert.match(section, /Verified in Maker \(2026-11-22/, 'it records the Maker run with its date');
  assert.doesNotMatch(section, /none of the probes above has run yet/, 'and no longer says nothing has run');
  assert.match(section, /last user really leaves is reclaimed by the engine/, 'and records that an empty match room is reclaimed at once');
  assert.match(section, /\nNot verified: /, 'and lists what is not verified');
  assert.match(section, /try_reconnect/, 'including the real network drop');
});

test('rooms are looked up behind the transfer adapter, which the fault adapter can hide in Maker', () => {
  const transfer = source('RootDesk/MyDesk/Matchmaking/MatchTransfer.mlua');
  const faults = source('RootDesk/MyDesk/Matchmaking/MatchFaults.mlua');
  assert.ok(methods(transfer).includes('FindRoom') && methods(faults).includes('FindRoom'), 'both adapters answer FindRoom');
  assert.match(body(transfer, 'FindRoom'), /InstanceRooms:TryGetValue\(matchKey\)/, 'the real adapter asks the room service');
  assert.match(body(transfer, 'FindRoom'), /IsValid\(\)/, 'a handle that is no longer valid is no room');
  assert.match(body(faults, 'ConfigureRooms'), /Environment:IsMakerPlay\(\)/, 'hiding rooms refuses to arm outside Maker');
  assert.match(body(faults, 'FindRoom'), /hideRooms/, 'while armed the room is not found');
  assert.match(body(faults, 'Remove'), /hideRooms = false/, 'Remove disarms it');
});
