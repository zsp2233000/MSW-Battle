const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');

// Structural contract for #107 (a captured town changes flag, the conqueror walks in, the losers go home).
// The behaviour itself is proven by tests/faction_war_conquest_runtime_probe.lua and
// tests/faction_war_conquest_e2e_runtime_probe.lua in Maker; these tests pin the seams those probes drive.
const source = path => fs.readFileSync(path, 'utf8').replace(/\r\n/g, '\n');
const methods = text => [...text.matchAll(/^    method \w+ (\w+)\(/gm)].map(m => m[1]);
const body = (text, name) => text.match(new RegExp(`method \\w+ ${name}\\([^]*?(?=\\n    @|\\n    method|\\n    handler|\\nend)`))?.[0] || '';
const war = () => source('RootDesk/MyDesk/Formations/FactionWar.mlua');
const attack = () => source('RootDesk/MyDesk/Formations/FactionWarAttack.mlua');
const flow = () => source('RootDesk/MyDesk/Matchmaking/MatchFlow.mlua');
const ui = () => source('RootDesk/MyDesk/Formations/FactionWarUI.mlua');

test('FactionWar decides where a faction may stand: its own capital is the one landing that never changes hands', () => {
  const text = war();
  for (const name of ['CapitalOf', 'Landing', 'CanPass']) assert.ok(methods(text).includes(name), `${name} exists`);
  assert.match(text, /property table CapitalByFaction = \{ RED = "nanzih", BLUE = "yancheng" \}/, 'the capital of each faction');
  assert.match(body(text, 'Landing'), /\.owner == faction/, 'a town is a landing only while the faction owns it');
  assert.match(body(text, 'Landing'), /CapitalOf/, 'every other answer is the capital');
  assert.doesNotMatch(text, /@ExecSpace\("\w+"\)\n    method \w+ (CapitalOf|Landing|CanPass)\(/, 'the rules are plain helpers like IsTown, not RPC surface');
  assert.match(body(text, 'RequestGate'), /CanPass\(/, 'the gate and the probes share one passage rule');
});

test('a town that reaches zero strength changes flag and refills in the same stored document', () => {
  const text = attack();
  assert.match(text, /property integer FullStrength = 100\b/, 'a captured town refills to the full strength the storage decoder allows');
  const attempt = body(text, 'Attempt');
  assert.doesNotMatch(attempt, /math\.max\(1,/, 'strength is no longer clamped above zero');
  assert.match(attempt, /<= 0/, 'zero strength is the capture condition');
  assert.match(attempt, /owner = towns\[operation\.winner\]\.owner/, 'the winner side\'s current owner takes the town');
  assert.match(attempt, /strength = self\.FullStrength/, 'the flip is written as owner + full strength, never as a zero');
  assert.equal(attempt.match(/WriteTowns\(/g).length, 1, 'ownership and strength are one document write');
  assert.match(source('RootDesk/MyDesk/Formations/FactionWar.mlua'), /town\.strength < 1 or town\.strength > 100/, 'the decoder still rejects a stored zero');
});

test('a settlement reports a structured outcome and remembers it per match so a repeat answers the same thing', () => {
  const text = attack();
  assert.ok(methods(text).includes('EntryKey'), 'settled entries are read through one helper that accepts legacy match keys');
  const attempt = body(text, 'Attempt');
  assert.match(attempt, /k = operation\.matchKey/, 'the settled list stores the key');
  assert.match(attempt, /\bw = operation\.winner\b.*\bl = operation\.loser\b/s, 'and who beat whom');
  assert.match(attempt, /"DUPLICATE"/, 'a repeat is still reported');
  assert.match(attempt, /operation\.flipped = /, 'a repeat restores whether this match flipped the town');
  const finish = body(text, 'Finish');
  assert.match(finish, /operation\.complete\(status, detail, outcome\)/, 'the caller gets the outcome as a third value');
  assert.match(finish, /flipped = /, 'the outcome says whether the town changed hands');
  assert.match(finish, /_FactionWar:AnnounceFall\(/, 'a final flip is announced to the people standing in that town');
  assert.match(finish, /self\._T\.outcomes\[/, 'the room remembers the outcome for the players who return from it');
  assert.match(body(text, 'OnBeginPlay'), /_T\.outcomes = \{\}/);
});

test('a capital still never loses strength or changes owner', () => {
  const text = attack();
  assert.match(body(text, 'Deduction'), /IsCapital\(target\)\) then return 0|IsCapital\(target\) then return 0/, 'a win over a capital deducts nothing');
  assert.match(body(text, 'Settle'), /amount == 0/, 'a zero deduction never reaches the storage write');
});

test('returning from a war match lands by the match outcome and live ownership, never blindly at the departure town', () => {
  const landing = body(attack(), 'LandingFor');
  assert.match(landing, /outcome\.flipped and outcome\.winner == origin/, 'only the side that won the flipping match walks into the conquered town');
  assert.match(landing, /_FactionWar:Landing\(faction, preferred, towns\)/, 'ownership is judged on the live town table');
  assert.match(landing, /self\._T\.settling\[matchKey\]/, 'a fast return waits for the settlement write');
  assert.match(landing, /return origin/, 'unreadable storage falls back to the previous behaviour');
  const home = body(flow(), 'MoveHome');
  assert.match(home, /_FactionWarAttack:LandingFor\(userId, ticket\)/, 'the town return asks for its landing');
  assert.match(home, /MoveToTown\(userId, /, 'the same adapter boundary moves the player');
  assert.match(home, /MoveToLobby\(userId\)/, 'a lobby ticket still returns to the lobby');
});

test('a fallen town is emptied in the static room: waiting tickets are cancelled first, matched ones are left alone', () => {
  const text = war();
  for (const name of ['AnnounceFall', 'SweepFallen', 'Enforce', 'Evict']) assert.ok(methods(text).includes(name), `${name} exists`);
  assert.match(body(text, 'AnnounceFall'), /IsInstanceRoom\(\)/, 'a settlement in a match room has to cross to the static room');
  assert.match(body(text, 'AnnounceFall'), /RequestSendEventToRoomAsync\(event, _RoomService\.StaticRoomKey/, 'the news goes to the static room, where every town map lives');
  assert.match(text, /@EventSender\("Service", "RoomService"\)\n    handler HandleTownFellEvent\(TownFellEvent event\)/, 'the static room listens for it');
  assert.match(source('RootDesk/MyDesk/Formations/TownFellEvent.mlua'), /script TownFellEvent extends EventType[^]*property string Town[^]*property string Owner/, 'the event names the town and its new owner');
  assert.match(body(text, 'SweepFallen'), /CurrentMapName == town/, 'everybody standing in the town is considered');
  assert.match(body(text, 'SweepFallen'), /ReadTowns/, 'the live table decides, not the event');
  const evict = body(text, 'Evict');
  assert.match(evict, /self:Landing\(faction, town, towns\)/, 'the faction of the player decides whether they stay');
  assert.ok(evict.indexOf('_MatchFlow:Vacate(userId)') > -1 && evict.indexOf('_MatchFlow:Vacate(userId)') < evict.indexOf('self:Move('), 'the queue is released before the move');
  assert.match(evict, /ReceiveTownNotice/, 'the player is told why they moved');
  const vacate = body(flow(), 'Vacate');
  assert.match(vacate, /CanCancel\(ticket\)/, 'only a waiting ticket can be cancelled');
  assert.match(vacate, /CancelForUser\(userId\)/, 'the common cancellation path is used');
  assert.match(vacate, /return false/, 'a matched ticket keeps its place');
});

test('a player who missed the announcement is moved the next time they act in a town they no longer own', () => {
  const text = war();
  assert.match(body(text, 'RequestTownStatus'), /self:Enforce\(/, 'entering a town re-checks ownership');
  assert.match(body(text, 'RequestGate'), /self:Enforce\(/, 'a refused gate in a fallen town sends the player home');
  assert.match(body(attack(), 'OptionsFor'), /_FactionWar:Enforce\(/, 'the NPC does not just say "not yours", it moves the player');
  assert.match(body(text, 'Enforce'), /evicting/, 'one eviction per player at a time');
  assert.match(text, /handler HandleUserLeaveEvent[^]*evicting\[event\.UserId\] = nil/, 'a leaver does not keep the guard');
});

test('the town HUD keeps a relocation notice until the player has arrived', () => {
  const text = ui();
  assert.match(body(text, 'ShowTownNotice'), /arrivalNotice/, 'a notice that beats the map change is kept');
  assert.match(body(text, 'EnterMap'), /arrivalNotice/, 'the destination town shows it on arrival');
});
