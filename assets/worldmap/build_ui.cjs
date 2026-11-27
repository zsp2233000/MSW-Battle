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

// Cardgame theme parts (msw-ui-kit cardgame palette), as used by the rest of the game.
const CARD_BUTTON = { normal: '9505617fb63c447c8ff9c15c18d88064', highlighted: '398dfdb46d534ea2a2373e4f5d29ae2a', pressed: '1016088c7aca43c78cdd06c01645ab1b' };
const X_BUTTON = { normal: 'e01ef74a1ecf444bbb013c4313a8d0a9', highlighted: 'f24a6333e4df404795e922ec2966e997', pressed: '5952570d481245a9a4fbe562f3c030c5' };
const PANEL_BG = 'd9b68fae16404c5c81228b6c45cf40a5';   // Panel_3 Background_1 (Sliced)
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

const uiFile = path.join(ROOT, 'ui', 'WorldMapGroup.ui');
const b = new UIBuilder('WorldMapGroup', 9, true);
b.patchComponent('/ui/WorldMapGroup', 'MOD.Core.UIGroupComponent', { GroupType: 1, GroupOrder: 9, DefaultShow: true });

// Entry button, shown by the script only while the player stands in a town (below the system buttons in the top-right corner).
b.button('OpenButton', '大地圖 (M)', { anchor: 'top-right', pos: [-24, -150], rect_size: [210, 88], font_size: 26,
  image_ruid: CARD_BUTTON.normal, bg_color: '#FFFFFF', color: '#FFFFFF', enable: false });
swap(b, 'OpenButton', CARD_BUTTON);
b.patchComponent('OpenButton', 'MOD.Core.TextGUIRendererComponent', { OutlineColor: OUTLINE.outline_color, OutlineWidth: 0.2, FaceDilate: 0.2, FontStyle: 1 });

// Full-screen dimmer + window; the script toggles Overlay.
b.sprite('Overlay', { anchor: 'stretch', color: '#000000', alpha: 0.55, raycast: true, enable: false });
b.sprite('Overlay/Window', { anchor: 'middle-center', rect_size: [1360, 960], image_ruid: PANEL_BG, color: '#FFFFFF', sprite_type: 1, raycast: true });
b.text('Overlay/Window/Title', '國戰大地圖', { size: 32, color: '#FFFFFF', bold: true, ...OUTLINE, anchor: 'top-center', pos: [0, -30], rect_size: [600, 56] });
b.button('Overlay/Window/Close', '', { anchor: 'top-right', pos: [-16, -12], rect_size: [88, 96], image_ruid: X_BUTTON.normal, bg_color: '#FFFFFF', sprite_type: 0 });
swap(b, 'Overlay/Window/Close', X_BUTTON);

// The transparent input surface and the mask stay fixed. Only the content moves.
const VIEW = 'Overlay/Window/Map';
const MAP = `${VIEW}/Content`;
const size = [layout.size.w, layout.size.h];
b.mask(VIEW, { anchor: 'middle-left', pivot: [0.5, 0.5], pos: [44 + size[0] / 2, -24], rect_size: size });
b.empty(MAP, { rect_size: size });
b.sprite(`${MAP}/Terrain`, { anchor: 'stretch', image_ruid: art.terrain, color: '#FFFFFF', sprite_type: 0 });
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
b.empty(`${MAP}/Links`, { anchor: 'stretch' });
for (let n = 1; n <= 3; n++) {
  b.sprite(`${MAP}/Links/Link${n}`, { anchor: 'middle-center', rect_size: [100, 6], color: { r: 0.29, g: 0.18, b: 0.09, a: 0.85 }, sprite_type: 1, enable: false });
}
b.empty(`${MAP}/Towns`, { anchor: 'stretch' });
for (const id of TOWNS) {
  const node = layout.towns[id];
  const town = `${MAP}/Towns/${id}`;
  b.empty(town, { pos: [node.x, node.y], rect_size: [64, 64] });
  b.sprite(`${town}/Crest`, { rect_size: [60, 60], image_ruid: art.crest, color: NEUTRAL, sprite_type: 0 });
  b.text(`${town}/Name`, NAMES[id], { size: 26, color: '#FFFFFF', bold: true, ...OUTLINE, alignment: 5, pos: [-106, 12], rect_size: [140, 30] });
  b.text(`${town}/Strength`, '兵力 —', { size: 21, color: '#FFF2C8', ...OUTLINE, alignment: 5, pos: [-106, -16], rect_size: [140, 28] });
  b.text(`${town}/Capital`, '主城', { size: 21, color: '#FACA33', bold: true, ...OUTLINE, alignment: 5, pos: [-96, 40], rect_size: [120, 28], enable: false });
  b.sprite(`${town}/Arrow`, { anchor: 'middle-center', pos: [0, 60], rect_size: [30, 54], image_ruid: HERE_ARROW, color: '#FFFFFF', sprite_type: 0, enable: false });
  // The arrow is a 4-frame animationclip; the builder's default AnimClipPlayType is Onetime (0), which would freeze it after one pass.
  b.patchComponent(`${town}/Arrow`, 'MOD.Core.SpriteGUIRendererComponent', { AnimClipPlayType: 1 });
}

// No controls inside the moving map can intercept drag input. The fixed surface
// receives mouse and touch from the entire visible rect, not the scaled terrain.
const INPUT = `${VIEW}/Input`;
b.sprite(INPUT, { anchor: 'stretch', alpha: 0, raycast: true });
b.addComponent(INPUT, 'MOD.Core.UITouchReceiveComponent');

b.text('Overlay/Window/MapHint', '高雄 38 區｜滾輪縮放・拖曳移動', { size: 22, color: '#E8DCC8', ...OUTLINE,
  anchor: 'middle-left', pos: [44, -452], rect_size: [size[0], 30] });

// --- side panel: own faction, strength list north to south, legend, status -------------------
const SIDE = 'Overlay/Window/Side';
b.sprite(SIDE, { anchor: 'middle-right', pos: [-44, -30], rect_size: [500, 810], color: { r: 0.12, g: 0.075, b: 0.04, a: 0.88 }, sprite_type: 1 });
b.text(`${SIDE}/FactionLabel`, '你的陣營', { size: 22, color: GOLD, ...OUTLINE, anchor: 'top-center', pos: [0, -24], rect_size: [460, 30] });
b.text(`${SIDE}/Faction`, '讀取中…', { size: 34, color: GOLD, bold: true, ...OUTLINE, anchor: 'top-center', pos: [0, -58], rect_size: [460, 44] });
b.sprite(`${SIDE}/Divider`, { anchor: 'top-center', pos: [0, -118], rect_size: [440, 2], color: { r: 0.93, g: 0.78, b: 0.56, a: 0.5 }, sprite_type: 1 });
b.text(`${SIDE}/Header`, '城鎮兵力（由北到南）', { size: 22, color: GOLD, ...OUTLINE, anchor: 'top-center', pos: [0, -134], rect_size: [460, 30] });
b.empty(`${SIDE}/Rows`, { anchor: 'top-center', pos: [0, -176], rect_size: [460, 4 * 92] });
TOWNS.forEach((id, n) => {
  const row = `${SIDE}/Rows/${id}`;
  b.sprite(row, { anchor: 'top-center', pos: [0, -n * 92], rect_size: [460, 84], color: { r: 0, g: 0, b: 0, a: 0.3 }, sprite_type: 1 });
  b.text(`${row}/Name`, NAMES[id], { size: 26, color: '#FFFFFF', bold: true, ...OUTLINE, alignment: 3, anchor: 'middle-left', pos: [16, 14], rect_size: [100, 34] });
  b.text(`${row}/Here`, '你在這裡', { size: 20, color: '#FACA33', bold: true, ...OUTLINE, alignment: 3, anchor: 'middle-left', pos: [16, -20], rect_size: [110, 26], enable: false });
  b.text(`${row}/Owner`, '讀取中', { size: 22, color: '#DAD1C2', ...OUTLINE, alignment: 3, anchor: 'middle-left', pos: [124, 14], rect_size: [180, 30] });
  b.text(`${row}/Value`, '—', { size: 24, color: '#FFFFFF', bold: true, ...OUTLINE, alignment: 5, anchor: 'middle-right', pos: [-16, 14], rect_size: [120, 30] });
  b.sprite(`${row}/Bar`, { anchor: 'middle-right', pos: [-16, -20], rect_size: [280, 16], color: { r: 0.05, g: 0.035, b: 0.02, a: 0.85 }, sprite_type: 1 });
  b.sprite(`${row}/Bar/Fill`, { anchor: 'middle-left', pos: [0, 0], rect_size: [280, 16], pivot: [0, 0.5], image_ruid: GAUGE, color: NEUTRAL, sprite_type: 1, enable: false });
});
b.empty(`${SIDE}/Legend`, { anchor: 'top-center', pos: [0, -560], rect_size: [460, 40] });
b.sprite(`${SIDE}/Legend/A`, { anchor: 'middle-left', pos: [20, 0], rect_size: [28, 28], color: { r: 0.84, g: 0.29, b: 0.24, a: 1 }, sprite_type: 1 });
b.text(`${SIDE}/Legend/A/Label`, 'A 方', { size: 22, color: '#FFFFFF', ...OUTLINE, alignment: 3, anchor: 'middle-left', pos: [36, 0], rect_size: [90, 30] });
b.sprite(`${SIDE}/Legend/B`, { anchor: 'middle-left', pos: [170, 0], rect_size: [28, 28], color: { r: 0.27, g: 0.5, b: 0.88, a: 1 }, sprite_type: 1 });
b.text(`${SIDE}/Legend/B/Label`, 'B 方', { size: 22, color: '#FFFFFF', ...OUTLINE, alignment: 3, anchor: 'middle-left', pos: [36, 0], rect_size: [90, 30] });
b.sprite(`${SIDE}/Legend/Link`, { anchor: 'middle-left', pos: [314, 0], rect_size: [40, 6], color: { r: 0.79, g: 0.64, b: 0.44, a: 1 }, sprite_type: 1 });
b.text(`${SIDE}/Legend/Link/Label`, '相鄰', { size: 22, color: '#FFFFFF', ...OUTLINE, alignment: 3, anchor: 'middle-left', pos: [48, 0], rect_size: [90, 30] });
b.text(`${SIDE}/Note`, '連線：以傳送門直接相連的相鄰城鎮\n主城永不易主，兵力恆為 100', { size: 20, color: '#E8DCC8', ...OUTLINE, anchor: 'top-center', pos: [0, -612], rect_size: [460, 64] });
b.text(`${SIDE}/Status`, '正在讀取戰況…', { size: 20, color: GOLD, ...OUTLINE, anchor: 'bottom-center', pos: [0, 56], rect_size: [460, 30] });
b.text(`${SIDE}/Hint`, '按 M 鍵或右上角按鈕關閉', { size: 20, color: '#BCBBBB', ...OUTLINE, anchor: 'bottom-center', pos: [0, 20], rect_size: [460, 28] });

// The NPC's target selection (#124): a pick button and a veil on each row, and the confirmation window above the map.
addSelectUi(b);

b.write(uiFile, { lint_verbose: true });
