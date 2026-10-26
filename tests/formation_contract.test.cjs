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

test('lobby hides its scene background and UI binding does not force travel', () => {
  const lobby = MapBuilder.read('map/formationlobby.map');
  assert.equal(lobby.find('Background').jsonString.enable, false);
  const source = fs.readFileSync('RootDesk/MyDesk/Formations/FormationLobby.mlua', 'utf8');
  const update = source.slice(source.indexOf('method void OnUpdate('), source.indexOf('method void UpdateLobbyPlayer('));
  assert.doesNotMatch(update, /self:Travel\("formationlobby"\)/);
  assert.match(update, /_FormationService:RequestOpen\(\)/);
});

test('native login destination is configured on the server before players spawn', () => {
  const source = fs.readFileSync('RootDesk/MyDesk/Formations/FormationService.mlua', 'utf8');
  assert.match(source, /@ExecSpace\("ServerOnly"\)\s+method void OnBeginPlay\(\)[\s\S]*?_DefaultUserEnterLeaveLogic.StartPoint = "\/maps\/formationlobby"/);
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

test('every map preserves the template formation terrain and coordinate system', () => {
  const reference = MapBuilder.read('map/template.map');
  const terrain = map => {
    const component = map.component('RectTileMap', 'MOD.Core.RectTileMapComponent');
    return {
      ...component,
      tileMap: [...map.getTiles()].sort((a, b) => a.position.x - b.position.x || a.position.y - b.position.y),
    };
  };
  for (const file of fs.readdirSync('map').filter(name => name.endsWith('.map'))) {
    const map = MapBuilder.read(`map/${file}`);
    assert.equal(map.getTileMapMode(), reference.getTileMapMode(), file);
    assert.deepEqual(terrain(map), terrain(reference), `${file}: formation terrain differs from template`);
    assert.deepEqual(map.component('RectTileMap', 'MOD.Core.TransformComponent'),
      reference.component('RectTileMap', 'MOD.Core.TransformComponent'), `${file}: tile coordinate transform differs from template`);
  }
});

test('simulation and matched battlefield share the template camera and symmetric walkable area', () => {
  const reference = MapBuilder.read('map/template.map');
  for (const name of ['formationsim', 'matchprobe']) {
    const map = MapBuilder.read(`map/${name}.map`);
    assert.equal(map.getTileMapMode(), 1);
    for (const component of ['MOD.Core.TransformComponent', 'MOD.Core.CameraComponent']) {
      const expected = reference.component('BattleCameraAnchor', component);
      assert.deepEqual(map.component('BattleCameraAnchor', component), expected);
    }
  }
  const simulation = MapBuilder.read('map/formationsim.map');
  assert.ok(simulation.listEntities().find(e => e.name === 'formationsim').componentNames.includes('script.FormationMapInput'));
  assert.ok(simulation.listEntities().find(e => e.name === 'formationsim').componentNames.includes('script.BattleFixedCamera'));
  const palette = JSON.parse(fs.readFileSync('RootDesk/MyDesk/NewTileSet.tileset', 'utf8')).ContentProto.Json.datas;
  const tiles = new Map(reference.getTiles().map(t => [`${t.position.x},${t.position.y}`, t]));
  assert.equal(tiles.size, 209);
  for (let y = -4; y <= 4; y++) {
    for (let x = -8; x <= 8; x++) {
      const tile = tiles.get(`${x},${y}`);
      assert.ok(tile, `floor ${x},${y}`);
      assert.equal(palette[tile.tileIndex].IsCollidable, false);
    }
  }
  for (let y = -5; y <= 5; y++) {
    for (let x = -9; x <= 9; x++) {
      const tile = tiles.get(`${x},${y}`);
      const mirror = tiles.get(`${-x},${y}`);
      assert.equal(palette[tile.tileIndex].IsCollidable, palette[mirror.tileIndex].IsCollidable);
      if (x === -9 || x === 9 || y === -5 || y === 5) assert.equal(palette[tile.tileIndex].IsCollidable, true);
    }
  }
  assert.deepEqual(reference.component('BattleCameraAnchor', 'MOD.Core.TransformComponent').Position, {x: 0, y: 0, z: 0});
  assert.deepEqual(reference.component('RectTileMap', 'MOD.Core.TransformComponent').Position, {x: 0, y: 0, z: 1000});
  const camera = reference.component('BattleCameraAnchor', 'MOD.Core.CameraComponent');
  assert.equal(camera.ZoomRatio, 60);
  assert.deepEqual(camera.CameraOffset, {x: 0.5, y: 0});
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
