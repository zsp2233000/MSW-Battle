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
  assert.deepEqual(childNames(ui, STAGE).filter(name => name === 'Actor'), ['Actor']);
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
  const bind = methodBody(source, 'EnsureBound');
  for (const [, , property] of TRIAL_BUTTONS) assert.match(bind, new RegExp(`self\\.${property}\\.Entity`), `${property} is connected`);
  for (const action of ['IDLE', 'MOVE', 'ATTACK', 'HURT', 'DIE']) assert.match(bind, new RegExp(`Play\\("${action}"\\)`), `${action} button plays ${action}`);
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

test('hurt and die play their own sound, blank sounds are skipped, attack plays no sound yet', () => {
  const source = read(MODULE);
  const sound = methodBody(source, 'PlaySoundOnce');
  assert.match(sound, /_SoundService:PlaySound\(/);
  assert.match(sound, /== ""/, 'a blank sound field is skipped');
  const specs = methodBody(source, 'ActionSpecs');
  assert.match(specs, /HURT = \{[^}]*sound = "hurtSoundRuid"/);
  assert.match(specs, /DIE = \{[^}]*sound = "dieSoundRuid"/);
  assert.doesNotMatch(specs, /attackSoundRuid|attackEffectRuid|hitEffectRuid|projectileRuid/, 'no attack sound, effect or projectile in this ticket');
  assert.doesNotMatch(methodBody(source, 'StartClip'), /attackSoundRuid|attackEffectRuid|hitEffectRuid|projectileRuid/);
});

test('the stage scale is read from the battle camera setting and the native screen conversion, not typed in', () => {
  const service = read(SERVICE);
  const module = read(MODULE);
  assert.match(service, /BattleCameraAnchor/, 'the server reads the battle camera anchor');
  assert.match(service, /ZoomRatio/);
  assert.match(module, /ScreenToWorldPosition/, 'the client measures the world width of the screen natively');
  assert.doesNotMatch(methodBody(module, 'StagePixelsPerUnit'), /\b(12\.8|7\.2|150|90|60|1920)\b/, 'no pixel or world scale literal');
  // The camera the service reads must be one single, consistent setting across every battle map.
  const zooms = ['template', 'formationsim', 'matchprobe'].map(name => {
    const map = MapBuilder.read(`map/${name}.map`);
    return map.component('BattleCameraAnchor', 'MOD.Core.CameraComponent').ZoomRatio;
  });
  assert.equal(new Set(zooms).size, 1, `all battle maps share one zoom ratio (${zooms.join(', ')})`);
  assert.match(service, /\/maps\/template\/BattleCameraAnchor/, 'reads the template battle map, which the server holds in every Play');
});

test('stage size follows the model scale published with the dex row', () => {
  const source = read(MODULE);
  const layout = methodBody(source, 'StageLayout');
  assert.match(layout, /scaleX/);
  assert.match(layout, /scaleY/);
  assert.match(layout, /StagePixelsPerUnit/);
});
