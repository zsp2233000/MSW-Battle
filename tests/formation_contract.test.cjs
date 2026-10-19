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

test('first formation has explicit save, activation, retry and placement controls', () => {
  const ui = UIBuilder.read('ui/FormationGroup.ui');
  for (const name of ['Lobby/Edit', 'Editor/Save', 'Editor/Activate', 'Retry', 'Editor/Board', 'Editor/Remove']) {
    assert.ok(ui.find(name), name);
  }
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
