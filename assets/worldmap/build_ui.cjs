#!/usr/bin/env node
'use strict';

// Builds ui/WorldMapGroup.ui (the faction-war world map) with the msw-ui-system UIBuilder.
// Town nodes and place labels come from layout.json (written by paint_worldmap.cjs), the art from ruids.json.
//
//   node assets/worldmap/build_ui.cjs
//
// FactionWarMapUI.mlua finds every entity by path under /ui/WorldMapGroup, so keep the paths below in step with it.

const path = require('path');
const { UIBuilder } = require('../../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');

const ROOT = path.join(__dirname, '..', '..');
const layout = require('./layout.json');
const art = require('./ruids.json');

// Cardgame theme parts (msw-ui-kit cardgame palette), as used by the rest of the game.
const CARD_BUTTON = { normal: '9505617fb63c447c8ff9c15c18d88064', highlighted: '398dfdb46d534ea2a2373e4f5d29ae2a', pressed: '1016088c7aca43c78cdd06c01645ab1b' };
const X_BUTTON = { normal: 'e01ef74a1ecf444bbb013c4313a8d0a9', highlighted: 'f24a6333e4df404795e922ec2966e997', pressed: '5952570d481245a9a4fbe562f3c030c5' };
const PANEL_BG = 'd9b68fae16404c5c81228b6c45cf40a5';   // Panel_3 Background_1 (Sliced)
const CHIP_BG = 'ffdc4b11ef384e2cb4996562d867dd80';    // Base_9 (Sliced), white text
const GAUGE = 'f0911af597259044aa624a11332c0595';      // HP gauge slice (Sliced fill, width-driven)
const OUTLINE = { outline: true, outline_color: { r: 0, g: 0, b: 0, a: 0.7 }, outline_width: 0.2, face_dilate: 0.2 };
const GOLD = '#EEC78F';
const NEUTRAL = { r: 0.62, g: 0.6, b: 0.56, a: 1 };
const TOWNS = ['nanzih', 'zuoying', 'gushan', 'yancheng'];
const NAMES = { nanzih: '楠梓', zuoying: '左營', gushan: '鼓山', yancheng: '鹽埕' };

// Crest position per town: the district centre from layout.json, nudged where labels of neighbours would collide.
const NODE_SHIFT = { nanzih: [0, 28], zuoying: [6, 18], gushan: [3, 57], yancheng: [0, 0] };
// Yancheng is tiny and sits under Gushan, so its labels go to the right and its "you are here" chip to the left.
const SIDE_LABELS = { yancheng: true };

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

const b = new UIBuilder('WorldMapGroup', 9, true);
b.patchComponent('/ui/WorldMapGroup', 'MOD.Core.UIGroupComponent', { GroupType: 1, GroupOrder: 9, DefaultShow: true });

// Entry button, shown by the script only while the player stands in a town (below the system buttons in the top-right corner).
b.button('OpenButton', '大地圖 (M)', { anchor: 'top-right', pos: [-24, -150], rect_size: [210, 88], font_size: 26,
  image_ruid: CARD_BUTTON.normal, bg_color: '#FFFFFF', color: '#FFFFFF', enable: false });
swap(b, 'OpenButton', CARD_BUTTON);
b.patchComponent('OpenButton', 'MOD.Core.TextGUIRendererComponent', { OutlineColor: OUTLINE.outline_color, OutlineWidth: 0.2, FaceDilate: 0.2, FontStyle: 1 });

// Full-screen dimmer + window; the script toggles Overlay.
b.sprite('Overlay', { anchor: 'stretch', color: '#000000', alpha: 0.55, raycast: true, enable: false });
b.sprite('Overlay/Window', { anchor: 'middle-center', rect_size: [1240, 960], image_ruid: PANEL_BG, color: '#FFFFFF', sprite_type: 1, raycast: true });
b.text('Overlay/Window/Title', '國戰大地圖', { size: 32, color: '#FFFFFF', bold: true, ...OUTLINE, anchor: 'top-center', pos: [0, -30], rect_size: [600, 56] });
b.button('Overlay/Window/Close', '', { anchor: 'top-right', pos: [-16, -12], rect_size: [88, 96], image_ruid: X_BUTTON.normal, bg_color: '#FFFFFF', sprite_type: 0 });
swap(b, 'Overlay/Window/Close', X_BUTTON);

// --- the map: terrain, tinted districts, place labels, gate links, town nodes -----------------
const MAP = 'Overlay/Window/Map';
b.empty(MAP, { anchor: 'middle-left', pos: [44, -30], rect_size: [layout.size.w, layout.size.h] });
b.sprite(`${MAP}/Terrain`, { anchor: 'stretch', image_ruid: art.terrain, color: '#FFFFFF', sprite_type: 0 });
b.empty(`${MAP}/Districts`, { anchor: 'stretch' });
for (const id of TOWNS) {
  b.sprite(`${MAP}/Districts/${id}`, { anchor: 'stretch', image_ruid: art[`mask_${id}`], color: { ...NEUTRAL, a: 0.25 }, sprite_type: 0 });
}
b.empty(`${MAP}/Places`, { anchor: 'stretch' });
layout.places.forEach((place, n) => {
  const sea = place.name === '台灣海峽';
  const y = Math.max(-378, Math.min(378, place.y));
  b.text(`${MAP}/Places/Place${n + 1}`, place.name, { size: 20, color: sea ? { r: 0.91, g: 0.95, b: 0.97, a: 0.85 } : { r: 0.35, g: 0.27, b: 0.19, a: 0.8 },
    anchor: 'middle-center', pos: [place.x, y], rect_size: [120, 28] });
});
b.empty(`${MAP}/Links`, { anchor: 'stretch' });
for (let n = 1; n <= 3; n++) {
  b.sprite(`${MAP}/Links/Link${n}`, { anchor: 'middle-center', rect_size: [100, 6], color: { r: 0.29, g: 0.18, b: 0.09, a: 0.85 }, sprite_type: 1, enable: false });
}
b.empty(`${MAP}/Towns`, { anchor: 'stretch' });
for (const id of TOWNS) {
  const node = layout.towns[id];
  const [sx, sy] = NODE_SHIFT[id];
  const town = `${MAP}/Towns/${id}`;
  b.empty(town, { anchor: 'middle-center', pos: [node.x + sx, node.y + sy], rect_size: [64, 64] });
  b.sprite(`${town}/Crest`, { anchor: 'middle-center', rect_size: [60, 60], image_ruid: art.crest, color: NEUTRAL, sprite_type: 0 });
  if (SIDE_LABELS[id]) {
    b.text(`${town}/Name`, NAMES[id], { size: 26, color: '#FFFFFF', bold: true, ...OUTLINE, alignment: 3, anchor: 'middle-center', pos: [115, 14], rect_size: [150, 34] });
    b.text(`${town}/Strength`, '兵力 —', { size: 21, color: '#FFF2C8', ...OUTLINE, alignment: 3, anchor: 'middle-center', pos: [125, -16], rect_size: [170, 28] });
    b.text(`${town}/Capital`, '主城', { size: 21, color: '#FACA33', bold: true, ...OUTLINE, alignment: 3, anchor: 'middle-center', pos: [100, 44], rect_size: [120, 28] });
    b.sprite(`${town}/Here`, { anchor: 'middle-center', pos: [-115, 0], rect_size: [140, 40], image_ruid: CHIP_BG, color: '#FFFFFF', sprite_type: 1,
      text: '你在這裡', text_size: 21, text_color: '#FFFFFF', text_bold: true, enable: false });
  } else {
    b.text(`${town}/Name`, NAMES[id], { size: 26, color: '#FFFFFF', bold: true, ...OUTLINE, anchor: 'middle-center', pos: [0, -48], rect_size: [180, 34] });
    b.text(`${town}/Strength`, '兵力 —', { size: 21, color: '#FFF2C8', ...OUTLINE, anchor: 'middle-center', pos: [0, -78], rect_size: [200, 28] });
    b.text(`${town}/Capital`, '主城', { size: 21, color: '#FACA33', bold: true, ...OUTLINE, anchor: 'middle-center', pos: [0, 46], rect_size: [80, 28] });
    b.sprite(`${town}/Here`, { anchor: 'middle-center', pos: [115, 0], rect_size: [140, 40], image_ruid: CHIP_BG, color: '#FFFFFF', sprite_type: 1,
      text: '你在這裡', text_size: 21, text_color: '#FFFFFF', text_bold: true, enable: false });
  }
  b.patch(`${town}/Capital`, { enable: false });
}

// --- side panel: own faction, strength list north to south, legend, status -------------------
const SIDE = 'Overlay/Window/Side';
b.sprite(SIDE, { anchor: 'middle-right', pos: [-44, -30], rect_size: [500, 810], color: { r: 0.12, g: 0.075, b: 0.04, a: 0.62 }, sprite_type: 1 });
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
b.sprite(`${SIDE}/Legend/Red`, { anchor: 'middle-left', pos: [20, 0], rect_size: [28, 28], color: { r: 0.84, g: 0.29, b: 0.24, a: 1 }, sprite_type: 1 });
b.text(`${SIDE}/Legend/Red/Label`, '紅方', { size: 22, color: '#FFFFFF', ...OUTLINE, alignment: 3, anchor: 'middle-left', pos: [36, 0], rect_size: [90, 30] });
b.sprite(`${SIDE}/Legend/Blue`, { anchor: 'middle-left', pos: [170, 0], rect_size: [28, 28], color: { r: 0.27, g: 0.5, b: 0.88, a: 1 }, sprite_type: 1 });
b.text(`${SIDE}/Legend/Blue/Label`, '藍方', { size: 22, color: '#FFFFFF', ...OUTLINE, alignment: 3, anchor: 'middle-left', pos: [36, 0], rect_size: [90, 30] });
b.sprite(`${SIDE}/Legend/Link`, { anchor: 'middle-left', pos: [314, 0], rect_size: [40, 6], color: { r: 0.79, g: 0.64, b: 0.44, a: 1 }, sprite_type: 1 });
b.text(`${SIDE}/Legend/Link/Label`, '相鄰', { size: 22, color: '#FFFFFF', ...OUTLINE, alignment: 3, anchor: 'middle-left', pos: [48, 0], rect_size: [90, 30] });
b.text(`${SIDE}/Note`, '連線：以傳送門直接相連的相鄰城鎮\n主城永不易主，兵力恆為 100', { size: 20, color: '#E8DCC8', ...OUTLINE, anchor: 'top-center', pos: [0, -612], rect_size: [460, 64] });
b.text(`${SIDE}/Status`, '正在讀取戰況…', { size: 20, color: GOLD, ...OUTLINE, anchor: 'bottom-center', pos: [0, 56], rect_size: [460, 30] });
b.text(`${SIDE}/Hint`, '按 M 鍵或右上角按鈕關閉', { size: 20, color: '#BCBBBB', ...OUTLINE, anchor: 'bottom-center', pos: [0, 20], rect_size: [460, 28] });

b.write(path.join(ROOT, 'ui', 'WorldMapGroup.ui'), { lint_verbose: true });
