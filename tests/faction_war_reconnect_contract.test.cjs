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
