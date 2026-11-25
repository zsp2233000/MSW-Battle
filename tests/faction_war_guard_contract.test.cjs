const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');

const TOWNS = ['nanzih', 'zuoying', 'gushan', 'yancheng'];
const source = path => fs.readFileSync(path, 'utf8').replace(/\r\n/g, '\n');
const methods = text => [...text.matchAll(/^    method \w+ (\w+)\(/gm)].map(m => m[1]);
const body = (text, name) => text.match(new RegExp(`method \\w+ ${name}\\([^]*?(?=\\n    @|\\n    method|\\nend)`))?.[0] || '';
const guard = () => source('RootDesk/MyDesk/Formations/FactionWarGuard.mlua');
const flow = () => source('RootDesk/MyDesk/Matchmaking/MatchFlow.mlua');
const attack = () => source('RootDesk/MyDesk/Formations/FactionWarAttack.mlua');
const monsterIds = () => new Set(source('RootDesk/MyDesk/Data/MonsterData.csv').split('\n').slice(1).map(line => line.split(',')[0]).filter(Boolean));

test('every town has a guard formation made of catalog monsters on the left deployment side', () => {
  const text = guard();
  for (const name of ['Profile', 'IsGuardProfile', 'TownOf', 'Roster']) assert.ok(methods(text).includes(name), `${name} exists`);
  assert.match(text, /property integer WaitSeconds = 10\b/, 'the wait is ten seconds');
  const known = monsterIds();
  for (const town of TOWNS) {
    const block = text.match(new RegExp(`${town} = \\{([^]*?)\\n        \\},?\\n`))?.[1] || '';
    const units = [...block.matchAll(/\{ monsterId = "(\w+)", x = (-?[\d.]+), y = (-?[\d.]+) \}/g)];
    assert.ok(units.length >= 1 && units.length <= 6, `${town} has one to six guards`);
    const spots = new Set();
    for (const [, id, x, y] of units) {
      assert.ok(known.has(id), `${town}: ${id} is a catalog monster`);
      assert.ok(Number(x) < 0, `${town}: guards are placed on the left like any formation, the match mirrors the away side`);
      assert.ok(!spots.has(`${x},${y}`), `${town}: no two guards share a spot`);
      spots.add(`${x},${y}`);
    }
  }
});

test('a guard profile is told apart by its prefix and never collides with a player profile', () => {
  const text = guard();
  assert.match(text, /property string ProfilePrefix = "guard:"/, 'the guard profile is guard:<town>');
  assert.match(body(text, 'Profile'), /ProfilePrefix/);
  assert.match(body(text, 'IsGuardProfile'), /ProfilePrefix/);
  assert.doesNotMatch(text, /@ExecSpace\("Client/, 'the helpers are callable on the server and the client');
});

test('the queue starts a ten second guard clock and converts a still-waiting ticket into one guard match', () => {
  const text = flow();
  for (const name of ['StartGuardClock', 'ClearGuardClock', 'GuardFire', 'Pairing', 'IsGuard']) assert.ok(methods(text).includes(name), `${name} exists`);
  assert.match(body(text, 'SubmitQueue'), /StartGuardClock/, 'a war queue starts the clock once the adapter accepted it');
  assert.match(body(text, 'SubmitQueue'), /guarding/, 'a guard claim removes the ticket from the human pool');
  const fire = body(text, 'GuardFire');
  assert.match(fire, /state ~= "QUEUED"|state == "QUEUED"/, 'only a still-queued ticket can be converted');
  assert.match(fire, /CancelMatching/, 'the adapter must confirm the ticket left the human pool before a guard match starts');
  assert.match(fire, /:Lookup\(/,'a pairing the adapter still holds wins over the guard');
  assert.match(fire, /RetrySeconds/, 'a withdrawal the adapter could not confirm is retried, not abandoned');
  assert.match(body(text, 'ResumeDeferredMatch'), /guardPairing/, 'a deferred guard claim resumes with its own pairing');
  assert.match(fire, /guard = true/, 'the guard pairing is marked in the pairing itself');
  assert.match(fire, /Matched\(userId, ticket, /, 'the guard match goes through the one match path');
  assert.match(body(text, 'Matched'), /guarding/, 'a human result that arrives during the claim is deferred like a cancellation');
  assert.match(body(text, 'Matched'), /ClearGuardClock/, 'a human match ends the countdown');
  assert.match(body(text, 'CancelForUser'), /ClearGuardClock/, 'cancelling ends the countdown');
  assert.match(body(text, 'Depart'), /guardTimers/, 'leaving drops the countdown');
});

test('the guard pairing is read back from the ticket, so no adapter has to know about it', () => {
  const text = flow();
  assert.match(body(text, 'Pairing'), /\.guard == true/);
  assert.match(body(text, 'Recover'), /Pairing\(/, 'recovery looks the pairing up through Pairing');
  assert.doesNotMatch(body(text, 'Recover'), /QueueAdapter\(\):Lookup/, 'recovery never asks the adapter about a guard match');
  assert.match(body(text, 'Rendezvous'), /\.guard/, 'a guard match has no peer to wait for and is admitted at once');
  assert.match(body(text, 'RoomBattleAdmission'), /guard/, 'the match room admits the lone player against the guard');
  assert.match(body(text, 'PublishState'), /guardAt/, 'the clients see when the guard comes');
});

test('the battle fields the guard from the town roster and never settles a profile for it', () => {
  const battle = source('RootDesk/MyDesk/Matchmaking/MatchedBattle.mlua');
  assert.match(battle, /_FactionWarGuard:Roster\(/, 'the away side is the town guard roster');
  assert.match(battle, /"GUARD"/, 'the settlement knows it was a guard match');
  const session = source('RootDesk/MyDesk/Combat/BattleSession.mlua');
  assert.match(body(session, 'InitializeMatchedBattle'), /IsGuardProfile/, 'only the guard profile may be absent from the room');
  assert.match(session, /IsGuardProfile\(self\.AwayProfile\)/, 'the guard earns no monster experience record');
  assert.match(source('RootDesk/MyDesk/Combat/BattleView.mlua'), /IsGuardProfile/, 'the opponent avatar is named as the guard');
});

test('the attack flow forwards the match kind to the town document', () => {
  assert.match(body(attack(), 'Settle'), /_FactionWarTownDocument:Settle\([^]*kind = kind/);
});

test('the queue bar shows the guard countdown and then the guard fight', () => {
  const ui = source('RootDesk/MyDesk/Formations/FactionWarUI.mlua');
  assert.match(body(ui, 'QueueView'), /guardAt/, 'the countdown is computed from the server clock');
  assert.match(body(ui, 'QueueView'), /守衛/, 'the text names the guard');
});
