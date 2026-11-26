const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');
const { MapBuilder } = require('../.agents/skills/msw-general/scripts/map/msw_map_builder.cjs');
const { ModelBuilder } = require('../.agents/skills/msw-general/scripts/model/msw_model_builder.cjs');
const { UIBuilder } = require('../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');

const TOWNS = ['nanzih', 'zuoying', 'gushan', 'yancheng'];
const source = path => fs.readFileSync(path, 'utf8').replace(/\r\n/g, '\n');
const methods = text => [...text.matchAll(/^    method \w+ (\w+)\(/gm)].map(m => m[1]);
const body = (text, name) => text.match(new RegExp(`method \\w+ ${name}\\([^]*?(?=\\n    @|\\nend)`))?.[0] || '';

test('every town carries the same shared NPC on the town platform', () => {
  const model = ModelBuilder.read('RootDesk/MyDesk/Models/NPCs/FactionWarNpc.model');
  assert.ok(model.hasComponent('MOD.Core.InteractionComponent'));
  assert.ok(model.getValue('MOD.Core.SpriteRendererComponent', 'SpriteRUID'));
  for (const id of TOWNS) {
    const map = MapBuilder.read(`map/${id}.map`);
    const npc = map.listEntities().find(entity => entity.name === 'WarNpc');
    assert.ok(npc, `${id} has WarNpc`);
    assert.equal(npc.modelId, 'factionwarnpc', id);
    assert.ok(npc.componentNames.includes('script.FactionWarNpc'), id);
    const { x, y } = map.component('WarNpc', 'MOD.Core.TransformComponent').Position;
    assert.ok(x > -9 && x < 9 && y >= -0.45 && y - -0.45 < 0.5, `${id} NPC stands on the platform`);
    const gates = map.listEntities().filter(entity => entity.name.startsWith('Gate_'));
    for (const gate of gates) {
      const gx = map.component(gate.name, 'MOD.Core.TransformComponent').Position.x;
      assert.ok(Math.abs(gx - x) > 1.7, `${id} NPC does not overlap ${gate.name}`);
    }
  }
});

test('the attack panel and the siege panel are authored in the faction war UI', () => {
  const war = UIBuilder.read('ui/FactionWarGroup.ui');
  assert.equal(war.find('AttackPanel').jsonString.enable, false);
  for (const part of ['Title', 'Status']) assert.ok(war.hasComponent(`AttackPanel/Window/${part}`, 'MOD.Core.TextGUIRendererComponent'), part);
  assert.ok(war.hasComponent('AttackPanel/Window/Close', 'MOD.Core.ButtonComponent'));
  for (const row of [1, 2]) {
    assert.ok(war.hasComponent(`AttackPanel/Window/Row${row}/Option`, 'MOD.Core.ButtonComponent'), `Row${row} option`);
    assert.ok(war.hasComponent(`AttackPanel/Window/Row${row}/Note`, 'MOD.Core.TextGUIRendererComponent'), `Row${row} note`);
  }
  assert.equal(war.find('SiegePanel').jsonString.enable, false);
  for (const part of ['Origin', 'Versus', 'Target', 'Status']) assert.ok(war.hasComponent(`SiegePanel/${part}`, 'MOD.Core.TextGUIRendererComponent'), `SiegePanel/${part}`);
  assert.ok(war.hasComponent('SiegePanel/Cancel', 'MOD.Core.ButtonComponent'));
  assert.equal(war.find('QueueBar'), null, 'the queue bar is gone (#123)');
});

test('FactionWarAttack owns options, queueing, settlement and answers only authenticated callers', () => {
  const attack = source('RootDesk/MyDesk/Formations/FactionWarAttack.mlua');
  for (const name of ['Targets', 'Settle', 'RequestOptions', 'RequestAttack', 'IsEngaged']) {
    assert.ok(methods(attack).includes(name), `${name} exists`);
  }
  for (const name of ['RequestOptions', 'RequestAttack']) {
    assert.match(attack, new RegExp(`@ExecSpace\\("Server"\\)\\n    method void ${name}\\(`), `${name} is the Server RPC`);
    assert.match(body(attack, name), /senderUserId/, `${name} identifies the caller on the server`);
  }
  assert.match(body(attack, 'Settle'), /_FactionWarTownDocument:Settle\(/, 'town effects are committed by the document');
});

test('queue tickets carry the origin and target town through every layer', () => {
  assert.match(source('RootDesk/MyDesk/Formations/FormationHandoff.mlua'), /"origin", "target"/, 'the handoff metadata keeps the towns');
  const flow = source('RootDesk/MyDesk/Matchmaking/MatchFlow.mlua');
  assert.match(body(flow, 'Belongs'), /Origin/, 'a notification must match the ticket towns');
  assert.match(body(flow, 'RoomBattleAdmission'), /homeTown/, 'the match room learns both towns');
  assert.match(source('RootDesk/MyDesk/Matchmaking/MatchQueueLocal.mlua'), /Pairs/, 'the local queue pairs only mutual targets');
  const native = source('RootDesk/MyDesk/Matchmaking/MatchQueueNative.mlua');
  assert.match(native, /origin/, 'native extras carry the origin');
  assert.match(body(native, 'Enqueue'), /pair|origin/i, 'native queue name separates town pairs');
});

test('leaving the town is blocked while engaged and the result settles the towns once', () => {
  assert.match(body(source('RootDesk/MyDesk/Formations/FactionWar.mlua'), 'RequestGate'), /IsEngaged/);
  assert.match(source('RootDesk/MyDesk/Matchmaking/MatchedBattle.mlua'), /_FactionWarAttack:Settle\(/);
  for (const adapter of ['MatchTransfer', 'MatchFaults']) {
    const text = source(`RootDesk/MyDesk/Matchmaking/${adapter}.mlua`);
    assert.ok(methods(text).includes('MoveToTown'), `${adapter} can return a player to the departure town`);
  }
  const flow = source('RootDesk/MyDesk/Matchmaking/MatchFlow.mlua');
  assert.doesNotMatch(flow.replace(/method boolean MoveHome[^]*?\n    end\n/, ''), /MoveToLobby\(userId\)/, 'only MoveHome decides between lobby and town');
});
