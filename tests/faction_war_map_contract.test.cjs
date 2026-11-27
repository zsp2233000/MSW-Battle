const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');
const { UIBuilder } = require('../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');

// Structural contract for the faction-war world map. The behaviour (open, pushed boards, close, leaving a town) is proven by
// tests/faction_war_map_runtime_probe.lua (server_main) and tests/faction_war_map_client_runtime_probe.lua (client) in Maker.
const source = path => fs.readFileSync(path, 'utf8').replace(/\r\n/g, '\n');
const body = (text, name) => text.match(new RegExp(`(?:method \\w+|handler) ${name}\\([^]*?(?=\\n    @|\\n    method|\\n    handler|\\nend)`))?.[0] || '';
const annotation = (text, name) => text.match(new RegExp(`((?:    @[^\\n]+\\n)+)    (?:method \\w+|handler) ${name}\\(`))?.[1] || '';
const server = () => source('RootDesk/MyDesk/Formations/FactionWarMap.mlua');
const client = () => source('RootDesk/MyDesk/Formations/FactionWarMapUI.mlua');
const TOWNS = ['nanzih', 'zuoying', 'gushan', 'yancheng'];
const VIEW = 'Overlay/Window/Map';
const MAP = `${VIEW}/Content`;

test('the world map group draws above the town HUD, opens from a hidden town button and starts closed', () => {
  const ui = UIBuilder.read('ui/WorldMapGroup.ui');
  const group = ui.getComponent('/ui/WorldMapGroup', 'MOD.Core.UIGroupComponent');
  assert.equal(group.DefaultShow, true, 'the group itself stays shown so the client logic can toggle its children');
  assert.ok(group.GroupOrder > UIBuilder.read('ui/FactionWarGroup.ui').getComponent('/ui/FactionWarGroup', 'MOD.Core.UIGroupComponent').GroupOrder, 'above the town HUD');
  for (const button of ['OpenButton', 'Overlay/Window/Close']) {
    assert.ok(ui.hasComponent(button, 'MOD.Core.ButtonComponent'), button);
    const size = ui.getComponent(button, 'MOD.Core.UITransformComponent').RectSize;
    assert.ok(size.x >= 88 && size.y >= 88, `${button} is a full touch target`);
  }
  assert.equal(ui.find('OpenButton').jsonString.enable, false, 'the button appears only in towns');
  assert.equal(ui.find('Overlay').jsonString.enable, false, 'the map starts closed');
});

test('the map uses the painted terrain, one tinted mask per district, three link bars and a node per town', () => {
  const ui = UIBuilder.read('ui/WorldMapGroup.ui');
  const art = JSON.parse(source('assets/worldmap/ruids.json'));
  const layout = JSON.parse(source('assets/worldmap/layout.json'));
  for (const ruid of Object.values(art)) assert.match(ruid, /^[0-9a-f]{32}$/);
  const ruidOf = path => ui.getComponent(path, 'MOD.Core.SpriteGUIRendererComponent').ImageRUID.DataId;
  assert.equal(ruidOf(`${MAP}/Terrain`), art.terrain);
  assert.deepEqual(ui.getComponent(MAP, 'MOD.Core.UITransformComponent').RectSize, { x: layout.size.w, y: layout.size.h }, 'the map is the size the art was painted at');
  for (const id of TOWNS) {
    const tint = `${MAP}/Districts/${id}`;
    assert.equal(ruidOf(tint), art[`mask_${id}`], `${id} mask`);
    const { x, y, w, h } = layout.towns[id].mask;
    const transform = ui.getComponent(tint, 'MOD.Core.UITransformComponent');
    assert.deepEqual(transform.anchoredPosition, { x, y }, `${id} cropped mask location`);
    assert.deepEqual(transform.RectSize, { x: w, y: h }, `${id} cropped mask size`);
    assert.equal(ruidOf(`${MAP}/Towns/${id}/Crest`), art.crest, `${id} crest`);
    for (const part of ['Name', 'Strength', 'Capital', 'Arrow']) assert.ok(ui.find(`${MAP}/Towns/${id}/${part}`), `${id} ${part}`);
    assert.equal(ui.find(`${MAP}/Towns/${id}/Here`), null, `${id} the arrow replaced the map chip`);
    assert.equal(ui.getComponent(`${MAP}/Towns/${id}/Arrow`, 'MOD.Core.SpriteGUIRendererComponent').AnimClipPlayType, 1, `${id} arrow loops`);
    assert.equal(ruidOf(`${MAP}/Towns/${id}/Arrow`), '96392b1df6724d43abab0ec1988aa7c4', `${id} here arrow`);
    assert.equal(ui.find(`${MAP}/Towns/${id}/Arrow`).jsonString.enable, false, `${id} arrow waits for the client`);
    for (const part of ['Name', 'Owner', 'Value', 'Here', 'Bar/Fill']) assert.ok(ui.find(`Overlay/Window/Side/Rows/${id}/${part}`), `${id} row ${part}`);
    const node = ui.getComponent(`${MAP}/Towns/${id}`, 'MOD.Core.UITransformComponent').anchoredPosition;
    assert.ok(Math.abs(node.x) < layout.size.w / 2 && Math.abs(node.y) < layout.size.h / 2, `${id} node on the map`);
  }
  for (let n = 1; n <= 3; n++) assert.equal(ui.find(`${MAP}/Links/Link${n}`).jsonString.enable, false, `link ${n} waits for the server`);
  assert.match(client(), /property integer LinkSlots = 3\b/, 'the client fills exactly the authored bars');
  // Real geography, north to south: Nanzih above Zuoying above Gushan above Yancheng.
  const y = id => layout.towns[id].y;
  assert.ok(y('nanzih') > y('zuoying') && y('zuoying') > y('gushan') && y('gushan') > y('yancheng'));
});

test('the clipped map has 38 district names and a stationary input layer', () => {
  const ui = UIBuilder.read('ui/WorldMapGroup.ui');
  const layout = JSON.parse(source('assets/worldmap/layout.json'));
  const districts = JSON.parse(source('assets/worldmap/kaohsiung_boundaries.json')).districts;
  const xform = path => ui.getComponent(path, 'MOD.Core.UITransformComponent');
  assert.ok(ui.hasComponent(VIEW, 'MOD.Core.MaskComponent'));
  assert.deepEqual(xform(VIEW).Pivot, { x: 0.5, y: 0.5 });
  assert.deepEqual(xform(VIEW).RectSize, xform(MAP).RectSize);
  assert.ok(ui.getComponent(`${VIEW}/Input`, 'MOD.Core.SpriteGUIRendererComponent').RaycastTarget);
  assert.ok(ui.hasComponent(`${VIEW}/Input`, 'MOD.Core.UITouchReceiveComponent'));
  assert.ok(ui.find('Overlay/Window/Side'), 'the war board is outside the pan/zoom layer');
  const names = ui.listEntities().filter(e => e.path.startsWith(`/ui/WorldMapGroup/${MAP}/Places/`));
  const mapped = layout.places.map(place => {
    const path = `${MAP}/Places/${place.code}`;
    assert.deepEqual(xform(path).anchoredPosition, { x: place.x, y: place.y });
    return ui.getComponent(path, 'MOD.Core.TextGUIRendererComponent').Text;
  });
  assert.equal(names.length, 34);
  const activeNames = TOWNS.map(id => ui.getComponent(`${MAP}/Towns/${id}/Name`, 'MOD.Core.TextGUIRendererComponent').Text + '區');
  assert.equal(districts.length, 38);
  assert.deepEqual(new Set([...mapped, ...activeNames]), new Set(districts.map(d => d.name)));
});

test('the server answers an opened map at once and pushes later boards only to viewers, without polling storage', () => {
  const text = server();
  assert.match(annotation(text, 'RequestOpen'), /@ExecSpace\("Server"\)/);
  assert.match(annotation(text, 'RequestClose'), /@ExecSpace\("Server"\)/);
  for (const name of ['ReceiveBoard', 'ReceiveFaction', 'ReceiveUnavailable']) assert.match(annotation(text, name), /@ExecSpace\("Client"\)/, name);
  assert.match(body(text, 'RequestOpen'), /_FactionWar:IsTown\(player\.CurrentMapName\)/, 'only players in a town subscribe');
  assert.match(body(text, 'RequestOpen'), /self:Refresh\(userId\)/, 'the opener always gets an answer');
  assert.match(body(text, 'Refresh'), /self\._T\.again = true/, 'requests during a read are folded into one more read');
  assert.match(body(text, 'Deliver'), /changed or answering\[userId\]/, 'others hear only of a changed board');
  assert.match(body(text, 'BoardChanged'), /next\(self\._T\.viewers\) == nil/, 'a room with no viewer reads nothing');
  assert.doesNotMatch(text, /SetTimerRepeat|SetTimer\(/, 'no storage polling (ADR 0012)');
  assert.match(body(text, 'Links'), /FindGate/, 'links are the authored gates');
  assert.match(text, /@EventSender\("Service", "RoomService"\)\n    handler HandleRoomBoardChanged\(TownBoardChangedEvent/);
  assert.match(text, /@EventSender\("Service", "WorldInstanceService"\)\n    handler HandleInstanceBoardChanged\(TownBoardChangedEvent/);
  assert.match(body(text, 'HandleInstanceBoardChanged'), /event\.Source == _WorldInstanceService\.WorldInstanceId/, 'the own instance\'s echo is ignored (it arrived as a room event)');
  assert.match(body(text, 'AnnounceChange'), /RequestSendEventToAllWorldInstancesAsync/);
  assert.match(body(text, 'HandleUserLeaveEvent'), /self\._T\.viewers\[event\.UserId\] = nil/);
});

test('every stored settlement announces the change; the client closes outside towns and follows the pushed board', () => {
  const finish = body(source('RootDesk/MyDesk/Formations/FactionWarAttack.mlua'), 'Finish');
  assert.match(finish, /status == "SAVED" or status == "DUPLICATE" then _FactionWarMap:AnnounceChange\(\)/);
  const text = client();
  assert.match(body(text, 'CanOpen'), /_FactionWar:IsTown\(player\.CurrentMapName\) and not _FormationLobby:IsTownPanelOpen\(\)/);
  assert.match(body(text, 'OnUpdate'), /if self\._T\.open and not available then self:Close\(\) end/);
  assert.match(body(text, 'HandleKey'), /KeyboardKey\.M/);
  assert.match(body(text, 'Close'), /_FactionWarMap:RequestClose\(\)/);
  assert.match(body(text, 'ApplyBoard'), /_FactionWarUI:ShowTownStatus/, 'the town HUD follows the pushed board');
  assert.match(body(text, 'ShowBoard'), /self:ApplyBoard\(towns, links\)/, 'a pushed board is applied');
  assert.match(body(text, 'ShowLinks'), /ZRotation = math\.deg\(math\.atan\(dy, dx\)\)/);
  const declared = [...text.matchAll(/\n((?:    @[^\n]+\n)*)    method \w+ (\w+)\(/g)];
  assert.ok(declared.length >= 15, 'every method was found');
  for (const method of declared) {
    assert.match(method[1], /@ExecSpace\("ClientOnly"\)/, `${method[2]} runs on the client only`);
  }
});
