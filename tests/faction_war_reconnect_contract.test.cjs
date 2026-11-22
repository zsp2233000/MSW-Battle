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
  const landing = body(attack(), 'LandingFor');
  assert.match(landing, /self\._T\.outcomes\[matchKey\]/, 'the room that settled the match remembers it');
  assert.match(landing, /self:OutcomeFrom\(towns, matchKey\)/, 'any other room rebuilds it from the town document it has just read');
  assert.ok(landing.indexOf('OutcomeFrom') > landing.indexOf('ReadTowns'), 'the record is read after the board, never from a stale copy');
  assert.match(landing, /outcome\.flipped and outcome\.winner == origin/, 'only the side that won the flipping match walks into the conquered town');
  assert.match(landing, /_FactionWar:Landing\(faction, preferred, towns\)/, 'ownership is still judged on the live board');
  assert.doesNotMatch(landing, /\bwait\(/, 'no waiting loop of its own: a room that did not settle has nothing to wait for');
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
  assert.ok(methods(text).includes('NoticeText') && methods(text).includes('ResultNotice'), 'the notice has a pure wording rule and a reader');
  assert.equal(tag(text, 'NoticeText'), '', 'the wording is a pure helper');
  assert.equal(tag(text, 'ResultNotice'), '@ExecSpace("ServerOnly")\n', 'the reader reads storage on the server');
  assert.match(body(text, 'ResultNotice'), /self\._T\.outcomes\[matchKey\] or self:OutcomeFrom\(towns, matchKey\)/, 'the room that settled the match answers from memory, every other room from the record');
  assert.match(body(text, 'NoticeText'), /上一場戰果/, 'it speaks of the 戰果 of the glossary');
  assert.doesNotMatch(body(text, 'NoticeText'), /勝利|落敗|平手/, 'the record holds no win or loss for the player, so the text claims none');
});

// ---- the last town a player stood in is kept, so a login can bring them back ---------------------------------------------------

test('the last town is one small per-profile key written through the storage boundary, best effort, one write at a time', () => {
  const text = war();
  assert.match(text, /property string TownKey = "CountryWarTownV1"/, 'a key of its own next to the faction key');
  for (const name of ['ReadTown', 'Remember', 'StoreTown']) assert.ok(methods(text).includes(name), `${name} exists`);
  assert.match(body(text, 'ReadTown'), /_FormationStorage:Read\(profile, self\.TownKey/, 'it reads through the same boundary as the faction');
  assert.match(body(text, 'ReadTown'), /complete\(nil\)/, 'a storage error or a value that is no town reads as unreadable, never as a guess');
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
  assert.match(place, /cause ~= "enter" or here ~= "formationlobby" or owned/, 'only a fresh arrival in the lobby that no ticket owns is brought to a town');
  assert.match(place, /self:Landing\(faction, home, towns\)/, 'home if the faction still holds it (or holds it again), else the capital');
  const lobby = place.slice(place.indexOf('cause ~= "enter"'));
  assert.ok(lobby.indexOf('ReadFaction') < lobby.indexOf('ReadTown(') && lobby.indexOf('ReadTown(') < lobby.indexOf('ReadTowns'), 'faction first, then the last town, then the board');
  assert.match(place, /faction == "" or home == ""/, 'a player with no faction or no last town stays where they are');
  assert.match(place, /login placement unreadable/, 'unreadable data does nothing and says so');
  assert.doesNotMatch(text, /Environment:/, 'no environment branch');
  assert.match(handler(text, 'HandleUserLeaveEvent'), /placing\[event\.UserId\] = nil/, 'a leaver frees the slot');
});

test('MatchFlow hands every login to FactionWar after its own recovery, once the ticket state is settled', () => {
  const text = flow();
  assert.match(handler(text, 'HandleUserEnterEvent'), /self:Recover\(event\.UserId\)[^]*self:PlaceAtLogin\(event\.UserId, "enter"\)/, 'the arrival timer places after the recovery');
  const reconnect = handler(text, 'HandleUserReconnectEvent');
  assert.match(reconnect, /self:Recover\(event\.UserId\)[^]*self:PlaceAtLogin\(event\.UserId, "reconnect"\)/, 'a reconnect in the static room places after the recovery');
  const wrapper = body(text, 'PlaceAtLogin');
  assert.match(wrapper, /IsInstanceRoom\(\)/, 'only the static room holds the towns');
  assert.match(wrapper, /self\._T\.busy\[userId\] or self\._T\.pendingRecover\[userId\]/, 'it waits for a recovery that is still running');
  assert.match(wrapper, /self\._T\.arrival\[userId\] ~= nil/, 'a ticket that owns the player (a queue, a room, a return) keeps them');
  assert.match(wrapper, /_FactionWar:PlaceAtLogin\(userId, cause, owned\)/, 'the town judgement is FactionWar\'s');
});

test('Recover records which kind of ticket owns an arriving player, so a lobby match return stays in the lobby', () => {
  const text = flow();
  assert.match(text, /self\._T\.arrival = \{\}/, 'the hint is per room and starts empty');
  const recover = body(text, 'Recover');
  assert.match(recover, /self\._T\.arrival\[userId\] = nil/, 'a terminal or missing ticket owns nobody');
  assert.match(recover, /self\._T\.arrival\[userId\] = \(data\.origin or ""\) ~= "" and "WAR" or "LOBBY"/, 'a live ticket is a war ticket or a lobby ticket');
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
  assert.match(landing, /_FactionWarAttack:LandingFor\(userId, war\)/, 'the landing is the same rule the room-side return uses');
  assert.match(landing, /here == destination[^]*landing in place/, 'a player who already stands there is left alone, so a normal return is not moved twice');
  assert.match(landing, /_FactionWar:Move\(player, destination\)/, 'a move inside the static room is a teleport, not another room change');
  assert.match(landing, /_FactionWarAttack:ResultNotice\(/, 'the notice is built from the stored record');
  assert.match(landing, /ReceiveTownNotice\(destination, /, 'it reaches the player through the town notice');
  assert.doesNotMatch(landing, /MoveToLobby|MoveToTown/, 'the lobby-or-town decision stays in MoveHome');
  assert.match(body(text, 'MoveHome'), /_FactionWarAttack:LandingFor\(userId, ticket\)/, 'the room-side return is unchanged');
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
