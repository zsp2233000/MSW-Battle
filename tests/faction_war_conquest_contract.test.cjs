const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');

// Structural contract for #107 capture and eviction, with ADR 0016 landing back at the origin or capital.
// The Maker conquest probes exercise the seams pinned here; see tests/README.md for run status.
const source = path => fs.readFileSync(path, 'utf8').replace(/\r\n/g, '\n');
const methods = text => [...text.matchAll(/^    method \w+ (\w+)\(/gm)].map(m => m[1]);
const body = (text, name) => text.match(new RegExp(`method \\w+ ${name}\\([^]*?(?=\\n    @|\\n    method|\\n    handler|\\nend)`))?.[0] || '';
const war = () => source('RootDesk/MyDesk/Formations/FactionWar.mlua');
const attack = () => source('RootDesk/MyDesk/Formations/FactionWarAttack.mlua');
const flow = () => source('RootDesk/MyDesk/Matchmaking/MatchFlow.mlua');
const ui = () => source('RootDesk/MyDesk/Formations/FactionWarUI.mlua');

test('the gate uses the shared town document for passage rules', () => {
  assert.match(body(war(), 'RequestGate'), /_FactionWarTownDocument:CanPass\(/);
});

// Capture, capital protection, idempotency and history are exercised through Apply/Settle
// in faction_war_town_document_local.cjs and the Maker settlement probes.

test('a settlement reports a structured outcome and remembers it per match so a repeat answers the same thing', () => {
  const text = attack();
  const finish = body(text, 'Finish');
  assert.match(finish, /complete\(status, detail, outcome\)/, 'the caller gets the document outcome as a third value');
  assert.match(finish, /_FactionWar:AnnounceFall\(/, 'a final flip is announced to the people standing in that town');
  assert.match(finish, /_FactionWarLanding:RememberOutcome\(matchKey, outcome\)/, 'the room remembers the outcome for battle notices');
});

test('return dispatches war landings through the transfer adapter, and keeps lobby returns separate', () => {
  const home = body(flow(), 'MoveHome');
  assert.match(home, /_FactionWarLanding:Judge\(userId, \{ kind = "RETURN"/);
  assert.match(home, /MoveToTown\(userId, /, 'the same adapter boundary moves the player');
  assert.match(home, /MoveToLobby\(userId\)/, 'a lobby ticket still returns to the lobby');
});

test('a fallen town is emptied in the static room: waiting tickets are cancelled first, matched ones are left alone', () => {
  const text = war();
  for (const name of ['AnnounceFall', 'SweepFallen']) assert.ok(methods(text).includes(name), `${name} exists`);
  assert.match(body(text, 'AnnounceFall'), /IsInstanceRoom\(\)/, 'a settlement in a match room has to cross to the static room');
  assert.match(body(text, 'AnnounceFall'), /RequestSendEventToRoomAsync\(event, _RoomService\.StaticRoomKey/, 'the news goes to the static room, where every town map lives');
  assert.match(text, /@EventSender\("Service", "RoomService"\)\n    handler HandleTownFellEvent\(TownFellEvent event\)/, 'the static room listens for it');
  assert.match(source('RootDesk/MyDesk/Formations/TownFellEvent.mlua'), /script TownFellEvent extends EventType[^]*property string Town[^]*property string Owner/, 'the event names the town and its new owner');
  assert.match(body(text, 'SweepFallen'), /CurrentMapName == town/, 'everybody standing in the town is considered');
  assert.match(body(text, 'SweepFallen'), /_FactionWarTownDocument:Read\(/, 'the live table decides, not the event');
  assert.match(body(text, 'SweepFallen'), /_FactionWarLanding:Judge\(userId, \{ kind = "CHECK"/);
  const vacate = body(flow(), 'Vacate');
  assert.match(vacate, /IsWaiting\(ticket\)/, 'only a ticket still waiting for an opponent can be cancelled (the review tightened this from CanCancel, see faction_war_review_contract.test.cjs)');
  assert.match(vacate, /CancelForUser\(userId\)/, 'the common cancellation path is used');
  assert.match(vacate, /return false/, 'a matched ticket keeps its place');
});

test('a player who missed the announcement is moved the next time they act in a town they no longer own', () => {
  const text = war();
  for (const [script, method] of [[text, 'RequestTownStatus'], [text, 'RequestGate'], [attack(), 'SelectFor']]) {
    assert.match(body(script, method), /_FactionWarLanding:Judge\(userId, \{ kind = "CHECK"/);
  }
});

test('the town HUD keeps a relocation notice until the player has arrived', () => {
  const text = ui();
  assert.match(body(text, 'ShowTownNotice'), /self\._T\.mapName ~= town or not self:IsCurrentTown\(town\)[^]*arrivalNotice/, 'a notice before map sync or before the HUD enters the town is kept');
  assert.match(body(text, 'EnterMap'), /self\._T\.mapName = name[^]*arrival\.town == name then self:ShowTownNotice\(name, arrival\.message\)[^]*self\._T\.arrivalNotice = nil/, 'the destination town shows it once on arrival');
});
