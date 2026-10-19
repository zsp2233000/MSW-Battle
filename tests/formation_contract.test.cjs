const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');
const { MapBuilder } = require('../.agents/skills/msw-general/scripts/map/msw_map_builder.cjs');
const { UIBuilder } = require('../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');

test('personal lobby and simulation are reachable RectTile maps without battle controllers', () => {
  for (const name of ['formationlobby', 'formationsim']) {
    const map = MapBuilder.read(`map/${name}.map`);
    assert.equal(map.getTileMapMode(), 1);
    assert.ok(map.listEntities().every(e => !e.componentNames.includes('script.BattleSession')));
  }
});

test('five formations expose stable selectors in lobby and editor with explicit save and activation', () => {
  const ui = UIBuilder.read('ui/FormationGroup.ui');
  for (const name of ['Lobby/Edit', 'Editor/Save', 'Editor/Activate', 'Retry', 'Editor/Remove']) {
    assert.ok(ui.find(name), name);
  }
  for (const screen of ['Lobby', 'Editor']) {
    for (let slot = 1; slot <= 5; slot++) {
      const path = `${screen}/Slots/Slot${slot}`;
      assert.ok(ui.find(path), path);
      assert.ok(ui.hasComponent(path, 'MOD.Core.ButtonComponent'), path);
    }
  }
  assert.equal(ui.find('Editor/Board'), null, 'formation placement is in world space');
  const dock = ui.listEntities().find(e => e.path === '/ui/FormationGroup/Editor');
  assert.ok(dock.size[1] <= 350, 'editor controls leave the terrain visible');
});

test('formation simulation retains map01 terrain, dimensions and camera framing', () => {
  const reference = MapBuilder.read('map/map01.map');
  const simulation = MapBuilder.read('map/formationsim.map');
  assert.deepEqual(simulation.getTileBounds(), reference.getTileBounds());
  assert.deepEqual(simulation.component('RectTileMap', 'MOD.Core.RectTileMapComponent'), reference.component('RectTileMap', 'MOD.Core.RectTileMapComponent'));
  for (const component of ['MOD.Core.TransformComponent', 'MOD.Core.CameraComponent']) {
    assert.deepEqual(simulation.component('BattleCameraAnchor', component), reference.component('BattleCameraAnchor', component));
  }
  assert.ok(simulation.listEntities().find(e => e.name === 'formationsim').componentNames.includes('script.FormationMapInput'));
  assert.ok(simulation.listEntities().find(e => e.name === 'formationsim').componentNames.includes('script.BattleFixedCamera'));
});

test('private map previews contain renderers without AI or combat components', () => {
  const { ModelBuilder } = require('../.agents/skills/msw-general/scripts/model/msw_model_builder.cjs');
  const preview = ModelBuilder.snapshot('RootDesk/MyDesk/Models/MapObjects/FormationPreview.model');
  assert.ok(preview.components.includes('MOD.Core.SpriteRendererComponent'));
  assert.ok(preview.components.every(c => !/BattleUnit|Attack|HitComponent|AIComponent/.test(c)));
});

test('private formation RPCs accept no player identity or combat statistics', () => {
  const source = fs.readFileSync('RootDesk/MyDesk/Formations/FormationService.mlua', 'utf8');
  const rpc = [...source.matchAll(/@ExecSpace\("Server"\)\s+method \w+ (\w+)\(([^)]*)\)([\s\S]*?)(?=\n    @ExecSpace|\nend)/g)];
  assert.ok(rpc.length >= 5);
  for (const [, name, args, body] of rpc) {
    assert.doesNotMatch(args, /userId|profileCode|Hp|Damage/);
    assert.match(body, /senderUserId/, name);
  }
  const storage = fs.readFileSync('RootDesk/MyDesk/Formations/FormationStorage.mlua', 'utf8');
  assert.match(storage, /UpdateAsync/);
  assert.match(storage, /GetUserDataStorage/);
  assert.doesNotMatch(source, /@Sync/);
});
