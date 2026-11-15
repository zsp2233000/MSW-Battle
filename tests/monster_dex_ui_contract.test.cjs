const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const { UIBuilder } = require('../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');

const root = path.join(__dirname, '..');
const read = p => fs.readFileSync(path.join(root, p), 'utf8');
const DEX_UI = 'ui/MonsterDexGroup.ui';
const LOBBY_UI = 'ui/FormationGroup.ui';
const MODULE = 'RootDesk/MyDesk/Dex/MonsterDex.mlua';
const SERVICE = 'RootDesk/MyDesk/Dex/MonsterDexService.mlua';
const BOOK_RUID = '0a782ef3897543b593bda6bd1763f978';
const BOOK_PIXELS = { width: 1024, height: 664 };
const CANVAS = { width: 1920, height: 1080 };
const PAGE = 'Book/Page';
const LEFT = `${PAGE}/LeftPage`;
const LIST = `${LEFT}/List`;
const ROW = `${LIST}/RowTemplate`;

const UI_TRANSFORM = 'MOD.Core.UITransformComponent';
const SPRITE = 'MOD.Core.SpriteGUIRendererComponent';
const BUTTON = 'MOD.Core.ButtonComponent';
const TEXT = 'MOD.Core.TextGUIRendererComponent';
const SCROLL = 'MOD.Core.ScrollLayoutGroupComponent';

const dex = () => UIBuilder.read(DEX_UI);
const lobby = () => UIBuilder.read(LOBBY_UI);
const rect = (ui, entity) => ui.getComponent(entity, UI_TRANSFORM);

// Statements of a method body with comments and blank lines removed.
function methodBody(source, name) {
  const match = source.match(new RegExp(`method [\\w<>, ]+ ${name}\\([^)]*\\)([\\s\\S]*?)\\n    end\\b`));
  assert.ok(match, `${name} must exist`);
  return match[1];
}
const statements = body => body.split(/\r?\n/).map(line => line.trim()).filter(line => line && !line.startsWith('--'));

test('the dex is its own overlay group above the lobby and match screens, hidden until opened', () => {
  const ui = dex();
  const group = ui.getComponent('MonsterDexGroup', 'MOD.Core.UIGroupComponent');
  assert.equal(group.DefaultShow, true, 'the controller script needs a shown group; the book itself starts disabled');
  const orderOf = (file, name) => UIBuilder.read(file).getComponent(name, 'MOD.Core.UIGroupComponent').GroupOrder;
  assert.ok(group.GroupOrder > orderOf('ui/MatchGroup.ui', 'MatchGroup'), 'above the match panel');
  assert.ok(group.GroupOrder > orderOf(LOBBY_UI, 'FormationGroup'), 'above the lobby');
  assert.equal(ui.find('Book').jsonString.enable, false, 'the book is closed when Play starts');
});

test('a full-screen dimmer swallows input so the lobby underneath stays untouched', () => {
  const ui = dex();
  const dimmer = ui.find('Book/Dimmer');
  assert.ok(dimmer, 'dimmer exists');
  assert.equal(ui.getComponent('Book/Dimmer', SPRITE).RaycastTarget, true);
  // A centred 1920x1080 rect, like the lobby's own full-screen layers: a stretch anchor kept its stale 100x100 size in Play.
  for (const entity of ["Book", "Book/Dimmer"]) {
    const transform = rect(ui, entity);
    assert.deepEqual([transform.AlignmentOption, transform.RectSize.x, transform.RectSize.y, transform.anchoredPosition.x, transform.anchoredPosition.y], [0, CANVAS.width, CANVAS.height, 0, 0], `${entity} covers the whole canvas`);
  }
  assert.equal(ui.getComponent('MonsterDexGroup', 'MOD.Core.CanvasGroupComponent').BlocksRaycasts, true);
});

test('the book background uses the specified RUID, keeps its aspect ratio and is centred', () => {
  const ui = dex();
  const sprite = ui.getComponent(PAGE, SPRITE);
  assert.equal(sprite.ImageRUID.DataId, BOOK_RUID);
  const transform = rect(ui, PAGE);
  assert.ok(Math.abs(transform.RectSize.x / transform.RectSize.y - BOOK_PIXELS.width / BOOK_PIXELS.height) < 0.002, 'aspect ratio of the 1024x664 picture');
  assert.ok(transform.RectSize.x <= CANVAS.width && transform.RectSize.y <= CANVAS.height, 'fits the canvas');
  assert.equal(transform.AlignmentOption, 0, 'middle-center anchor');
  assert.deepEqual([transform.anchoredPosition.x, transform.anchoredPosition.y], [0, 0]);
  assert.equal(sprite.Type, 0, 'plain image, not sliced or tiled');
});

test('the left page holds a scrollable vertical list with a hidden row template, the right page only the details', () => {
  const ui = dex();
  assert.ok(ui.find(LEFT) && ui.find(`${PAGE}/RightPage`), 'both pages exist');
  const layout = ui.getComponent(LIST, SCROLL);
  assert.equal(layout.Type, 1, 'vertical list');
  assert.ok([3].includes(layout.VerticalScrollBarDirection), 'a vertical scroll-bar direction value');
  assert.equal(ui.find(ROW).jsonString.enable, false, 'template is hidden');
  assert.ok(ui.getComponent(ROW, BUTTON), 'a row is a button');
  assert.equal(ui.listEntities().filter(e => e.path.startsWith(`/ui/MonsterDexGroup/${PAGE}/RightPage/`)
    && !/^\/ui\/MonsterDexGroup\/Book\/Page\/RightPage\/(DetailTitle|Details)(\/|$)/.test(e.path)).length, 0,
    'the right page holds only the resource details (monster_dex_details_contract.test.cjs); the stage is a later ticket');
  const list = rect(ui, LIST);
  const left = rect(ui, LEFT);
  assert.ok(list.RectSize.x <= left.RectSize.x && list.RectSize.y < left.RectSize.y, 'list sits inside the left page and leaves room for the trial buttons');
});

test('the book has a visible close button', () => {
  const ui = dex();
  assert.ok(ui.getComponent('Book/Close', BUTTON));
  assert.ok(ui.getComponent('Book/Close', TEXT).Text.length > 0);
});

test('the lobby has a monster dex button next to the other lobby actions', () => {
  const ui = lobby();
  assert.ok(ui.getComponent('Lobby/MonsterDex', BUTTON), 'button exists under the lobby panel');
  assert.equal(ui.getComponent('Lobby/MonsterDex', TEXT).Text, '怪物圖鑑');
  assert.equal(ui.listEntities().filter(e => e.path.includes('MonsterDex')).length, 1, 'the dex entry exists only in the lobby');
});

test('every bound property of MonsterDex holds the id of the entity it names', () => {
  const source = read(MODULE);
  const binds = [
    [DEX_UI, 'book', 'Book'],
    [DEX_UI, 'closeButton', 'Book/Close'],
    [DEX_UI, 'listLayout', LIST],
    [DEX_UI, 'rowTemplate', ROW],
    [DEX_UI, 'statusText', `${LEFT}/Status`],
    [LOBBY_UI, 'lobbyButton', 'Lobby/MonsterDex'],
  ];
  for (const [file, property, entity] of binds) {
    const declared = source.match(new RegExp(`property \\w+ ${property} = "([^"]*)"`));
    assert.ok(declared, `${property} is declared`);
    assert.equal(declared[1], UIBuilder.read(file).getId(entity), `${property} -> ${entity}`);
  }
});

test('MonsterDex exposes open, close, select and a readable snapshot, all client only', () => {
  const source = read(MODULE);
  assert.match(source, /^@Logic\s*\nscript MonsterDex extends Logic/m);
  for (const [name, signature] of [['Open', 'boolean Open\\(\\)'], ['Close', 'void Close\\(\\)'],
    ['Select', 'boolean Select\\(string monsterId\\)'], ['GetSnapshot', 'table GetSnapshot\\(\\)'], ['Observe', 'void Observe\\(table rows\\)']]) {
    assert.match(source, new RegExp(`@ExecSpace\\("ClientOnly"\\)\\s*\\n\\s*method ${signature}`), `${name} is a ClientOnly method`);
  }
  const body = methodBody(source, 'GetSnapshot');
  for (const field of ['selectedMonsterId', 'selectedMonsterName', 'action', 'events', 'open', 'loadState', 'rows']) {
    assert.match(body, new RegExp(`\\b${field}\\b`), `snapshot carries ${field}`);
  }
});

test('opening is refused first thing outside Maker Play and only from the lobby when no match is running', () => {
  const source = read(MODULE);
  assert.equal(statements(methodBody(source, 'Open'))[0], 'if not Environment:IsMakerPlay() then return false end',
    'the published-environment refusal is the first statement');
  const gate = statements(methodBody(source, 'CanOpen')).join('\n');
  assert.match(gate, /Environment:IsMakerPlay\(\)/);
  assert.match(gate, /CurrentMapName ~= self.LobbyMapName/);
  assert.match(read(MODULE), /property string LobbyMapName = "formationlobby"/);
  assert.match(gate, /_MatchFlowInput:AllowsFormationActions\(\)/, 'reuses the lobby\'s existing matchmaking lock');
});

test('the lobby button is only shown in Maker Play and follows the same gate', () => {
  const update = statements(methodBody(read(MODULE), 'OnUpdate')).join('\n');
  assert.match(update, /local shown = Environment:IsMakerPlay\(\)/, 'the published world never shows the entry');
  assert.match(update, /lobbyButton\.Entity:SetEnable\(shown\)/);
  assert.match(update, /lobbyButton\.Enable = canOpen/, 'matchmaking disables it');
  assert.match(update, /local canOpen = self:CanOpen\(\)/);
  assert.match(update, /self:Close\(\)/, 'a match starting while the book is open closes it');
});

test('opening and closing touch no storage, formation, edit-session or matchmaking state', () => {
  const source = read(MODULE);
  assert.doesNotMatch(source, /DataStorage|_FormationService|_FormationStorage|_MonsterLevelStorage|_MatchFlow\b|_FormationLobby|_FormationEditorSlide/);
  assert.doesNotMatch(source, /_FormationEditSession:(Request|Select|Confirm|Continue|Reset|Observe|Run|Ensure)/);
  assert.doesNotMatch(source, /_MatchFlowInput:(Click|Observe|Render|SelectScreen)/);
  assert.doesNotMatch(source, /@Sync|@TargetUserSync/);
});

test('the service forwards each reply to the dex and still keeps only the latest in memory', () => {
  const receive = methodBody(read(SERVICE), 'Receive');
  assert.match(receive, /self\._T\.latest = rows/);
  assert.match(receive, /_MonsterDex:Observe\(rows\)/);
});
