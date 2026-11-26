#!/usr/bin/env node
'use strict';

// Builds the 上一場戰果 / 上一場對戰結果 window (#122) as its own UIGroup with the msw-ui-system UIBuilder, in the Cardgame parts and the
// brown translucent "戰術沙盤" look of the attack panel (assets/siege/build_siege_ui.cjs) and the result window.
//
//   node assets/siege/build_absent_result_ui.cjs
//
// AbsentResultUI.mlua finds every entity by path under /ui/AbsentResultGroup, so keep the paths below in step with it.
// The group draws above every other group (order 10) so it covers the town HUD, the lobby screen and the world map.

const path = require('node:path');
const { UIBuilder } = require('../../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');

const ROOT = path.join(__dirname, '..', '..');
const uiFile = path.join(ROOT, 'ui', 'AbsentResultGroup.ui');

const CARD_BUTTON = { normal: '9505617fb63c447c8ff9c15c18d88064', highlighted: '398dfdb46d534ea2a2373e4f5d29ae2a', pressed: '1016088c7aca43c78cdd06c01645ab1b' };
const BASE_FRAME = 'ac319875b43f40ea86a069c468a1a26e'; // Base_4 panel frame (hollow, 43 px slices)
const OUTLINE = { outline: true, outline_color: { r: 0, g: 0, b: 0, a: 0.7 }, outline_width: 0.2, face_dilate: 0.2 };
const GOLD = '#EEC78F';
const BROWN_PANEL = { r: 0.12, g: 0.075, b: 0.04, a: 0.9 };
const BROWN_FIELD = { r: 0.16, g: 0.11, b: 0.07, a: 0.63 };

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

function cardButton(b, name, text, opts) {
  b.button(name, text, { font_size: 28, image_ruid: CARD_BUTTON.normal, bg_color: '#FFFFFF', color: '#FFFFFF', ...opts });
  swap(b, name, CARD_BUTTON);
  b.patchComponent(name, 'MOD.Core.TextGUIRendererComponent', { OutlineColor: OUTLINE.outline_color, OutlineWidth: 0.2, FaceDilate: 0.2, FontStyle: 1 });
}

function frame(b, name, size) {
  // The frame only draws its border, so the translucent brown behind it shows through; it never takes a click.
  b.sprite(name, { anchor: 'stretch', rect_size: size, image_ruid: BASE_FRAME, color: '#FFFFFF', sprite_type: 1 });
  b.patchComponent(name, 'MOD.Core.SpriteGUIRendererComponent', { FillCenter: false });
}

const b = new UIBuilder('AbsentResultGroup', 10, true);

// The dimmer takes every click while the window shows, so nothing behind it can be pressed. AbsentResultUI enables it when a record arrives.
b.sprite('Popup', { anchor: 'stretch', rect_size: [1920, 1080], color: '#000000', alpha: 0.55, raycast: true, enable: false });
b.sprite('Popup/Window', { anchor: 'middle-center', rect_size: [760, 560], color: BROWN_PANEL, sprite_type: 1, raycast: true });
frame(b, 'Popup/Window/Frame', [760, 560]);
b.text('Popup/Window/Title', '上一場戰果', { size: 38, color: '#FFFFFF', bold: true, ...OUTLINE, anchor: 'top-center', pos: [0, -30], rect_size: [600, 56] });
b.text('Popup/Window/Result', '勝利', { size: 68, color: '#FFD173', bold: true, ...OUTLINE, anchor: 'top-center', pos: [0, -104], rect_size: [600, 96] });

// The war block: the two strengths and the conclusion (a lobby result hides it and shortens the window).
b.sprite('Popup/Window/War', { anchor: 'top-center', pos: [0, -218], rect_size: [680, 196], color: BROWN_FIELD, sprite_type: 1 });
b.text('Popup/Window/War/Origin', '—', { size: 30, color: '#FFFFFF', bold: true, ...OUTLINE, anchor: 'top-center', pos: [0, -22], rect_size: [640, 40] });
b.text('Popup/Window/War/Target', '—', { size: 30, color: '#FFFFFF', bold: true, ...OUTLINE, anchor: 'top-center', pos: [0, -72], rect_size: [640, 40] });
b.text('Popup/Window/War/Conclusion', '', { size: 28, color: GOLD, ...OUTLINE, anchor: 'top-center', pos: [0, -130], rect_size: [640, 48] });

cardButton(b, 'Popup/Window/Confirm', '確定', { anchor: 'bottom-center', pos: [0, 36], rect_size: [240, 88], font_size: 32 });

b.write(uiFile, { lint_verbose: true });
