const assert = require('node:assert/strict');
const test = require('node:test');
const { MapBuilder } = require('../.agents/skills/msw-general/scripts/map/msw_map_builder.cjs');
const { UIBuilder } = require('../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');

test('the four MapleTile towns share one level platform and only the authored one-hop connections', () => {
  const towns = {
    nanzih: ['zuoying'],
    zuoying: ['nanzih', 'gushan'],
    gushan: ['zuoying', 'yancheng'],
    yancheng: ['gushan'],
  };

  for (const [id, neighbors] of Object.entries(towns)) {
    const map = MapBuilder.read(`map/${id}.map`);
    assert.equal(map.getTileMapMode(), 0, id);
    assert.equal(map.getMapInfo().IsInstanceMap, false, id);
    assert.ok(map.component('TileMap', 'MOD.Core.TileMapComponent'), id);
    assert.equal(map.find('RectTileMap'), null, id);
    const platforms = map.listEntities().filter(entity => entity.componentNames.includes('MOD.Core.CustomFootholdComponent'));
    assert.deepEqual(platforms.map(platform => platform.name), ['TownPlatform'], id);
    const [platform] = platforms;
    const [ground] = map.getFootholds();
    assert.equal(map.getFootholds().length, 1, id);
    assert.equal(ground.OwnerId, platform.id, id);
    assert.deepEqual(ground.StartPoint, { x: -9, y: -0.45 }, id);
    assert.deepEqual(ground.EndPoint, { x: 9, y: -0.45 }, id);
    const [edges] = map.component(platform.name, 'MOD.Core.CustomFootholdComponent').edgeLists;
    assert.equal(edges.length, 2, id);
    assert.equal(edges[0].y, edges[1].y, id);
    const sprite = map.component(platform.name, 'MOD.Core.SpriteRendererComponent');
    assert.ok(sprite.SpriteRUID, id);
    assert.equal(sprite.TiledSize.x, ground.Length, id);
    const exits = map.listEntities().filter(entity => entity.name.startsWith('Gate_'));
    assert.deepEqual(exits.map(exit => exit.name.slice('Gate_'.length)).sort(), neighbors.sort(), id);
    for (const exit of exits) {
      assert.ok(map.component(exit.name, 'MOD.Core.InteractionComponent'), exit.path);
      assert.ok(map.component(exit.name, 'MOD.Core.SpriteRendererComponent').SpriteRUID, exit.path);
    }
    for (const name of ['TownArrival', 'SpawnLocation', ...exits.map(exit => exit.name)]) {
      const { x, y } = map.component(name, 'MOD.Core.TransformComponent').Position;
      assert.ok(x > ground.StartPoint.x && x < ground.EndPoint.x, name);
      assert.ok(y >= ground.StartPoint.y && y - ground.StartPoint.y < 0.5, name);
    }
  }
});

test('lobby entry, faction selection, and the shared town HUD are authored', () => {
  const war = UIBuilder.read('ui/FactionWarGroup.ui');
  assert.ok(war.hasComponent('LobbyEntry', 'MOD.Core.ButtonComponent'));
  assert.equal(war.find('LobbyEntry').jsonString.enable, false);
  assert.equal(war.find('FactionChoice').jsonString.enable, false);
  assert.equal(war.find('TownHUD').jsonString.enable, false);
  for (const button of ['A', 'B', 'Close']) {
    assert.ok(war.hasComponent(`FactionChoice/Window/${button}`, 'MOD.Core.ButtonComponent'));
  }
  assert.ok(war.hasComponent('TownHUD/Strength', 'MOD.Core.TextGUIRendererComponent'));
  assert.equal(war.getComponent('TownHUD', 'MOD.Core.UITransformComponent').AnchorsMin.y, 1);
});
