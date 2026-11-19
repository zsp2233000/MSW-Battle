const assert = require('node:assert/strict');
const test = require('node:test');
const { MapBuilder } = require('../.agents/skills/msw-general/scripts/map/msw_map_builder.cjs');
const { UIBuilder } = require('../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');

test('the four walkable towns have only the authored one-hop connections', () => {
  const towns = {
    nanzih: ['zuoying'],
    zuoying: ['nanzih', 'gushan'],
    gushan: ['zuoying', 'yancheng'],
    yancheng: ['gushan'],
  };

  for (const [id, neighbors] of Object.entries(towns)) {
    const map = MapBuilder.read(`map/${id}.map`);
    assert.equal(map.getTileMapMode(), 1, id);
    assert.equal(map.getMapInfo().IsInstanceMap, false, id);
    assert.ok(map.getMapInfo().tileCount > 0, id);
    assert.ok(map.find('TownArrival'), id);
    const exits = map.listEntities().filter(entity => entity.name.startsWith('Gate_'));
    assert.deepEqual(exits.map(exit => exit.name.slice('Gate_'.length)).sort(), neighbors.sort(), id);
    for (const exit of exits) {
      assert.ok(map.component(exit.name, 'MOD.Core.InteractionComponent'), exit.path);
      assert.ok(map.component(exit.name, 'MOD.Core.SpriteRendererComponent').SpriteRUID, exit.path);
    }
  }
});

test('lobby entry, faction selection, and the shared town HUD are authored', () => {
  const war = UIBuilder.read('ui/FactionWarGroup.ui');
  assert.ok(war.hasComponent('LobbyEntry', 'MOD.Core.ButtonComponent'));
  assert.equal(war.find('LobbyEntry').jsonString.enable, false);
  assert.equal(war.find('FactionChoice').jsonString.enable, false);
  assert.equal(war.find('TownHUD').jsonString.enable, false);
  for (const button of ['Red', 'Blue', 'Close']) {
    assert.ok(war.hasComponent(`FactionChoice/Window/${button}`, 'MOD.Core.ButtonComponent'));
  }
  assert.ok(war.hasComponent('TownHUD/Strength', 'MOD.Core.TextGUIRendererComponent'));
  assert.equal(war.getComponent('TownHUD', 'MOD.Core.UITransformComponent').AnchorsMin.y, 1);
});
