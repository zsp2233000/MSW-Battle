'use strict';

// The near-full-screen layout of ui/WorldMapGroup.ui (#132), in one place for the two ways of building the file:
//   - assets/worldmap/build_ui.cjs makes the file from nothing and takes every rectangle below through geo();
//   - assets/worldmap/build_fullscreen_ui.cjs loads the file that exists (Maker keeps the entities) and applyFullscreenLayout() lays it out.
// Both read GEOMETRY, so they cannot drift apart. FactionWarMapUI.mlua finds every entity by path under /ui/WorldMapGroup, so no path changes except that the closing
// hint moves out of the town list to the window (Overlay/Window/Hint) and the backdrop is gone (the mask is opaque by itself).
//
// The screen is 1920 x 1080 and the window leaves 40 px on every side: 1840 x 1000. The map is 740 x 810 (the size it was painted at); the viewport that clips it is
// drawn at BASE_SCALE (1.2), so at 1x (the full overview) the map is 888 x 972 on the screen: as tall as the viewport, centred. The viewport is 1500 x 810 in its
// own units, 1800 x 972 on the screen, so everything FactionWarMapUI computes inside it (zoom, offsets, clamping, hit tests) keeps its meaning. The scale itself is not
// authored: Maker's import ignores a UIScale written in the file (Maker run of #132: 1.2 in the file, 1 in Play, with Scale as well), so FactionWarMapUI sets it on the
// viewport when the map opens (its property BaseScale, which tests/worldmap_fullscreen_contract.test.cjs holds equal to BASE_SCALE here). The town list
// floats on top, in the empty space on the right of the map: 420 wide, so at 1x it starts 28 px after the map ends, and when the map is zoomed it covers part of it.
// The title, the close button and the two hints stand at the four corners of the window. The close button is not at the very corner of the screen: the engine draws
// its friends and menu buttons there (about 220 x 130, ui-fundamentals.md §9.3), so it sits left of them.

const MASK_COLOR = { r: 0x24 / 255, g: 0x1C / 255, b: 0x14 / 255, a: 1 };       // the deep brown #241C14, opaque
const WINDOW_FRAME = 'ac319875b43f40ea86a069c468a1a26e';                         // Cardgame Base_4, the hollow frame the dialogs use: only its border is drawn
const SKIN = '2860136c06ab075439721c027de365af';                                   // the builder's default sprite skin (sliced), as the town list uses
const LABEL_PLATE = { r: 0.07, g: 0.045, b: 0.025, a: 0.62 };                    // a dark plate behind each corner label, so it reads over the zoomed map
const SIDE_COLOR = { r: 0.12, g: 0.075, b: 0.04, a: 0.82 };                     // the brown of the town list, translucent
const WINDOW_SIZE = [1840, 1000];
const BASE_SCALE = 1.2;
const VIEW_SIZE = [1500, 810];
const SIDE_ROW = [380, 84];
const BAR_WIDTH = 240;
const SIDE = 'Overlay/Window/Side';
const TOWNS = ['nanzih', 'zuoying', 'gushan', 'yancheng'];

const PIVOT = {
  'top-left': [0, 1], 'top-center': [0.5, 1], 'top-right': [1, 1],
  'middle-left': [0, 0.5], 'middle-center': [0.5, 0.5], 'middle-right': [1, 0.5],
  'bottom-left': [0, 0], 'bottom-center': [0.5, 0], 'bottom-right': [1, 0],
};
// A fixed anchor with the pivot on the same point of the node: pos is the margin from that edge or corner of the parent.
const at = (anchor, pos, rect_size) => ({ anchor, pos, rect_size, pivot: PIVOT[anchor] });

const GEOMETRY = {
  'Overlay/Window': at('middle-center', [0, 0], WINDOW_SIZE),
  'Overlay/Window/Map': at('middle-center', [0, 0], VIEW_SIZE),
  'Overlay/Window/Map/Input': at('middle-center', [0, 0], VIEW_SIZE),
  'Overlay/Window/Title': at('top-left', [28, -12], [200, 52]),
  'Overlay/Window/Close': at('top-right', [-188, -8], [88, 96]),
  'Overlay/Window/MapHint': at('bottom-left', [28, 12], [380, 34]),
  'Overlay/Window/Hint': at('bottom-right', [-28, 12], [300, 34]),
  [SIDE]: at('middle-right', [-28, -20], [420, 800]),
  [`${SIDE}/FactionLabel`]: at('top-center', [0, -20], [380, 30]),
  [`${SIDE}/Faction`]: at('top-center', [0, -54], [380, 44]),
  [`${SIDE}/Divider`]: at('top-center', [0, -108], [360, 2]),
  [`${SIDE}/Header`]: at('top-center', [0, -120], [380, 30]),
  [`${SIDE}/Rows`]: at('top-center', [0, -160], [SIDE_ROW[0], 4 * 92]),
  [`${SIDE}/Legend`]: at('top-center', [0, -540], [380, 40]),
  [`${SIDE}/Legend/Ally`]: at('middle-left', [10, 0], [28, 28]),
  [`${SIDE}/Legend/Ally/Label`]: at('middle-left', [36, 0], [60, 30]),
  [`${SIDE}/Legend/Enemy`]: at('middle-left', [116, 0], [28, 28]),
  [`${SIDE}/Legend/Enemy/Label`]: at('middle-left', [36, 0], [60, 30]),
  [`${SIDE}/Legend/Link`]: at('middle-left', [224, 0], [48, 8]),
  [`${SIDE}/Note`]: at('top-center', [0, -592], [380, 64]),
  [`${SIDE}/Notice`]: at('top-center', [0, -664], [380, 36]),
  [`${SIDE}/Status`]: at('bottom-center', [0, 20], [380, 30]),
};
TOWNS.forEach((id, n) => {
  const row = `${SIDE}/Rows/${id}`;
  GEOMETRY[row] = at('top-center', [0, -n * 92], SIDE_ROW);
  GEOMETRY[`${row}/Name`] = at('middle-left', [16, 14], [100, 34]);
  GEOMETRY[`${row}/Here`] = at('middle-left', [16, -20], [100, 26]);
  GEOMETRY[`${row}/Owner`] = at('middle-left', [124, 14], [130, 30]);
  GEOMETRY[`${row}/Value`] = at('middle-right', [-16, 14], [110, 30]);
  GEOMETRY[`${row}/Bar`] = at('middle-right', [-16, -20], [BAR_WIDTH, 16]);
  GEOMETRY[`${row}/Bar/Fill`] = at('middle-left', [0, 0], [BAR_WIDTH, 16]);
});
// These stretch over their row: only the size is set, and 88 high is the touch size of the pick button.
const STRETCHED = TOWNS.flatMap(id => [[`${SIDE}/Rows/${id}/Pick`, [SIDE_ROW[0], 88]], [`${SIDE}/Rows/${id}/Dim`, SIDE_ROW]]);
// The creators and patch() take the same geometry keys.
const geo = path => {
  if (GEOMETRY[path] === undefined) throw new Error(`no geometry for ${path}`);
  return { ...GEOMETRY[path] };
};

const TRANSFORM = 'MOD.Core.UITransformComponent';
const SPRITE = 'MOD.Core.SpriteGUIRendererComponent';
const TEXT = 'MOD.Core.TextGUIRendererComponent';
const GOLD = '#EEC78F';
const OUTLINE = { outline: true, outline_color: { r: 0, g: 0, b: 0, a: 0.7 }, outline_width: 0.2, face_dilate: 0.2 };
// The text enums of TextGUIRendererComponent (not the 0-8 index of text()): centred, middle.
const CENTER = 2;
const MIDDLE = 512;

// The direct children of Overlay/Window, bottom to top: the map first, the town list over it, then the corner controls over both.
const WINDOW_ORDER = ['Map', 'Side', 'Title', 'Close', 'MapHint', 'Hint'];

// Move the children `names` of `parent` (each with everything under it, in its own order) to just after the last entity under `after`, in that order. Maker takes the render
// order from the order of the entities, and a new entity is appended at the very end, so a delta build has to put the corner controls behind the map and the town list.
// Only the small ones move: the map and the town list keep their place in the file (a diff that moved them would be thousands of lines).
function moveAfter(b, parent, names, after) {
  const base = `${b.root_path}/${parent}/`;
  const blockOf = name => b.entities.filter(entity => entity.path === `${base}${name}` || entity.path.startsWith(`${base}${name}/`));
  const moving = names.flatMap(blockOf);
  const gone = new Set(moving);
  const rest = b.entities.filter(entity => !gone.has(entity));
  const anchor = Math.max(...blockOf(after).map(entity => rest.indexOf(entity)));
  rest.splice(anchor + 1, 0, ...moving);
  b.entities.splice(0, b.entities.length, ...rest);
}

// patch() re-writes the whole transform of an entity even when nothing in it moves, which shows in a diff of the file as the whole block. Only an entity whose rectangle
// differs from `geo` is patched (the anchor point of `at()` is the pivot).
const same = (actual, expected) => actual !== undefined && Math.abs(actual.x - expected[0]) < 1e-9 && Math.abs(actual.y - expected[1]) < 1e-9;
function place(b, path) {
  const wanted = geo(path);
  const now = b.getComponent(path, TRANSFORM);
  if (same(now.RectSize, wanted.rect_size) && same(now.anchoredPosition, wanted.pos) && same(now.Pivot, wanted.pivot) && same(now.AnchorsMin, wanted.pivot) && same(now.AnchorsMax, wanted.pivot)) return;
  b.patch(path, wanted);
}

function applyFullscreenLayout(b) {
  // The mask: opaque deep brown over the whole screen. It is its own backing, so the old backdrop under the window goes.
  if (b.find('Overlay/Backdrop')) b.remove('Overlay/Backdrop');
  b.patchComponent('Overlay', SPRITE, { Color: MASK_COLOR, RaycastTarget: true });
  b.patch('Overlay/Window', { display_order: 0 });

  // The window leaves 40 px on every side. The viewport is laid out in its own units and the script draws it at the base scale (see above), so the file keeps the default
  // scale (an earlier run of this script wrote the base scale into the file, where the import ignores it: that is undone here).
  place(b, 'Overlay/Window');
  b.patchComponent('Overlay/Window', SPRITE, { ImageRUID: { DataId: WINDOW_FRAME }, FillCenter: false, Color: { r: 1, g: 1, b: 1, a: 1 }, Type: 1 });
  place(b, 'Overlay/Window/Map');
  b.patchComponent('Overlay/Window/Map', TRANSFORM, { UIScale: { x: 1, y: 1, z: 1 }, Scale: { x: 1, y: 1, z: 1 } });
  place(b, 'Overlay/Window/Map/Input');

  // The town list: translucent, narrower, over the map, and it takes the touches that land on it.
  place(b, SIDE);
  b.patchComponent(SIDE, SPRITE, { Color: SIDE_COLOR, RaycastTarget: true });
  for (const path of Object.keys(GEOMETRY)) {
    if (path.startsWith(`${SIDE}/`)) place(b, path);
  }
  for (const [path, size] of STRETCHED) {
    if (!same(b.getComponent(path, TRANSFORM).RectSize, size)) b.patch(path, { rect_size: size });
  }

  // The corners. The closing hint leaves the town list and stands at the bottom right.
  place(b, 'Overlay/Window/Title');
  b.patchComponent('Overlay/Window/Title', TEXT, { HorizontalAlignment: CENTER, VerticalAlignment: MIDDLE });
  plate(b, 'Overlay/Window/Title');
  place(b, 'Overlay/Window/Close');
  place(b, 'Overlay/Window/MapHint');
  b.patchComponent('Overlay/Window/MapHint', TEXT, { HorizontalAlignment: CENTER, VerticalAlignment: MIDDLE });
  plate(b, 'Overlay/Window/MapHint');
  const closing = b.find(`${SIDE}/Hint`) ? b.getComponent(`${SIDE}/Hint`, TEXT).Text : '按 M 鍵或右上角按鈕關閉';
  if (b.find(`${SIDE}/Hint`)) b.remove(`${SIDE}/Hint`);
  addHint(b, closing);
  moveAfter(b, 'Overlay/Window', WINDOW_ORDER.slice(WINDOW_ORDER.indexOf('Side') + 1), 'Side');
  WINDOW_ORDER.forEach((name, index) => { b.find(`Overlay/Window/${name}`).jsonString.displayOrder = index; });
  return b;
}

// The closing hint at the bottom right corner of the window.
function addHint(b, label) {
  b.text('Overlay/Window/Hint', label, { size: 22, color: '#E8DCC8', ...OUTLINE, ...geo('Overlay/Window/Hint') });
  plate(b, 'Overlay/Window/Hint');
}

// The dark plate behind a corner label: the text entity's own background sprite (a text is made with an invisible, empty one), which takes no click.
function plate(b, path) {
  b.patchComponent(path, SPRITE, { ImageRUID: { DataId: SKIN }, Type: 1, Color: LABEL_PLATE, RaycastTarget: false });
}

module.exports = {
  GEOMETRY, STRETCHED, geo, applyFullscreenLayout, moveAfter, addHint, plate,
  MASK_COLOR, SIDE_COLOR, WINDOW_FRAME, LABEL_PLATE, WINDOW_SIZE, VIEW_SIZE, BASE_SCALE, SIDE_ROW, BAR_WIDTH, WINDOW_ORDER, GOLD,
  CENTER, MIDDLE,
};
