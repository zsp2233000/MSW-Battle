const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const { UIBuilder } = require('../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');
const { MapBuilder } = require('../.agents/skills/msw-general/scripts/map/msw_map_builder.cjs');

const root = path.join(__dirname, '..');
const read = p => fs.readFileSync(path.join(root, p), 'utf8');
const DEX_UI = 'ui/MonsterDexGroup.ui';
const MODULE = 'RootDesk/MyDesk/Dex/MonsterDex.mlua';
const SERVICE = 'RootDesk/MyDesk/Dex/MonsterDexService.mlua';
const LEFT = 'Book/Page/LeftPage';
const RIGHT = 'Book/Page/RightPage';
const STAGE = `${RIGHT}/Stage`;
const ACTOR = `${STAGE}/Actor`;
const TRIAL = `${LEFT}/Trial`;
const NOTICE = `${STAGE}/Notice`;
const CAMERA_MODULE = 'RootDesk/MyDesk/Combat/BattleFixedCamera.mlua';
// Left to right, as the ticket lists them.
const TRIAL_BUTTONS = [['Idle', '待機', 'idleButton'], ['Move', '移動', 'moveButton'], ['Attack', '攻擊', 'attackButton'],
  ['Hurt', '受傷', 'hurtButton'], ['Die', '死亡', 'dieButton']];

const SPRITE = 'MOD.Core.SpriteGUIRendererComponent';
const BUTTON = 'MOD.Core.ButtonComponent';
const TEXT = 'MOD.Core.TextGUIRendererComponent';
const UI_TRANSFORM = 'MOD.Core.UITransformComponent';

const dex = () => UIBuilder.read(DEX_UI);
const rect = (ui, entity) => ui.getComponent(entity, UI_TRANSFORM);
const childNames = (ui, parentPath) => ui.listEntities()
  .filter(e => e.path.startsWith(`/ui/MonsterDexGroup/${parentPath}/`) && e.path.slice(`/ui/MonsterDexGroup/${parentPath}/`.length).indexOf('/') < 0)
  .map(e => ({ name: e.path.split('/').pop(), order: ui.find(e.path).jsonString.displayOrder }))
  .sort((a, b) => a.order - b.order)
  .map(e => e.name);
function methodBody(source, name) {
  const match = source.match(new RegExp(`method [\\w<>, ]+ ${name}\\([^)]*\\)([\\s\\S]*?)\\n    end\\b`));
  assert.ok(match, `${name} must exist`);
  return match[1];
}

test('the stage fills the upper right page, above the resource details', () => {
  const ui = dex();
  const page = rect(ui, RIGHT);
  const stage = rect(ui, STAGE);
  const title = rect(ui, `${RIGHT}/DetailTitle`);
  assert.ok(-stage.anchoredPosition.y >= 0, 'starts inside the page');
  assert.ok(-stage.anchoredPosition.y + stage.RectSize.y <= -title.anchoredPosition.y, 'ends above the details title');
  assert.ok(stage.anchoredPosition.x >= 0 && stage.anchoredPosition.x + stage.RectSize.x <= page.RectSize.x, 'fits the page width');
  assert.ok(stage.RectSize.y >= page.RectSize.y * 0.4, 'takes the upper part of the page');
  assert.deepEqual(childNames(ui, RIGHT), ['Stage', 'DetailTitle', 'Details']);
});

test('the stage shows one monster: an animation image that always faces right', () => {
  const ui = dex();
  assert.deepEqual(childNames(ui, STAGE), ['Ground', 'Actor', 'Notice']);
  const sprite = ui.getComponent(ACTOR, SPRITE);
  assert.equal(sprite.FlipX, true, 'monster art faces left, the stage flips it to face right');
  assert.equal(sprite.Type, 0, 'a plain image, never sliced or tiled');
  assert.equal(sprite.RaycastTarget, false, 'the stage never takes clicks');
  assert.equal(ui.find(ACTOR).jsonString.enable, false, 'nothing is drawn until a monster is selected');
  const actor = rect(ui, ACTOR);
  const stage = rect(ui, STAGE);
  assert.ok(actor.anchoredPosition.x > 0 && actor.anchoredPosition.x < stage.RectSize.x / 2, 'the attacker stands in the left half, leaving room on its right');
  // The art is drawn with its own pivot (the feet) at the rect centre, so scaling and flipping happen around the feet and the rect centre is the ground point.
  assert.deepEqual([actor.Pivot.x, actor.Pivot.y], [0.5, 0.5]);
  assert.ok(actor.anchoredPosition.y > 0 && actor.anchoredPosition.y < stage.RectSize.y / 2, 'the ground point is in the lower half of the stage');
});

test('five trial buttons sit under the left page list, in the ticket order', () => {
  const ui = dex();
  const list = rect(ui, `${LEFT}/List`);
  const page = rect(ui, LEFT);
  const bar = rect(ui, TRIAL);
  assert.ok(-bar.anchoredPosition.y >= -list.anchoredPosition.y + list.RectSize.y, 'below the monster list');
  assert.ok(-bar.anchoredPosition.y + bar.RectSize.y <= page.RectSize.y, 'inside the left page');
  assert.ok(bar.anchoredPosition.x + bar.RectSize.x <= page.RectSize.x);
  assert.deepEqual(childNames(ui, TRIAL), TRIAL_BUTTONS.map(([name]) => name));
  let previousRight = -Infinity;
  for (const [name, label] of TRIAL_BUTTONS) {
    const button = `${TRIAL}/${name}`;
    assert.ok(ui.getComponent(button, BUTTON), `${name} is a button`);
    assert.equal(ui.getComponent(button, TEXT).Text, label);
    const box = rect(ui, button);
    assert.ok(box.anchoredPosition.x >= previousRight, `${name} does not overlap the button before it`);
    assert.ok(box.anchoredPosition.x + box.RectSize.x <= bar.RectSize.x, `${name} stays inside the bar`);
    assert.ok(box.RectSize.y >= 44, `${name} is large enough to click`);
    previousRight = box.anchoredPosition.x + box.RectSize.x;
  }
});

test('MonsterDex binds the stage image and every trial button to the authored entities', () => {
  const source = read(MODULE);
  const ui = dex();
  const binds = [['stageSprite', ACTOR], ...TRIAL_BUTTONS.map(([name, , property]) => [property, `${TRIAL}/${name}`])];
  for (const [property, entity] of binds) {
    const declared = source.match(new RegExp(`property \\w+ ${property} = "([^"]*)"`));
    assert.ok(declared, `${property} is declared`);
    assert.equal(declared[1], ui.getId(entity), `${property} -> ${entity}`);
  }
});

test('sibling order numbers around the stage are real sibling indexes', () => {
  const ui = dex();
  for (const parent of [LEFT, RIGHT, STAGE, TRIAL]) {
    const names = childNames(ui, parent);
    const orders = names.map(name => ui.find(`${parent}/${name}`).jsonString.displayOrder);
    assert.deepEqual(orders, names.map((_, index) => index), `${parent} children are numbered 0..n-1`);
  }
});

test('trial playback goes through the public Play interface, wired to the authored buttons only', () => {
  const source = read(MODULE);
  assert.match(source, /@ExecSpace\("ClientOnly"\)\s*\n\s*method boolean Play\(string action\)/);
  // One table maps every trial action to its button; binding and highlighting both read it.
  const table = methodBody(source, 'TrialButtons');
  for (const [, , property] of TRIAL_BUTTONS) assert.match(table, new RegExp(`self\\.${property}\\b`), `${property} is in the table`);
  for (const action of ['IDLE', 'MOVE', 'ATTACK', 'HURT', 'DIE']) assert.match(table, new RegExp(`"${action}"`), `${action} is in the table`);
  assert.match(methodBody(source, 'EnsureBound'), /TrialButtons\(\)[\s\S]*self:Play\(/, 'binding walks the shared table and plays its action');
  assert.match(methodBody(source, 'RenderTrialButtons'), /TrialButtons\(\)/, 'highlighting walks the same table');
  assert.doesNotMatch(methodBody(source, 'EnsureBound'), /self\.(idle|move|attack|hurt|die)Button/, 'no second hand-written button list');
  assert.match(methodBody(source, 'GetSnapshot'), /\baction\b[\s\S]*\bevents\b/, 'the snapshot still carries the action and its event log');
  assert.match(methodBody(source, 'OnEndPlay'), /SpriteGUIAnimPlayerEndEvent/, 'the end-event subscription is released with the module');
});

test('idle and move loop, the other actions play once and return to idle on the animation end event', () => {
  const source = read(MODULE);
  assert.match(source, /SpriteGUIAnimPlayerEndEvent/, 'the return to idle is driven by the animation end event, not a timer');
  const start = methodBody(source, 'StartClip');
  assert.match(start, /SpriteAnimClipPlayType\.Loop/);
  assert.match(start, /SpriteAnimClipPlayType\.Onetime/);
  assert.doesNotMatch(source, /SetTimer|wait\(/, 'no timer decides when the clip ends');
  assert.match(methodBody(source, 'OnAnimationEnd'), /StartClip\("IDLE", true\)/, 'a finished one-shot goes back to idle, as part of the logged trial');
  assert.match(methodBody(source, 'RenderStage'), /StartClip\("IDLE", false\)/, 'the idle a shown monster starts with is not a logged trial');
  const specs = methodBody(source, 'ActionSpecs');
  const loops = Object.fromEntries([...specs.matchAll(/(\w+) = \{ field = "\w+", loop = (true|false)/g)].map(m => [m[1], m[2] === 'true']));
  assert.deepEqual(loops, { IDLE: true, MOVE: true, ATTACK: false, HURT: false, DIE: false });
});

test('attack, hurt and die play their own sound, blank sounds are skipped', () => {
  const source = read(MODULE);
  const sound = methodBody(source, 'PlaySoundOnce');
  assert.match(sound, /_SoundService:PlaySound\(/);
  assert.match(sound, /== ""/, 'a blank sound field is skipped');
  const specs = methodBody(source, 'ActionSpecs');
  assert.match(specs, /ATTACK = \{[^}]*sound = "attackSoundRuid"/);
  assert.match(specs, /HURT = \{[^}]*sound = "hurtSoundRuid"/);
  assert.match(specs, /DIE = \{[^}]*sound = "dieSoundRuid"/);
  assert.doesNotMatch(specs, /attackEffectRuid|hitEffectRuid|projectileRuid/, 'no attack effect, hit effect or projectile yet');
  assert.doesNotMatch(methodBody(source, 'StartClip'), /attackSoundRuid|attackEffectRuid|hitEffectRuid|projectileRuid/);
});

test('the stage scale is read from the battle camera setting and the native screen conversion, not typed in', () => {
  const service = read(SERVICE);
  const module = read(MODULE);
  assert.match(service, /ZoomRatio/);
  assert.match(module, /ScreenToWorldPosition/, 'the client measures the world width of the screen natively');
  assert.doesNotMatch(methodBody(module, 'StagePixelsPerUnit'), /\b(12\.8|7\.2|150|90|60|100|1920)\b/, 'no pixel or world scale literal');
  // The camera the service reads must be one single, consistent setting across every battle map.
  const zooms = ['template', 'formationsim', 'matchprobe'].map(name => {
    const map = MapBuilder.read(`map/${name}.map`);
    return map.component('BattleCameraAnchor', 'MOD.Core.CameraComponent').ZoomRatio;
  });
  assert.equal(new Set(zooms).size, 1, `all battle maps share one zoom ratio (${zooms.join(', ')})`);
});

test('the server finds the battle camera anchor the same way the battle map does', () => {
  const service = read(SERVICE);
  const battleLookup = read(CAMERA_MODULE).match(/map:GetChildByName\("(\w+)", false\)/);
  assert.ok(battleLookup, 'BattleFixedCamera looks the anchor up by name among the map children');
  const name = service.match(/property string BattleCameraAnchorName = "(\w+)"/);
  assert.ok(name, 'the service names the anchor in one property');
  assert.equal(name[1], battleLookup[1], 'both use the same anchor name');
  assert.match(methodBody(service, 'ReadBattleZoom'), /GetChildByName\(self\.BattleCameraAnchorName, false\)/, 'the same direct-child lookup, with the shared name');
  assert.match(service, /property string BattleMapPath = "\/maps\/template"/, 'reads the template battle map, which the server holds in every Play');
  const map = MapBuilder.read('map/template.map');
  assert.ok(map.component(name[1], 'MOD.Core.CameraComponent'), 'the template map has that anchor with a camera');
});

test('the rows are always sent: a missing battle camera only switches the stage off', () => {
  const body = methodBody(read(SERVICE), 'RequestRows');
  const afterZoom = body.slice(body.indexOf('ReadBattleZoom'));
  assert.doesNotMatch(afterZoom, /\breturn\b/, 'nothing after reading the zoom may abandon the reply');
  assert.match(afterZoom, /self:ReceiveBattleCamera\(/, 'the zoom (or its absence) is still reported');
  assert.match(afterZoom, /self:Receive\(rows, senderUserId\)/, 'the rows are sent regardless');
  const source = read(MODULE);
  assert.match(methodBody(source, 'ObserveBattleCamera'), /battleZoom = nil/, 'an unreadable zoom clears the stage scale');
  assert.match(methodBody(source, 'GetSnapshot'), /\bstageAvailable\b/, 'the snapshot reports whether the stage can run');
});

test('the stage scale uses the full screen width, never the book picture, and no bare pixel constant', () => {
  const module = read(MODULE);
  const pixels = methodBody(module, 'StagePixelsPerUnit');
  assert.match(pixels, /ScreenToUIPosition/, 'canvas width comes from the screen corners in UI coordinates');
  assert.doesNotMatch(pixels, /RectSize|\bbook\b/, 'not the size of one authored entity');
  assert.match(module, /property number PixelsPerWorldUnit = 100/, 'art pixels per world unit is a named property');
  assert.doesNotMatch(methodBody(module, 'StageLayout'), /\/ 100/, 'no magic 100');
});

test('the stage notice is an authored text bound to the module and hidden until the stage is unavailable', () => {
  const source = read(MODULE);
  const ui = dex();
  const declared = source.match(/property \w+ stageNotice = "([^"]*)"/);
  assert.ok(declared, 'stageNotice is declared');
  assert.equal(declared[1], ui.getId(NOTICE));
  assert.equal(ui.find(NOTICE).jsonString.enable, false, 'hidden until needed');
  const message = source.match(/property string StageUnavailableText = "([^"]+)"/);
  assert.ok(message, 'the module owns the message text');
  assert.equal(ui.getComponent(NOTICE, TEXT).Text, message[1], 'authored text matches the module text');
});

test('the constant tables are built once and shared', () => {
  const source = read(MODULE);
  for (const name of ['ActionSpecs', 'DetailSpecs']) {
    assert.match(methodBody(source, name), /if self\._T\.\w+ == nil then/, `${name} builds its table only on first use`);
  }
});

test('BuildDetails keeps its nesting shallow', () => {
  const body = methodBody(read(MODULE), 'BuildDetails').split('\n').filter(line => line.trim() !== '');
  const base = body[0].match(/^ */)[0].length;
  const depth = Math.max(...body.map(line => (line.match(/^ */)[0].length - base) / 4));
  assert.ok(depth <= 3, `nesting depth ${depth} stays within the limit`);
});

test('stage size follows the model scale published with the dex row', () => {
  const source = read(MODULE);
  const layout = methodBody(source, 'StageLayout');
  assert.match(layout, /scaleX/);
  assert.match(layout, /scaleY/);
  assert.match(layout, /StagePixelsPerUnit/);
});
