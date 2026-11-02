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
  const update = source.slice(source.indexOf('method void OnUpdate('), source.indexOf('method void Travel('));
  assert.doesNotMatch(update, /self:Travel\("formationlobby"\)/);
  assert.match(update, /_FormationService:RequestOpen\(\)/);
});

test('native login destination is configured on the server before players spawn', () => {
  const source = fs.readFileSync('RootDesk/MyDesk/Formations/FormationService.mlua', 'utf8');
  assert.match(source, /@ExecSpace\("ServerOnly"\)\s+method void OnBeginPlay\(\)[\s\S]*?_DefaultUserEnterLeaveLogic.StartPoint = "\/maps\/formationlobby"/);
});

test('five formations expose stable selectors in lobby and editor with explicit save and activation', () => {
  const ui = UIBuilder.read('ui/FormationGroup.ui');
  for (const name of ['Lobby/Edit', 'Editor/Save', 'Editor/Activate', 'Retry']) {
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
  assert.equal(ui.find('Editor/AddMode'), null, 'deployment resumes by choosing a monster card');
  assert.equal(ui.find('Editor/Remove'), null, 'unit removal uses world input');
  const surface = ui.getComponent('Editor', 'MOD.Core.SpriteGUIRendererComponent');
  assert.equal(surface.RaycastTarget, false, 'editor root leaves the real battlefield clickable');
  assert.equal(surface.Color.a, 0, 'editor root leaves the real battlefield visible');
  assert.ok(ui.find('Editor/Intel/Stats'), 'tactical intelligence remains outside the details');
  for (const path of ['Editor/Intel/Portrait', 'Editor/Intel/Context', 'Editor/Selection']) {
    assert.equal(ui.find(path), null, 'compact intelligence omits duplicate art and labels');
  }
  assert.ok(ui.find('Editor/Intel/Kind'));
  const catalog = ui.getComponent('Editor/Catalog', 'MOD.Core.ScrollLayoutGroupComponent');
  const viewport = ui.getComponent('Editor/Catalog', 'MOD.Core.UITransformComponent').RectSize;
  assert.equal(catalog.ConstraintCount, 4);
  assert.ok(4 * catalog.CellSize.x + 3 * catalog.GridSpacing.x + catalog.Padding.left
    + catalog.Padding.right + catalog.ScrollBarThickness <= viewport.x, 'four cards fit beside scrollbar');
  assert.ok(2 * catalog.CellSize.y + catalog.GridSpacing.y + catalog.Padding.top
    + catalog.Padding.bottom <= viewport.y, 'two complete rows fit without scrolling');
  const {RectSize: frame} = ui.getComponent('Editor/Catalog/Template', 'MOD.Core.UITransformComponent');
  const {RectSize: sign} = ui.getComponent('Editor/Catalog/Template/CardSign', 'MOD.Core.UITransformComponent');
  assert.ok(frame.y > frame.x, 'editable Cardgame frame remains portrait');
  assert.ok(sign.y > sign.x, 'editable Cardgame ornament remains portrait');
  assert.ok(sign.x > frame.x && sign.y > frame.y, 'ornament extends beyond the frame as in the source card');
  assert.equal(ui.find('Editor/Catalog/Template/SelectedGlow/Border'), null, 'selection does not cover the ornament with a second frame');
  assert.equal(ui.hasComponent('Editor/Catalog', 'script.FormationCardLayout'), false, 'native layout owns card dimensions');
  for (const part of ['CardSign', 'PortraitViewport', 'PortraitViewport/Portrait', 'SelectedGlow']) {
    assert.equal(ui.getComponent('Editor/Catalog/Template/' + part, 'MOD.Core.UITransformComponent').AlignmentOption, 15);
  }
  for (const part of ['MonsterName', 'Identity']) {
    assert.equal(ui.getComponent('Editor/Catalog/Template/' + part, 'MOD.Core.UITransformComponent').AlignmentOption, 11);
  }
});

test('Maker exposes the editor template and each screen owns its fixed controls', () => {
  const ui = UIBuilder.read('ui/FormationGroup.ui');
  for (const path of ['Editor', 'EditorControls', 'Editor/Catalog/Template']) {
    assert.equal(ui.find(path).jsonString.enable, true, `${path} can be edited without enabling its parents`);
  }
  assert.equal(ui.find('Lobby').jsonString.enable, false, 'lobby does not obscure the authoring preview');
  assert.match(ui.getComponent('Editor/Catalog/Template/PortraitViewport/Portrait', 'MOD.Core.SpriteGUIRendererComponent').ImageRUID.DataId,
    /^thumbnail:\/\/[a-f0-9]{32}$/, 'sample portrait is visible while editing');
  for (const path of ['EditorControls/Toggle', 'EditorControls/Retry', 'Retry', 'ReturnLobby']) {
    assert.ok(ui.hasComponent(path, 'MOD.Core.ButtonComponent'), path);
  }
  assert.ok(ui.find('EditorControls/Status'));
  const match = UIBuilder.read('ui/MatchGroup.ui');
  for (const panel of ['Match', 'BattleMatch']) {
    for (const control of ['Action', 'Status', 'FixedSummary']) assert.ok(match.find(`${panel}/${control}`));
    assert.equal(match.find(panel).jsonString.enable, false, 'matchmaking panels stay hidden in Maker');
  }
  assert.equal(match.find('EditorMatch'), null, 'the editor offers no matchmaking entry (#50)');
});

const read = file => fs.readFileSync(file, 'utf8');
const method = (source, name) => {
  const start = source.indexOf(`method `);
  const at = source.search(new RegExp(`method \\w+ ${name}\\(`));
  assert.ok(at >= 0, `${name} exists`);
  const next = source.slice(at + 1).search(/\n    @ExecSpace|\n    method |\nend/);
  return source.slice(at, next < 0 ? undefined : at + 1 + next);
};

test('#50 unsaved content lives only in the client, never in server sessions, storage or handoffs', () => {
  const service = read('RootDesk/MyDesk/Formations/FormationService.mlua');
  const handoff = read('RootDesk/MyDesk/Formations/FormationHandoff.mlua');
  const lobby = read('RootDesk/MyDesk/Formations/FormationLobby.mlua');
  for (const removed of ['RequestDraft', 'UpdateDraftForUser', 'AutoSaveForMatch', 'draftVersion', 'savedDraftVersion', '.drafts', 'saveState']) {
    assert.ok(!service.includes(removed), `FormationService no longer has ${removed}`);
  }
  assert.doesNotMatch(handoff, /drafts|autoSave|\.notice/i, 'handoffs carry confirmed content only');
  assert.doesNotMatch(read('RootDesk/MyDesk/Matchmaking/MatchFlow.mlua'), /autoSave|ticket\.notice/i);
  assert.doesNotMatch(read('RootDesk/MyDesk/Matchmaking/MatchFlowInput.mlua'), /AutoSaveNotice|EditorMatch|formationsim = /, 'no editor matchmaking screen');
  const session = read('RootDesk/MyDesk/Formations/FormationEditSession.mlua');
  assert.match(session, /property table Draft = \{\}/, 'the client holds its own copy');
  for (const source of [lobby, session]) assert.doesNotMatch(source, /_FormationService:RequestDraft|_DataStorageService/, 'edits never reach the server before an explicit save');
  // The edit session never calls a service; it only returns the commands the lobby carries out.
  assert.doesNotMatch(session, /_FormationService|_DataStorageService/, 'the edit session stays free of server calls');
  // Local edits must not call any service: Place and RemoveSelected stay inside the client.
  for (const name of ['Place', 'RemoveSelected']) assert.doesNotMatch(method(session, name), /_FormationService/, name);
});

test('#50 saving submits one group with identity from the RPC sender and a version condition', () => {
  const service = read('RootDesk/MyDesk/Formations/FormationService.mlua');
  assert.match(service, /method void RequestSave\(table units, integer slotId, integer expectedRevision, string requestId\)/);
  const save = method(service, 'SaveForUser');
  assert.match(save, /slot\.revision ~= expectedRevision/, 'existing version condition');
  assert.match(save, /ValidateUnits\(units, catalog, false\)/, 'server validates monsters, count and placement; an empty group cannot be saved');
  assert.match(save, /doc\.slots\[key\]\.units = clean/, 'only the submitted group changes');
  assert.doesNotMatch(save, /activeSlot/, 'saving never changes the active group');
  const write = method(service, 'Write');
  assert.match(write, /status = timedOut and "UNCONFIRMED" or "FAILED"/, 'timeouts are reported as unconfirmed, not failed');
  assert.match(write, /status = "OK"/);
});

test('#50 client states: dirty by content comparison, three-way confirmation, no stale actions', () => {
  const lobby = read('RootDesk/MyDesk/Formations/FormationLobby.mlua');
  const session = read('RootDesk/MyDesk/Formations/FormationEditSession.mlua');
  assert.match(method(session, 'IsDirty'), /UnitsEqual\(self\.Draft, self:CurrentSavedUnits\(\)\)/, 'exact restoration clears the marker');
  assert.match(method(session, 'SaveBlockReason'), /沒有變更/);
  assert.match(method(session, 'DraftInvalidReason'), /空隊伍無法儲存/);
  // Only the reply carrying the outstanding request id may run the deferred switch or return.
  const resolve = method(session, 'ResolveResult');
  assert.match(resolve, /result\.requestId ~= awaiting\.id/);
  assert.match(resolve, /result\.status == "OK"[\s\S]*CompleteAction/);
  assert.match(method(session, 'Tick'), /self\._T\.awaiting = nil/, 'a lost reply drops the pending action');
  const confirm = method(lobby, 'RenderConfirmation');
  for (const label of ['儲存並切換', '不儲存切換', '儲存並返回', '不儲存返回', '繼續編輯', '儲存中…']) assert.ok(confirm.includes(label), label);
  assert.match(method(session, 'RequestSwitchSlot'), /Unconfirmed\(\)/, 'no switching while a write is unconfirmed');
  assert.match(method(session, 'RequestReturnToLobby'), /Unconfirmed\(\)/, 'no leaving while a write is unconfirmed');
});

test('#50 player-facing text never says draft or currently-editing', () => {
  for (const file of ['FormationLobby', 'FormationEditSession', 'FormationService', 'FormationHandoff', 'FormationCatalogCards', 'FormationLobbyPreview', 'FormationLobbyIdentity']) {
    const strings = [...read(`RootDesk/MyDesk/Formations/${file}.mlua`).matchAll(/"([^"\n]*[一-鿿][^"\n]*)"/g)].map(m => m[1]);
    for (const text of strings) assert.doesNotMatch(text, /草稿|正在編輯/, `${file}: ${text}`);
  }
  const strings = [...read('RootDesk/MyDesk/Matchmaking/MatchFlowInput.mlua').matchAll(/"([^"\n]*[一-鿿][^"\n]*)"/g)].map(m => m[1]);
  for (const text of strings) assert.doesNotMatch(text, /草稿|正在編輯/, text);
  for (const file of ['FormationGroup', 'MatchGroup']) {
    const ui = UIBuilder.read(`ui/${file}.ui`);
    for (const entity of ui.listEntities()) {
      const text = ui.getComponent(entity.path, 'MOD.Core.TextGUIRendererComponent');
      if (text) assert.doesNotMatch(String(text.Text), /草稿|正在編輯/, entity.path);
    }
  }
});

test('#50 group selectors mark the viewed and active group; save and cards use native authored states', () => {
  const ui = UIBuilder.read('ui/FormationGroup.ui');
  for (const screen of ['Lobby', 'Editor']) {
    for (let slot = 1; slot <= 5; slot++) {
      const base = `${screen}/Slots/Slot${slot}`;
      assert.equal(ui.find(`${base}/EditFrame`), null, `${base} uses button colour instead of an animated frame`);
      // The active-group marker remains independent of the viewed group's button colour.
      for (const marker of ['ActiveBadge']) {
        assert.equal(ui.find(`${base}/${marker}`).jsonString.enable, false, `${base}/${marker} starts hidden`);
        assert.ok(ui.hasComponent(`${base}/${marker}`, 'MOD.Core.SpriteGUIRendererComponent'), `${marker} is a sprite`);
        assert.equal(ui.hasComponent(`${base}/${marker}`, 'MOD.Core.TextGUIRendererComponent'), false, `${marker} is not text`);
      }
    }
  }
  const save = ui.getComponent('Editor/Save', 'MOD.Core.ButtonComponent');
  const activate = ui.getComponent('Editor/Activate', 'MOD.Core.ButtonComponent');
  for (const path of ['Editor/Save', 'Editor/Back', 'EditorControls/Toggle', 'Editor/Slots/Slot1', 'Lobby/Slots/Slot1', 'Lobby/Edit']) {
    const button = ui.getComponent(path, 'MOD.Core.ButtonComponent');
    assert.equal(button.Transition, activate.Transition, `${path} hovers with the same native sprite swap as the other buttons`);
    assert.deepEqual(button.ImageRUIDs, activate.ImageRUIDs, path);
  }
  assert.match(method(read('RootDesk/MyDesk/Formations/FormationLobby.mlua'), 'Render'), /Editor\/Save[\s\S]*canSave and Color\(1, 0\.86, 0\.5, 1\)/, 'usable save is gold');
  assert.equal(ui.getComponent('Editor/Save', 'MOD.Core.TextGUIRendererComponent').Text, '儲存隊伍');
  for (const path of ['Editor/Activate', 'Editor/Save', 'Editor/Back']) assert.equal(ui.find(path).jsonString.enable, true, `${path} is always visible`);
  assert.equal(ui.find('Editor/Slots/Slot1').jsonString.enable, true);
});

test('#50 a usable save shows the authored hint instead of blinking', () => {
  const lobby = read('RootDesk/MyDesk/Formations/FormationLobby.mlua');
  assert.match(method(lobby, 'Render'), /SetEnabled\("Editor\/Save\/SaveHint", canSave\)/);
  assert.ok(!lobby.includes('saveBlink'));
  const ui = UIBuilder.read('ui/FormationGroup.ui');
  const hint = ui.getComponent('Editor/Save/SaveHint', 'MOD.Core.SpriteGUIRendererComponent');
  assert.equal(hint.ImageRUID.DataId, 'b2ae5080eb1041b8a780a20c4b350257');
  assert.equal(hint.RaycastTarget, false, '提示圖不攔截按鈕點擊');
  assert.equal(hint.AnimClipPlayType, 1, '提示動畫必須循環播放，不能播完一次便停住');
  assert.ok(ui.find('Editor/Save/SaveHint').jsonString.enable, 'Maker 編輯時可直接調整');
  assert.ok(!lobby.includes('DirtyMark'));
  assert.equal(ui.find('Editor/Slots/Slot1/DirtyMark'), null);
});

test('#50 the viewed group uses a static button tint in both screens', () => {
  const ui = UIBuilder.read('ui/FormationGroup.ui');
  for (const screen of ['Lobby', 'Editor']) {
    for (let index = 1; index <= 5; index++) {
      const path = `${screen}/Slots/Slot${index}`;
      assert.equal(ui.find(`${path}/EditFrame`), null, '選取框與動畫已移除');
      assert.equal(ui.getComponent(path, 'MOD.Core.ButtonComponent').Transition, 2, 'native sprite swap preserves the selection tint on hover');
      assert.deepEqual(ui.getComponent(path, 'MOD.Core.SpriteGUIRendererComponent').Color, {r: 1, g: 1, b: 1, a: 1}, 'unselected colour');
    }
  }
  const render = method(read('RootDesk/MyDesk/Formations/FormationLobby.mlua'), 'Render');
  assert.match(render, /local isCurrent = index == editSlot/);
  assert.match(render, /button\.SpriteGUIRendererComponent\.Color = isCurrent and Color\(1, 0\.86, 0\.5, 1\) or Color\(1, 1, 1, 1\)/);
  assert.match(render, /SetEnabled\(base \.\. "\/ActiveBadge", isActive\)/);
});

test('#50 group selection has no pulse or renderer sorting overrides', () => {
  // OverrideSorting is read-only and OrderInLayer is only writable in World UI mode, so such writes are errors or no-ops.
  const lobby = read('RootDesk/MyDesk/Formations/FormationLobby.mlua');
  assert.doesNotMatch(lobby, /OverrideSorting|OrderInLayer/);
  assert.doesNotMatch(lobby, /PulseSlotFrames|frameBars|self\._T\.pulse|EditFrame/, 'group selection does no per-frame animation work');
});

test('#50 review fixes: no silent drops while a request is outstanding', () => {
  const lobby = read('RootDesk/MyDesk/Formations/FormationLobby.mlua');
  const service = read('RootDesk/MyDesk/Formations/FormationService.mlua');
  // The server ignores a group switch while a write is pending, so discarding must not run then.
  const session = read('RootDesk/MyDesk/Formations/FormationEditSession.mlua');
  assert.match(method(session, 'ConfirmDiscard'), /self:Busy\(\)\s*then return nil end/);
  assert.match(method(lobby, 'RenderConfirmation'), /ReturnWithoutSave", not view\.busy/);
  // A request that cannot be correlated is answered, not dropped.
  assert.match(method(service, 'SaveForUser'), /#requestId > 64 then self:Publish\(record\) return end/);
});

test('#50 card frame looks are authored in the template, not hard-coded by Render', () => {
  const ui = UIBuilder.read('ui/FormationGroup.ui');
  const template = 'Editor/Catalog/Template';
  const order = name => ui.find(`${template}/${name}`).jsonString.displayOrder;
  assert.ok(order('SelectedFrame') < order('CardSign'), 'selected frame sits under the ornament');
  assert.equal(ui.find(`${template}/SelectedFrame`).jsonString.enable, false, 'unselected by default');
  assert.equal(ui.getComponent(`${template}/SelectedFrame`, 'MOD.Core.SpriteGUIRendererComponent').RaycastTarget, false);
  const normal = ui.getComponent(template, 'MOD.Core.ButtonComponent').Colors.NormalColor;
  assert.ok(normal.r < 0.9, 'unselected frames are dimmed by the template');
  assert.ok(ui.find(`${template}/SelectedGlow/Check`), 'selected cards keep a check mark');
  const lobby = read('RootDesk/MyDesk/Formations/FormationLobby.mlua');
  const cards = read('RootDesk/MyDesk/Formations/FormationCatalogCards.mlua');
  assert.doesNotMatch(cards, /359082ed43c44cc1a597b00b61bafa36|dc14abffdb9f400e819f61b9ab7e6805/, 'no second copy of the frame art in code');
  assert.doesNotMatch(method(lobby, 'Render'), /ImageRUID/, 'Render never overrides template art');
  assert.doesNotMatch(method(cards, 'Render'), /ImageRUID/, 'card Render never overrides template art');
  assert.match(method(cards, 'Render'), /card\.frame:SetEnable\(selected\)/);
});

test('#50 mouse preview and local edits share one rule set and keep selection rules', () => {
  const lobby = read('RootDesk/MyDesk/Formations/FormationLobby.mlua');
  const input = read('RootDesk/MyDesk/Formations/FormationMapInput.mlua');
  const session = read('RootDesk/MyDesk/Formations/FormationEditSession.mlua');
  const place = method(session, 'CanPlaceAt');
  assert.match(place, /#self\.Draft >= 6/, 'six-unit cap');
  assert.match(place, /_FormationMapLayout:CheckPlacement\(x, y, others, "DEPLOY", nil\)/, 'deployment zone, terrain and shared 0.3 spacing come from one rule');
  assert.match(place, /moving and index == self\.SelectedUnit/, 'a moving unit is excluded from its own spacing check');
  assert.match(method(input, 'ShowGhost'), /_FormationEditSession:CanPlaceAt\(x, y\)/, 'preview uses the same rule as the edit');
  assert.match(method(input, 'ShowGhost'), /Color\(1, 0\.25, 0\.25, 0\.55\)/, 'illegal spots turn red');
  assert.match(method(input, 'ShowGhost'), /Color\(1, 1, 1, 0\.55\)/, 'legal spots keep the original colour');
  assert.match(method(input, 'UpdateGhost'), /IsPointerOverUI\(\)/, 'hidden over UI');
  // An armed preview owns the click: it must never fall through to selecting a nearby unit.
  const click = method(input, 'HandleWorldClick');
  assert.ok(click.indexOf('_FormationEditSession:Place') < click.indexOf('UnitAt'), 'placement is attempted before any selection');
  assert.match(click, /PreviewMode\(\) ~= ""\s*then\s*if _FormationEditSession:Place\([^)]*\) then lobby:Render\(\) end\s*return\s*end/);
  // Right-click cancels only the preview; removal needs no preview.
  const right = method(input, 'RightClick');
  assert.match(right, /mode == "MOVE"[\s\S]*return[\s\S]*mode == "PLACE"[\s\S]*return[\s\S]*HandleWorldRemoval/);
  assert.match(method(input, 'UpdateHover'), /IsPointerOverUI\(\)[\s\S]*UnitAt/, 'hover is world-only and uses the click hit rule');
  const hover = method(input, 'ApplyHover');
  assert.match(hover, /PreviewMode\(\) == "PLACE" then index = 0 end/, '放置模式不暗示場上單位可被選取');
  assert.ok(hover.indexOf('index = 0') < hover.indexOf('previous == index'), '已亮起的單位也會先清除 hover');
  assert.match(hover, /Scale = Vector3\(1, 1, 1\)/, 'the previous unit is restored');
  assert.match(method(input, 'HandleRightClick'), /IsPointerOverUI\(\)\s*then return end/, 'a click on UI never reaches the world');
  assert.match(method(input, 'HandleWorldRemoval'), /PreviewMode\(\) ~= ""/);
  assert.match(method(session, 'PreviewMode'), /CanEdit\(\)/, 'no preview while pending, confirming or unconfirmed');
  const model = require('../.agents/skills/msw-general/scripts/model/msw_model_builder.cjs').ModelBuilder.snapshot('RootDesk/MyDesk/Models/MapObjects/FormationPreview.model');
  assert.ok(model.components.every(c => !/Trigger|Collider|Body|TouchReceive/.test(c)), 'the preview model cannot be a target or collide');
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
      let expected = reference.component('BattleCameraAnchor', component);
      // The battle view alone lifts its camera so the top HUD clears the field and the map's bottom edge stays on screen.
      if (name === 'matchprobe' && component === 'MOD.Core.CameraComponent') expected = {...expected, CameraOffset: {x: 0.5, y: 0.9}};
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

test('the handoff reaches formation sessions only through FormationService operations', () => {
  const handoff = read('RootDesk/MyDesk/Formations/FormationHandoff.mlua');
  const service = read('RootDesk/MyDesk/Formations/FormationService.mlua');
  // No session record access: the session shape and its transfer lock belong to FormationService alone.
  assert.doesNotMatch(handoff, /GetSession|transferLocked|loadEpoch|writeEpoch|restoredSession/, 'handoff holds no session fields');
  assert.doesNotMatch(handoff, /(session|record)\.(initialized|pending|loadState|saved|sessionId|editSlot|uncertain|message)\b/, 'handoff reads no session state');
  assert.doesNotMatch(handoff, /_FormationService:(Publish|Load)\(/, 'restoring a session is FormationService work');
  for (const name of ['ActiveFormation', 'LockTransfer', 'ExportConfirmed', 'ImportConfirmed', 'ReleaseTransfer']) {
    assert.ok(handoff.includes(`_FormationService:${name}(`), `handoff uses ${name}`);
    assert.match(service, new RegExp(`method \\w+ ${name}\\(`), `FormationService defines ${name}`);
  }
});

test('catalog options use named fields and one rule decides a confirmed read', () => {
  const scripts = [];
  for (const dir of ['RootDesk/MyDesk/Formations', 'RootDesk/MyDesk/Matchmaking', 'RootDesk/MyDesk/Combat']) {
    for (const file of fs.readdirSync(dir).filter(f => f.endsWith('.mlua'))) scripts.push({file, source: read(`${dir}/${file}`)});
  }
  for (const {file, source} of scripts) {
    assert.doesNotMatch(source, /\b(option|source)\[\d|options\[\d+\]\[/, `${file}: no positional catalog access`);
    if (file !== 'FormationSchema.mlua') {
      assert.doesNotMatch(source, /(\w+) [=~]= "READY" (or|and) \1 [=~]= "NEW"|(\w+) [=~]= "NEW" (or|and) \3 [=~]= "READY"/, `${file}: uses IsLoadConfirmed`);
    }
  }
  assert.match(read('RootDesk/MyDesk/Combat/MonsterCatalog.mlua'), /monsterId = profile\.MonsterId, monsterName = profile\.MonsterName, standRuid = profile\.StandAnimationRUID/);
});

test('only FormationService assigns the transfer lock', () => {
  const offenders = [];
  for (const dir of ['RootDesk/MyDesk/Formations', 'RootDesk/MyDesk/Matchmaking', 'RootDesk/MyDesk/Combat']) {
    for (const file of fs.readdirSync(dir).filter(f => f.endsWith('.mlua'))) {
      if (/\.transferLocked\s*=[^=]/.test(read(`${dir}/${file}`)) && file !== 'FormationService.mlua') offenders.push(file);
    }
  }
  assert.deepEqual(offenders, [], 'transferLocked is written only inside FormationService');
});
