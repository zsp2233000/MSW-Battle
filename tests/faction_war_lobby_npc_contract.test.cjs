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

test('every town has a lobby NPC that stands apart from the attack NPC and the gates', () => {
  const model = ModelBuilder.read('RootDesk/MyDesk/Models/NPCs/FactionWarLobbyNpc.model');
  assert.ok(model.hasComponent('MOD.Core.InteractionComponent'));
  const lobbySprite = model.getValue('MOD.Core.SpriteRendererComponent', 'SpriteRUID');
  const attackSprite = ModelBuilder.read('RootDesk/MyDesk/Models/NPCs/FactionWarNpc.model').getValue('MOD.Core.SpriteRendererComponent', 'SpriteRUID');
  assert.ok(lobbySprite && lobbySprite !== attackSprite, 'a different NPC look tells the two apart');
  for (const id of TOWNS) {
    const map = MapBuilder.read(`map/${id}.map`);
    const npc = map.listEntities().find(entity => entity.name === 'LobbyNpc');
    assert.ok(npc, `${id} has LobbyNpc`);
    assert.equal(npc.modelId, 'factionwarlobbynpc', id);
    assert.ok(npc.componentNames.includes('script.FactionWarLobbyNpc'), id);
    const x = map.component('LobbyNpc', 'MOD.Core.TransformComponent').Position.x;
    const others = map.listEntities().filter(entity => entity.name === 'WarNpc' || entity.name.startsWith('Gate_'));
    assert.ok(others.length >= 2, id);
    for (const other of others) {
      const ox = map.component(other.name, 'MOD.Core.TransformComponent').Position.x;
      assert.ok(Math.abs(ox - x) > 1.7, `${id} LobbyNpc does not overlap ${other.name}`);
    }
  }
});

test('the town lobby panel opens over the town and has its own close button above it', () => {
  const war = UIBuilder.read('ui/FactionWarGroup.ui');
  assert.ok(war.hasComponent('LobbyClose', 'MOD.Core.ButtonComponent'));
  assert.equal(war.find('LobbyClose').jsonString.enable, false);
  const lobby = source('RootDesk/MyDesk/Formations/FormationLobby.mlua');
  for (const name of ['OpenTownPanel', 'CloseTownPanel', 'OnLobbyScreen']) assert.ok(methods(lobby).includes(name), name);
  for (const name of ['Render', 'SelectLobbySlot']) assert.match(body(lobby, name), /OnLobbyScreen\(/, `${name} follows the lobby screen, not the map name`);
  assert.match(source('RootDesk/MyDesk/Formations/FormationLobbyIdentity.mlua'), /OnLobbyScreen\(/, 'the portrait follows the panel too');
  assert.match(body(source('RootDesk/MyDesk/Formations/FactionWarUI.mlua'), 'OnUpdate'), /LobbyClose/, 'the close button is bound');
  assert.match(source('RootDesk/MyDesk/Formations/FactionWarLobbyNpc.mlua'), /_FormationLobby:OpenTownPanel\(\)/);
});

test('travel from a town stays behind the same engaged lock as from the lobby', () => {
  const travel = body(source('RootDesk/MyDesk/Formations/FormationService.mlua'), 'RequestTravel');
  assert.doesNotMatch(travel, /_FactionWar:IsTown/, 'a town player may travel to the editor');
  assert.match(travel, /_FormationHandoff:IsLockedForUser\(senderUserId\)/, 'a queued or matched player still cannot travel');
});
