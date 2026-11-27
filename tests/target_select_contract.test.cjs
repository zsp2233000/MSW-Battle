const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');
const { UIBuilder } = require('../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');

// #124: the world map's target selection replaces the attack panel. The rules run in target_select_local.cjs (fengari); these tests pin what only the
// files can say: the authored window and row buttons, who may call what, that the retired panel is gone, and that the scripts bind paths that exist.
const source = path => fs.readFileSync(path, 'utf8').replace(/\r\n/g, '\n');
const body = (text, name) => text.match(new RegExp(`(?:method \\w+|handler) ${name}\\([^]*?(?=\\n    @|\\n    method|\\n    handler|\\nend)`))?.[0] || '';
const annotation = (text, name) => text.match(new RegExp(`((?:    @[^\\n]+\\n)+)    (?:method \\w+|handler) ${name}\\(`))?.[1] || '';
const attack = () => source('RootDesk/MyDesk/Formations/FactionWarAttack.mlua');
const mapServer = () => source('RootDesk/MyDesk/Formations/FactionWarMap.mlua');
const mapClient = () => source('RootDesk/MyDesk/Formations/FactionWarMapUI.mlua');
const townClient = () => source('RootDesk/MyDesk/Formations/FactionWarUI.mlua');
const ui = () => UIBuilder.read('ui/WorldMapGroup.ui');
const TOWNS = ['nanzih', 'zuoying', 'gushan', 'yancheng'];
const sprite = 'MOD.Core.SpriteGUIRendererComponent';
const button = 'MOD.Core.ButtonComponent';
const textComponent = 'MOD.Core.TextGUIRendererComponent';
const CARD_BUTTON = '9505617fb63c447c8ff9c15c18d88064';
const BASE_FRAME = 'ac319875b43f40ea86a069c468a1a26e';

test('every side-list row has a Cardgame pick button (hidden, touch sized, last in the row) and a veil', () => {
  const file = ui();
  for (const id of TOWNS) {
    const row = `Overlay/Window/Side/Rows/${id}`;
    assert.ok(file.hasComponent(`${row}/Pick`, button), `${id} has a pick button`);
    assert.equal(file.getComponent(`${row}/Pick`, sprite).ImageRUID.DataId, CARD_BUTTON, `${id} pick is a Cardgame button`);
    assert.equal(file.getComponent(`${row}/Pick`, button).Transition, 2, `${id} pick swaps sprites on hover and press`);
    assert.equal(file.find(`${row}/Pick`).jsonString.enable, false, `${id} pick waits for the server's list`);
    const size = file.getComponent(`${row}/Pick`, 'MOD.Core.UITransformComponent').RectSize;
    assert.ok(size.x >= 88 && size.y >= 88, `${id} pick is a full touch target`);
    assert.ok(file.find(`${row}/Dim`), `${id} has a veil`);
    assert.equal(file.find(`${row}/Dim`).jsonString.enable, false, `${id} veil waits for the selection mode`);
    assert.equal(file.getComponent(`${row}/Dim`, sprite).RaycastTarget, false, `${id} veil takes no click (the row under it is not a control)`);
    const order = name => file.find(`${row}/${name}`).jsonString.displayOrder;
    for (const earlier of ['Name', 'Here', 'Owner', 'Value', 'Bar']) assert.ok(order('Pick') > order(earlier), `${id}/Pick is drawn above ${earlier}, so it receives the click`);
    for (const part of ['Name', 'Owner', 'Value', 'Bar']) assert.ok(file.find(`${row}/${part}`), `${id}/${part} (the view) is untouched`);
  }
});

test('the confirmation window is a Cardgame dialog above the map: title, both strengths, capital note, status, 是 and 否, nothing outside closes it', () => {
  const file = ui();
  assert.ok(file.find('Confirm'), 'Confirm exists');
  assert.equal(file.find('Confirm').jsonString.enable, false, 'closed by default');
  assert.equal(file.getComponent('Confirm', sprite).RaycastTarget, true, 'the dimmer blocks the map behind it');
  assert.equal(file.hasComponent('Confirm', button), false, 'and has no handler: a click outside the window does nothing');
  const order = name => file.find(name).jsonString.displayOrder;
  assert.ok(order('Confirm') > order('Overlay') && order('Confirm') > order('OpenButton'), 'drawn above the map window');
  const inFile = file.build().ContentProto.Entities.map(entity => entity.path.replace('/ui/WorldMapGroup/', ''));
  assert.ok(inFile.indexOf('Confirm') > inFile.indexOf('Overlay/Window/Side/Hint'), 'and after it in the file: Maker takes render order from the order of the entities');
  assert.equal(file.getComponent('Confirm/Window', sprite).RaycastTarget, true, 'the window takes the click itself');
  assert.equal(file.getComponent('Confirm/Window/Frame', sprite).ImageRUID.DataId, BASE_FRAME, 'the hollow Base_4 frame');
  assert.equal(file.getComponent('Confirm/Window/Frame', sprite).FillCenter, false, 'it only draws the border');
  for (const part of ['Title', 'Origin', 'Target', 'Note', 'Status']) assert.ok(file.hasComponent(`Confirm/Window/${part}`, textComponent), `${part} is a text`);
  for (const [name, label] of [['Yes', '是'], ['No', '否']]) {
    const path = `Confirm/Window/${name}`;
    assert.ok(file.hasComponent(path, button), `${name} is a button`);
    assert.equal(file.getComponent(path, textComponent).Text, label, `${name} says ${label}`);
    assert.equal(file.getComponent(path, sprite).ImageRUID.DataId, CARD_BUTTON, `${name} is a Cardgame button`);
    const size = file.getComponent(path, 'MOD.Core.UITransformComponent').RectSize;
    assert.ok(size.x >= 88 && size.y >= 88, `${name} is a full touch target`);
  }
  const controls = file.listEntities().filter(node => node.path.startsWith('/ui/WorldMapGroup/Confirm') && file.hasComponent(node.path, button));
  assert.deepEqual(controls.map(node => node.path.split('/').pop()).sort(), ['No', 'Yes'], 'the only controls are 是 and 否');
  const texts = file.listEntities().filter(node => node.path.includes('/Confirm') && file.hasComponent(node.path, textComponent)).map(node => file.getComponent(node.path, textComponent).Text);
  assert.ok(texts.every(value => !value.includes('編隊')), 'the glossary says 隊伍, never 編隊');
});

test('the map and the view are unchanged and the retired attack panel is gone from the authored UI', () => {
  const file = ui();
  assert.equal(file.find('Overlay').jsonString.enable, false, 'the map starts closed');
  assert.equal(file.find('OpenButton').jsonString.enable, false, 'the button appears only in towns');
  for (const id of TOWNS) assert.ok(file.find(`Overlay/Window/Map/Content/Towns/${id}/Crest`), `${id} crest`);
  assert.equal(UIBuilder.read('ui/FactionWarGroup.ui').find('AttackPanel'), null, 'no AttackPanel');
});

test('the NPC press asks the server, which answers once with the whole selection', () => {
  const text = attack();
  assert.match(annotation(text, 'RequestSelect'), /@ExecSpace\("Server"\)/, 'RequestSelect is the Server RPC');
  assert.match(body(text, 'RequestSelect'), /self:SelectFor\(senderUserId\)/, 'it identifies the caller on the server');
  assert.match(annotation(text, 'ReceiveSelect'), /@ExecSpace\("Client"\)/);
  assert.match(text, /method void ReceiveSelect\(string town, string status, table header, table targets, table board\)/, 'the reply carries status, header, targets and the map board');
  assert.match(body(text, 'ReceiveSelect'), /_FactionWarMapUI:ShowSelect\(town, status, header, targets, board\)/);
  const select = body(text, 'SelectFor');
  assert.equal((select.match(/_FactionWarTownDocument:Read|self:Resolve\(/g) || []).length, 1, 'the town table is read once, through Resolve');
  assert.match(select, /self:Targets\(town, faction, towns\)/, 'the targets are the server\'s Targets');
  assert.match(select, /_FactionWarMap:Board\(towns\)/, 'the map board is built from the same read');
  assert.match(select, /\{ towns = board\.towns, links = board\.links \}/, 'with its links');
  const ready = select.slice(select.indexOf('else\n                local board'));
  assert.match(ready, /"READY"[^]*_FactionWarMap:WatchMap\(userId, player\)/, 'only READY registers the map viewer');
  assert.equal((select.match(/WatchMap/g) || []).length, 1, 'and nothing else does');
  for (const status of ['UNAVAILABLE', 'NOT_OWNED', 'NO_TARGETS']) {
    assert.match(select, new RegExp(`ReceiveSelect\\(town, "${status}", \\{\\}, \\{\\}, \\{\\}, userId\\)`), `${status} answers with the status alone`);
  }
  assert.match(select, /ReceiveSelect\(town, "ENGAGED", \{ target = _MatchFlow:TargetForUser\(userId\) \}, \{\}, \{\}, userId\)/, 'ENGAGED also names the town being attacked (#127)');
  assert.match(select, /elseif #self:Targets\(town, faction, towns\) == 0 then\s+[^\n]*\n\s+self:ReceiveSelect\(town, "NO_TARGETS"/, 'an owner with no adjacent enemy town gets NO_TARGETS, not an empty map (#127)');
  assert.ok(select.indexOf('"NO_TARGETS"') < select.indexOf('"READY"'), 'and it is decided before READY registers the viewer');
  assert.match(select, /_FactionWarLanding:Judge\(userId, \{ kind = "CHECK", town = town, board = towns \}\)/, 'a fallen departure town still sends the player to their capital');
  assert.match(body(text, 'CanTarget'), /self:Targets\(origin, faction, towns\)/, 'the attack check uses the same list');
  assert.match(body(text, 'AttackFor'), /self:CanTarget\(origin, target, faction, towns\)/, 'and repeats it on the server');
  assert.match(annotation(text, 'ReceiveAttackResult'), /@ExecSpace\("Client"\)/);
  assert.match(body(text, 'ReceiveAttackResult'), /_FactionWarMapUI:ShowAttackResult\(result\)/, 'the result goes to the map');
});

test('the attack panel, its request and the panel viewers are gone; the viewers are the map\'s and the siege panel\'s', () => {
  const retired = /RequestOptions|ReceiveOptions|OptionsFor|ShowAttackOptions|ShowAttackBoard|CloseAttack|RenderAttack|AttackStatusText|WatchPanel|RequestPanelClose|ReceivePanelBoard|panelViewers|PushStrengths|AttackPanel/;
  const walk = dir => fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => entry.isDirectory() ? walk(`${dir}/${entry.name}`) : [`${dir}/${entry.name}`]);
  for (const file of walk('RootDesk').filter(name => name.endsWith('.mlua'))) assert.doesNotMatch(source(file), retired, `${file} names nothing of the attack panel`);
  const text = mapServer();
  assert.match(text, /self\._T\.viewers = \{\}/);
  assert.match(text, /self\._T\.siegeViewers = \{\}/);
  assert.equal((text.match(/self\._T\.\w*[vV]iewers = \{\}/g) || []).length, 2, 'two kinds of viewer: the map and the siege panel');
  assert.match(annotation(text, 'WatchMap'), /@ExecSpace\("ServerOnly"\)/, 'a script can register a viewer, a client cannot');
  assert.match(body(text, 'WatchMap'), /self:Watching\(userId, player\)[^]*self\._T\.viewers\[userId\] = player/, 'only a player standing in a town, as the server knows them');
  assert.doesNotMatch(body(text, 'WatchMap'), /Refresh|Read\(/, 'it adds no read: the reply already carries the board');
  assert.match(body(text, 'BoardChanged'), /next\(self\._T\.viewers\) == nil and next\(self\._T\.siegeViewers\) == nil/, 'a room with neither kind reads nothing');
});

test('the map script binds only paths that the authored UI has, in selection mode and in the view', () => {
  const file = ui();
  const text = mapClient();
  for (const literal of new Set([...text.matchAll(/"((?:Confirm|Message|Overlay)\/[\w/]*\w)"/g)].map(match => match[1]))) {
    assert.ok(file.find(literal), `${literal} exists`);
  }
  for (const id of TOWNS) assert.ok(file.find(`Overlay/Window/Side/Rows/${id}/Pick`), `${id}/Pick exists`);
  assert.match(text, /"Overlay\/Window\/Side\/Rows\/" \.\. id \.\. "\/Pick", function\(\) self:Pick\(id\) end/, 'each pick button picks its own town');
  assert.match(text, /self:Bind\("Confirm\/Window\/Yes", function\(\) self:ConfirmAttack\(\) end\)/);
  assert.match(text, /self:Bind\("Confirm\/Window\/No", function\(\) self:Decline\(\) end\)/);
  assert.match(text, /self:Bind\("Message\/Window\/Ok", function\(\) self:DismissMessage\(\) end\)/);
  const declared = [...text.matchAll(/\n((?:    @[^\n]+\n)*)    method \w+ (\w+)\(/g)];
  for (const method of declared) assert.match(method[1], /@ExecSpace\("ClientOnly"\)/, `${method[2]} runs on the client only`);
  assert.ok(declared.length >= 40, 'every method was found');
});

test('the selection protocol: Pick needs a listed town, Yes sends one request, QUEUING closes, closing the map drops the selection', () => {
  const text = mapClient();
  assert.match(body(text, 'Pick'), /self\._T\.mode ~= "select" or not self\._T\.targets\[id\] or self\._T\.selected ~= nil then return end/, 'a pick needs selection mode, a listed town and no pick open');
  assert.match(body(text, 'ConfirmAttack'), /self\._T\.pending = true[^]*_FactionWarAttack:RequestAttack\(self\._T\.selected\)/, 'Yes marks the window pending and sends the request');
  assert.match(body(text, 'ConfirmAttack'), /self\._T\.selected == nil or self\._T\.pending then return end/, 'once');
  assert.match(body(text, 'Decline'), /self\._T\.selected == nil or self\._T\.pending then return end/, 'No is refused while waiting');
  assert.match(body(text, 'ShowAttackResult'), /result == "QUEUING" then\s+self:Close\(\)/, 'QUEUING closes the map for the siege panel');
  assert.match(body(text, 'ShowAttackResult'), /result == "INVALID"[^]*_FactionWarAttack:RequestSelect\(\)/, 'INVALID asks for the targets again');
  assert.match(body(text, 'Close'), /self:SetMode\("view", \{\}, ""\)[^]*_FactionWarMap:RequestClose\(\)/, 'closing the map cancels the selection and the subscription');
  assert.match(body(text, 'ShowSelect'), /status ~= "READY" then[^]*self:Close\(\)[^]*return/, 'any other status opens nothing');
  assert.doesNotMatch(body(text, 'ShowSelect'), /_FactionWarMap:RequestOpen\(\)/, 'the answer carries the board: no second request');
  assert.match(body(text, 'Open'), /self:Reveal\("view"\)[^]*_FactionWarMap:RequestOpen\(\)/, 'the view still asks the server');
  assert.match(body(text, 'ShowBoard'), /self\._T\.mode == "select"[^]*_FactionWarAttack:RequestSelect\(\)/, 'a changed owner in selection mode asks for the targets again');
  assert.match(body(text, 'HandleKey'), /self\._T\.selected ~= nil or self\._T\.message ~= nil then return end/, 'M does nothing behind the confirmation or message window');
  assert.match(body(text, 'HandleWheel'), /self\._T\.selected ~= nil or self\._T\.message ~= nil/, 'nor does the wheel');
  const title = body(text, 'RenderConfirm');
  for (const words of ['"進攻 "', '"出發城 "', '"目標城 "', '"打贏不扣主城兵力"', '"正在加入配對…"']) assert.ok(title.includes(words), `the window says ${words}`);
  assert.match(title, /_FactionWarTownDocument:IsCapital\(target\)/, 'the capital note follows the document');
  assert.doesNotMatch(text, /編隊/, 'the glossary says 隊伍');
});

test('both town NPCs ignore the interaction key while the map covers the town, and the shared NPC asks for the selection', () => {
  const npc = source('RootDesk/MyDesk/Formations/FactionWarNpc.mlua');
  assert.match(npc, /_FactionWarAttack:RequestSelect\(\)/, 'the war NPC asks for the target selection');
  assert.match(npc, /_FactionWarMapUI:BeginSelect\(\)\s+_FactionWarAttack:RequestSelect\(\)/, 'after marking the press as awaiting its answer (#127)');
  assert.match(npc, /event\.InteractionEntity == _UserService\.LocalPlayer and not _FactionWarMapUI:BlocksInteraction\(\)/);
  assert.match(source('RootDesk/MyDesk/Formations/FactionWarLobbyNpc.mlua'), /event\.InteractionEntity == _UserService\.LocalPlayer and not _FactionWarMapUI:BlocksInteraction\(\)/);
  assert.match(body(mapClient(), 'BlocksInteraction'), /return self\._T\.open == true or self\._T\.message ~= nil or self\._T\.asking == true/, 'the map, a message window and an unanswered press all block the NPCs (#127)');
  assert.doesNotMatch(townClient(), /AttackPanel|ShowAttack|RequestOptions/, 'the town HUD script has no attack panel any more');
});

test('the message window (#127) is a Cardgame dialog above the map and the confirmation window, with one 確定 button, shown without a map', () => {
  const file = ui();
  assert.ok(file.find('Message'), 'Message exists');
  assert.equal(file.find('Message').jsonString.enable, false, 'closed by default');
  assert.equal(file.getComponent('Message', sprite).RaycastTarget, true, 'the dimmer blocks everything behind it');
  assert.equal(file.hasComponent('Message', button), false, 'and has no handler: a click outside the window does nothing');
  const inFile = file.build().ContentProto.Entities.map(entity => entity.path.replace('/ui/WorldMapGroup/', ''));
  assert.ok(inFile.indexOf('Message') > inFile.indexOf('Confirm/Window/No') && inFile.indexOf('Message') > inFile.indexOf('Overlay/Window/Side/Hint'), 'drawn after, so above, the confirmation window and the map');
  assert.ok(file.find('Message').jsonString.displayOrder > file.find('Confirm').jsonString.displayOrder, 'with the display order to match');
  assert.equal(file.getComponent('Message/Window', sprite).RaycastTarget, true, 'the window takes the click itself');
  assert.equal(file.getComponent('Message/Window/Frame', sprite).ImageRUID.DataId, BASE_FRAME, 'the hollow Base_4 frame');
  assert.equal(file.getComponent('Message/Window/Frame', sprite).FillCenter, false);
  assert.ok(file.hasComponent('Message/Window/Text', textComponent), 'one text');
  const controls = file.listEntities().filter(node => node.path.startsWith('/ui/WorldMapGroup/Message') && file.hasComponent(node.path, button));
  assert.deepEqual(controls.map(node => node.path.split('/').pop()), ['Ok'], 'the only control is 確定');
  assert.equal(file.getComponent('Message/Window/Ok', textComponent).Text, '確定');
  assert.equal(file.getComponent('Message/Window/Ok', sprite).ImageRUID.DataId, CARD_BUTTON, 'a Cardgame button');
  const size = file.getComponent('Message/Window/Ok', 'MOD.Core.UITransformComponent').RectSize;
  assert.ok(size.x >= 88 && size.y >= 88, 'a full touch target');
  assert.equal(file.getComponent('Message/Window/Ok', sprite).Color.a, 1, 'untinted, like the other Cardgame buttons');
  assert.match(source('assets/worldmap/build_message_ui.cjs'), /messagePaths\(\)[^]*addMessageUi\(b\)/, 'a delta build script replaces only the message window');
  assert.match(source('assets/worldmap/select_ui.cjs'), /addMessageUi\(b\);\n\}/, 'and a full rebuild of the selection parts includes it, last');
});

test('only a status other than READY shows a message, with the words of the ticket, town names in the one highlight colour, no map', () => {
  const text = mapClient();
  const words = body(text, 'MessageFor');
  for (const sentence of [
    '，要改變目標請先取消配對（畫面上方的攻城面板可以取消）',
    '這座城已不屬於你的陣營',
    '暫時無法讀取國戰資料，請再試一次',
    '目前沒有可進攻的相鄰敵城',
  ]) assert.ok(words.includes(sentence), `the message says ${sentence}`);
  assert.ok(words.includes('"目前正在進攻 " .. _FactionWarUI:HighlightedTownName(target)'), 'the town being attacked is named with the shared highlight');
  assert.doesNotMatch(words, /<color|#[0-9A-Fa-f]{6}/, 'the colour is not repeated here');
  const select = body(text, 'ShowSelect');
  const rest = select.slice(select.indexOf('if status ~= "READY" then'), select.indexOf('local player = _UserService.LocalPlayer'));
  assert.match(rest, /self:ShowMessage\(town, self:MessageFor\(status, header\)\)/, 'every other status goes to the message window');
  assert.doesNotMatch(rest, /Reveal|RequestOpen|SetMode\("select"/, 'and never to the map');
  assert.match(select, /self\._T\.asking = false/, 'the answer ends the wait for it, shown or not');
  assert.match(body(text, 'ShowMessage'), /self:Ui\("Message"\)[^]*window:SetEnable\(true\)/);
  assert.match(body(text, 'DismissMessage'), /window:SetEnable\(false\)/);
  assert.match(body(text, 'OnUpdate'), /self:ExpireStale\(\)/, 'the wait times out and a message follows its town');
  assert.match(body(text, 'ExpireStale'), /self\.AskTimeout \* 1000[^]*self\._T\.asking = false[^]*self:DismissMessage\(\)/);
  assert.match(text, /property number AskTimeout = \d+/, 'the timeout is a property');
  assert.match(body(text, 'Open'), /self\._T\.message ~= nil/, 'the map button opens nothing behind a message');
  for (const method of ['MessageFor', 'ShowMessage', 'DismissMessage', 'ExpireStale']) assert.match(annotation(text, method), /@ExecSpace\("ClientOnly"\)/, `${method} runs on the client only`);
  assert.match(annotation(source('RootDesk/MyDesk/Matchmaking/MatchFlow.mlua'), 'TargetForUser'), /@ExecSpace\("ServerOnly"\)/, 'the target of a ticket is read on the server');
});

test('the #127 Maker client probe implements every step its header orders, presses the real key, and the README, ADR and glossary name the message window', () => {
  const probe = source('tests/target_select_message_client_runtime_probe.lua');
  const readme = source('tests/README.md');
  const order = probe.match(/^-- Order [^\n]*\n((?:--[^\n]*\n)+?)-- Final/m)[1];
  const header = [...order.matchAll(/(?<![#\d])\b(\d{1,2}) ([A-Z_]{4,})/g)].map(match => [Number(match[1]), match[2]]);
  assert.deepEqual(header.map(step => step[0]), Array.from({ length: 14 }, (_, index) => index + 1), 'the header numbers 14 steps from 1 without gaps');
  const implemented = [...probe.matchAll(/(?:if|elseif) STEP == "([A-Z_]+)" then/g)].map(match => match[1]);
  for (const name of new Set(header.map(step => step[1]))) {
    assert.ok(implemented.includes(name), `${name} is implemented`);
    assert.ok(probe.includes(`[VRF][TargetMessage] ${name} PASS`), `${name} ends in a PASS line`);
    assert.ok(readme.includes(`\`${name}\``), `the README names ${name}`);
  }
  assert.match(probe, /maker_keyboard_input/, 'the interaction key is a real key tap');
  assert.match(probe, /ActionKey == KeyboardKey\.E/, 'on the key the NPC answers');
  assert.match(probe, /GetChildComponentsByTypeName\(typeName, true\)/, 'beside the real NPC entities of the town');
  assert.match(probe, /if not ok then log_error\("\[VRF\]\[TargetMessage\] " \.\. STEP \.\. " FAIL "/, 'a failed step reports itself');
  assert.doesNotMatch(probe, /_FactionWarAttack\.\w+ = |_FactionWarMapUI\.\w+ = /, 'it never replaces a production method');
  const adr = source('docs/adr/0015-world-map-is-viewed-in-towns-and-pushed-by-settlement-events.md');
  for (const word of ['補記（#127）', 'NO_TARGETS', 'BeginSelect', 'AskTimeout', 'BlocksInteraction']) assert.ok(adr.includes(word), `ADR 0015 records ${word}`);
  assert.ok(source('CONTEXT.md').includes('**訊息視窗**'), 'CONTEXT.md defines the message window');
});

test('the builder scripts, ADR 0015 and the glossary agree with the code', () => {
  assert.match(source('assets/worldmap/build_ui.cjs'), /addSelectUi\(b\)/, 'a full rebuild of the map includes the selection parts');
  assert.match(source('assets/worldmap/build_select_ui.cjs'), /UIBuilder\.load\(uiFile\)[^]*addSelectUi\(b\)/, 'the delta script adds them to the existing file');
  assert.ok(fs.existsSync('assets/siege/remove_attack_panel_ui.cjs'), 'and the attack panel has a removal script');
  assert.doesNotMatch(source('assets/siege/build_siege_ui.cjs'), /AttackPanel\/Window/, 'the team preview build no longer draws the attack panel');
  const adr = source('docs/adr/0015-world-map-is-viewed-in-towns-and-pushed-by-settlement-events.md');
  for (const word of ['補記（#124）', 'RequestSelect', 'WatchMap', '選目標模式']) assert.ok(adr.includes(word), `ADR 0015 records ${word}`);
  const context = source('CONTEXT.md');
  for (const word of ['選目標模式', '確認視窗', '國戰大地圖']) assert.ok(context.includes(word), `CONTEXT.md names ${word}`);
});

test('the Maker client probe implements every step its header orders, ends each in a PASS line, and the README names them', () => {
  const probe = source('tests/target_select_client_runtime_probe.lua');
  const readme = source('tests/README.md');
  const order = probe.match(/^-- Order [^\n]*\n((?:--   [^\n]*\n)+)/m)[1];
  const header = [...order.matchAll(/(\d+) ([A-Z_]+)/g)].map(match => [Number(match[1]), match[2]]);
  assert.deepEqual(header.map(step => step[0]), Array.from({ length: 13 }, (_, index) => index + 1), 'the header numbers 13 steps from 1 without gaps');
  const implemented = [...probe.matchAll(/(?:if|elseif) STEP == "([A-Z_]+)" then/g)].map(match => match[1]);
  for (const [, name] of header) {
    assert.ok(implemented.includes(name), `${name} is implemented`);
    assert.ok(probe.includes(`[VRF][TargetSelect] ${name} PASS`), `${name} ends in a PASS line`);
    assert.ok(readme.includes(`\`${name}\``), `the README names ${name}`);
  }
  for (const extra of ['PENDING', 'PENDING_CLOSE']) assert.ok(implemented.includes(extra) && readme.includes(`\`${extra}\``), `${extra} is implemented and documented`);
  assert.match(probe, /if not ok then log_error\("\[VRF\]\[TargetSelect\] " \.\. STEP \.\. " FAIL "/, 'a failed step reports itself');
  assert.match(probe, /_FactionWarAttack:RequestSelect\(\)/, 'the probe makes the NPC\'s real request');
  assert.match(probe, /SendEvent\(ButtonClickEvent\(entity\)\)/, 'and presses the real buttons');
  assert.doesNotMatch(probe, /_FactionWarAttack\.RequestAttack = /, 'it never replaces a production method');
});
