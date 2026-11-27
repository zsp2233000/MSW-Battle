#!/usr/bin/env node
'use strict';

// Builds ui/WorldMapGroup.ui (the faction-war world map) with the msw-ui-system UIBuilder.
// Town nodes and place labels come from layout.json (written by paint_worldmap.cjs), the art from ruids.json.
//
//   node assets/worldmap/build_ui.cjs
//
// FactionWarMapUI.mlua finds every entity by path under /ui/WorldMapGroup, so keep the paths below in step with it.

const path = require('node:path');
const { UIBuilder } = require('../../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');

const ROOT = path.join(__dirname, '..', '..');
const layout = require('./layout.json');
const art = require('./ruids.json');
const { addSelectUi } = require('./select_ui.cjs');
const { addFrontlines, addFrontlineLegend, LEGEND_LABEL, LEGEND_LABEL_POS, NOTE } = require('./build_frontline_ui.cjs');
// The near-full-screen layout (#132): the window, the viewport and the town list take their rectangles from the module that build_fullscreen_ui.cjs lays an existing file out with.
const { geo, addHint, plate, MASK_COLOR, SIDE_COLOR, WINDOW_FRAME } = require('./fullscreen_ui.cjs');

// Cardgame theme parts (msw-ui-kit cardgame palette), as used by the rest of the game.
const CARD_BUTTON = { normal: '9505617fb63c447c8ff9c15c18d88064', highlighted: '398dfdb46d534ea2a2373e4f5d29ae2a', pressed: '1016088c7aca43c78cdd06c01645ab1b' };
const X_BUTTON = { normal: 'e01ef74a1ecf444bbb013c4313a8d0a9', highlighted: 'f24a6333e4df404795e922ec2966e997', pressed: '5952570d481245a9a4fbe562f3c030c5' };
const GAUGE = 'f0911af597259044aa624a11332c0595';      // HP gauge slice (Sliced fill, width-driven)
const HERE_ARROW = '96392b1df6724d43abab0ec1988aa7c4'; // animationclip 20x36, downward marker (plays directly as ImageRUID)
const OUTLINE = { outline: true, outline_color: { r: 0, g: 0, b: 0, a: 0.7 }, outline_width: 0.2, face_dilate: 0.2 };
const GOLD = '#EEC78F';
const NEUTRAL = { r: 0.62, g: 0.6, b: 0.56, a: 1 };
const TOWNS = ['nanzih', 'zuoying', 'gushan', 'yancheng'];
const NAMES = { nanzih: '楠梓', zuoying: '左營', gushan: '鼓山', yancheng: '鹽埕' };

function swap(b, entity, states) {
  b.patchComponent(entity, 'MOD.Core.ButtonComponent', {
    Transition: 2,
    ImageRUIDs: {
      HighlightedSprite: { DataId: states.highlighted },
      PressedSprite: { DataId: states.pressed },
      SelectedSprite: { DataId: states.normal },
      DisabledSprite: { DataId: states.pressed },
    },
  });
}

// WORLDMAP_UI_OUT writes the build somewhere else (tests/worldmap_fullscreen_contract.test.cjs compares a full build with the committed file without touching it).
const uiFile = process.env.WORLDMAP_UI_OUT || path.join(ROOT, 'ui', 'WorldMapGroup.ui');
const b = new UIBuilder('WorldMapGroup', 9, true);
b.patchComponent('/ui/WorldMapGroup', 'MOD.Core.UIGroupComponent', { GroupType: 1, GroupOrder: 9, DefaultShow: true });

// Entry button, shown by the script only while the player stands in a town (below the system buttons in the top-right corner).
b.button('OpenButton', '大地圖 (M)', { anchor: 'top-right', pos: [-24, -150], rect_size: [210, 88], font_size: 26,
  image_ruid: CARD_BUTTON.normal, bg_color: '#FFFFFF', color: '#FFFFFF', enable: false });
swap(b, 'OpenButton', CARD_BUTTON);
b.patchComponent('OpenButton', 'MOD.Core.TextGUIRendererComponent', { OutlineColor: OUTLINE.outline_color, OutlineWidth: 0.2, FaceDilate: 0.2, FontStyle: 1 });

// Full-screen mask in opaque deep brown (it covers the town, the HUD and the siege panel, so it needs no backdrop under the window); the script toggles Overlay.
// Stretch alone leaves the sprite's RectSize at 100×100 in Maker. The window leaves 40 px on every side.
b.sprite('Overlay', { anchor: 'stretch', rect_size: [1920, 1080], color: '#241C14', alpha: MASK_COLOR.a, raycast: true, enable: false });
b.sprite('Overlay/Window', { ...geo('Overlay/Window'), image_ruid: WINDOW_FRAME, color: '#FFFFFF', sprite_type: 1, raycast: true });
b.patchComponent('Overlay/Window', 'MOD.Core.SpriteGUIRendererComponent', { FillCenter: false });

// The transparent input surface and the mask stay fixed. Only the content moves. The viewport fills the window and FactionWarMapUI draws it at the base scale (1.2),
// so the map (740 × 810 in its own units) is centred in it and as tall as the window at 1x.
const VIEW = 'Overlay/Window/Map';
const MAP = `${VIEW}/Content`;
const size = [layout.size.w, layout.size.h];
b.mask(VIEW, geo(VIEW));
b.empty(MAP, { rect_size: size });
b.sprite(`${MAP}/Terrain`, { rect_size: size, image_ruid: art.terrain, color: '#FFFFFF', sprite_type: 0 });
b.empty(`${MAP}/Districts`, { anchor: 'stretch' });
for (const id of TOWNS) {
  const { x, y, w, h } = layout.towns[id].mask;
  b.sprite(`${MAP}/Districts/${id}`, { pos: [x, y], rect_size: [w, h], image_ruid: art[`mask_${id}`], color: { ...NEUTRAL, a: 0.25 }, sprite_type: 0 });
}
b.empty(`${MAP}/Places`, { anchor: 'stretch' });
layout.places.forEach(place => {
  b.text(`${MAP}/Places/${place.code}`, place.name, { size: 19, color: '#493728', bold: true,
    pos: [place.x, place.y], rect_size: [84, 26] });
});
b.text(`${MAP}/Sea`, '台灣海峽', { size: 22, color: '#E6F1F3', pos: [-261, -270], rect_size: [120, 32] });
addFrontlines(b);
b.empty(`${MAP}/Towns`, { anchor: 'stretch' });
for (const id of TOWNS) {
  const node = layout.towns[id];
  const town = `${MAP}/Towns/${id}`;
  b.empty(town, { pos: [node.x, node.y], rect_size: [64, 64] });
  b.sprite(`${town}/Crest`, { rect_size: [60, 60], image_ruid: art.crest, color: NEUTRAL, sprite_type: 0 });
  b.text(`${town}/Name`, NAMES[id], { size: 26, color: '#FFFFFF', bold: true, ...OUTLINE, alignment: 5, pos: [-106, 12], rect_size: [140, 30] });
  b.text(`${town}/Capital`, '主城', { size: 21, color: '#FACA33', bold: true, ...OUTLINE, alignment: 5, pos: [-96, 40], rect_size: [120, 28], enable: false });
  b.sprite(`${town}/Arrow`, { anchor: 'middle-center', pos: [0, 60], rect_size: [30, 54], image_ruid: HERE_ARROW, color: '#FFFFFF', sprite_type: 0, enable: false });
  // The arrow is a 4-frame animationclip; the builder's default AnimClipPlayType is Onetime (0), which would freeze it after one pass.
  b.patchComponent(`${town}/Arrow`, 'MOD.Core.SpriteGUIRendererComponent', { AnimClipPlayType: 1 });
}

// No controls inside the moving map can intercept drag input. The fixed surface
// receives mouse and touch from the entire visible rect, not the scaled terrain.
const INPUT = `${VIEW}/Input`;
b.sprite(INPUT, { ...geo(INPUT), alpha: 0, raycast: true });
b.addComponent(INPUT, 'MOD.Core.UITouchReceiveComponent');

// --- the town list: own faction, strength list north to south, legend, status -------------------
// It floats over the map (#132): translucent, in the empty space on the right of the map at 1x, and it takes the touches that land on it (raycast), so a drag on it
// does not move the map under it. It is created after the map, so it is drawn above it.
const SIDE = 'Overlay/Window/Side';
b.sprite(SIDE, { ...geo(SIDE), color: SIDE_COLOR, alpha: SIDE_COLOR.a, sprite_type: 1, raycast: true });
b.text(`${SIDE}/FactionLabel`, '你的陣營', { size: 22, color: GOLD, ...OUTLINE, ...geo(`${SIDE}/FactionLabel`) });
b.text(`${SIDE}/Faction`, '讀取中…', { size: 34, color: GOLD, bold: true, ...OUTLINE, ...geo(`${SIDE}/Faction`) });
b.sprite(`${SIDE}/Divider`, { ...geo(`${SIDE}/Divider`), color: { r: 0.93, g: 0.78, b: 0.56, a: 0.5 }, sprite_type: 1 });
b.text(`${SIDE}/Header`, '城鎮兵力（由北到南）', { size: 22, color: GOLD, ...OUTLINE, ...geo(`${SIDE}/Header`) });
b.empty(`${SIDE}/Rows`, geo(`${SIDE}/Rows`));
TOWNS.forEach(id => {
  const row = `${SIDE}/Rows/${id}`;
  b.sprite(row, { ...geo(row), color: { r: 0, g: 0, b: 0, a: 0.3 }, sprite_type: 1 });
  b.text(`${row}/Name`, NAMES[id], { size: 26, color: '#FFFFFF', bold: true, ...OUTLINE, alignment: 3, ...geo(`${row}/Name`) });
  b.text(`${row}/Here`, '你在這裡', { size: 20, color: '#FACA33', bold: true, ...OUTLINE, alignment: 3, ...geo(`${row}/Here`), enable: false });
  b.text(`${row}/Owner`, '讀取中', { size: 22, color: '#DAD1C2', ...OUTLINE, alignment: 3, ...geo(`${row}/Owner`) });
  b.text(`${row}/Value`, '—', { size: 24, color: '#FFFFFF', bold: true, ...OUTLINE, alignment: 5, ...geo(`${row}/Value`) });
  b.sprite(`${row}/Bar`, { ...geo(`${row}/Bar`), color: { r: 0.05, g: 0.035, b: 0.02, a: 0.85 }, sprite_type: 1 });
  b.sprite(`${row}/Bar/Fill`, { ...geo(`${row}/Bar/Fill`), image_ruid: GAUGE, color: NEUTRAL, sprite_type: 1, enable: false });
});
b.empty(`${SIDE}/Legend`, geo(`${SIDE}/Legend`));
b.sprite(`${SIDE}/Legend/Ally`, { ...geo(`${SIDE}/Legend/Ally`), color: NEUTRAL, sprite_type: 1 });
b.text(`${SIDE}/Legend/Ally/Label`, '我方', { size: 22, color: '#FFFFFF', ...OUTLINE, alignment: 3, ...geo(`${SIDE}/Legend/Ally/Label`) });
b.sprite(`${SIDE}/Legend/Enemy`, { ...geo(`${SIDE}/Legend/Enemy`), color: NEUTRAL, sprite_type: 1 });
b.text(`${SIDE}/Legend/Enemy/Label`, '敵方', { size: 22, color: '#FFFFFF', ...OUTLINE, alignment: 3, ...geo(`${SIDE}/Legend/Enemy/Label`) });
addFrontlineLegend(b);
b.patch(`${SIDE}/Legend/Link`, geo(`${SIDE}/Legend/Link`));
b.text(`${SIDE}/Legend/Link/Label`, LEGEND_LABEL, { size: 22, color: '#FFFFFF', ...OUTLINE, alignment: 3, anchor: 'middle-left', pos: LEGEND_LABEL_POS, rect_size: [90, 30] });
b.text(`${SIDE}/Note`, NOTE, { size: 20, color: '#E8DCC8', ...OUTLINE, ...geo(`${SIDE}/Note`) });
b.text(`${SIDE}/Status`, '正在讀取戰況…', { size: 20, color: GOLD, ...OUTLINE, ...geo(`${SIDE}/Status`) });

// --- the corners of the window, above the map and the town list: the title, the close button, the zoom hint and the closing hint ---------
b.text('Overlay/Window/Title', '國戰大地圖', { size: 32, color: '#FFFFFF', bold: true, ...OUTLINE, ...geo('Overlay/Window/Title') });
plate(b, 'Overlay/Window/Title');
b.button('Overlay/Window/Close', '', { ...geo('Overlay/Window/Close'), image_ruid: X_BUTTON.normal, bg_color: '#FFFFFF', sprite_type: 0 });
swap(b, 'Overlay/Window/Close', X_BUTTON);
b.text('Overlay/Window/MapHint', '高雄 38 區｜滾輪縮放・拖曳移動', { size: 22, color: '#E8DCC8', ...OUTLINE, ...geo('Overlay/Window/MapHint') });
plate(b, 'Overlay/Window/MapHint');
addHint(b, '按 M 鍵或右上角按鈕關閉');

// The NPC's target selection (#124): a pick button and a veil on each row, and the confirmation window above the map.
addSelectUi(b);

b.write(uiFile, { lint_verbose: true });
