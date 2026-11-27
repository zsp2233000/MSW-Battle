#!/usr/bin/env node
'use strict';

// Rebuilds the team button and team preview (#118) in ui/FactionWarGroup.ui with the msw-ui-system UIBuilder, and drops the attack panel of #117, which the
// world map's target selection replaced in #124 (assets/worldmap/select_ui.cjs; assets/siege/remove_attack_panel_ui.cjs removes it from an existing file).
// Everything else in the group (faction choice, the siege panel of #123, town HUD, lobby buttons) is left as it is.
//
//   node assets/siege/build_siege_ui.cjs
//
// FactionWarUI.mlua and FactionWarTeam.mlua find every entity by path under /ui/FactionWarGroup, so keep the paths below in step with them.

const path = require('node:path');
const { UIBuilder } = require('../../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');

const ROOT = path.join(__dirname, '..', '..');
const uiFile = path.join(ROOT, 'ui', 'FactionWarGroup.ui');

// Cardgame theme parts (the same ones the world map, the lobby and the result window use).
const CARD_BUTTON = { normal: '9505617fb63c447c8ff9c15c18d88064', highlighted: '398dfdb46d534ea2a2373e4f5d29ae2a', pressed: '1016088c7aca43c78cdd06c01645ab1b' };
const X_BUTTON = { normal: 'e01ef74a1ecf444bbb013c4313a8d0a9', highlighted: 'f24a6333e4df404795e922ec2966e997', pressed: '5952570d481245a9a4fbe562f3c030c5' };
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

function xButton(b, name) {
  b.button(name, '', { anchor: 'top-right', pos: [-16, -12], rect_size: [88, 96], image_ruid: X_BUTTON.normal, bg_color: '#FFFFFF', sprite_type: 0 });
  swap(b, name, X_BUTTON);
}

function frame(b, name, size) {
  // The frame only draws its border, so the translucent brown behind it shows through; it never takes a click.
  b.sprite(name, { anchor: 'stretch', rect_size: size, image_ruid: BASE_FRAME, color: '#FFFFFF', sprite_type: 1 });
  b.patchComponent(name, 'MOD.Core.SpriteGUIRendererComponent', { FillCenter: false });
}

const b = UIBuilder.load(uiFile);
for (const gone of ['AttackPanel', 'TeamButton', 'TeamPreview']) if (b.find(gone)) b.remove(gone);

// --- team preview (#118): the "隊伍" button beside the world map button, and the read-only stance preview -----
cardButton(b, 'TeamButton', '隊伍', { anchor: 'top-right', pos: [-246, -150], rect_size: [150, 88], font_size: 26, enable: false });

b.sprite('TeamPreview', { anchor: 'stretch', rect_size: [1920, 1080], color: '#000000', alpha: 0.55, raycast: true, enable: false });
b.sprite('TeamPreview/Window', { anchor: 'middle-center', rect_size: [820, 640], color: BROWN_PANEL, sprite_type: 1, raycast: true });
frame(b, 'TeamPreview/Window/Frame', [820, 640]);
b.text('TeamPreview/Window/Title', '出戰隊伍', { size: 38, color: '#FFFFFF', bold: true, ...OUTLINE, anchor: 'top-center', pos: [0, -30], rect_size: [600, 56] });
xButton(b, 'TeamPreview/Window/Close');
b.sprite('TeamPreview/Window/Field', { anchor: 'top-center', pos: [0, -104], rect_size: [740, 380], color: BROWN_FIELD, sprite_type: 1 });
b.text('TeamPreview/Window/Field/Empty', '', { size: 28, color: '#FFFFFF', ...OUTLINE, anchor: 'middle-center', pos: [0, 0], rect_size: [680, 100], enable: false });
for (let n = 1; n <= 6; n++) {
  const unit = `TeamPreview/Window/Field/Unit${n}`;
  b.sprite(unit, { anchor: 'middle-center', rect_size: [72, 92], color: '#FFFFFF', alpha: 0, enable: false });
  b.sprite(`${unit}/Portrait`, { anchor: 'top-center', pos: [0, -2], rect_size: [56, 56], image_ruid: CARD_BUTTON.normal, color: '#FFFFFF', sprite_type: 0 });
  b.text(`${unit}/Lv`, 'Lv 1', { size: 22, color: '#FFFFFF', bold: true, ...OUTLINE, anchor: 'bottom-center', pos: [0, 2], rect_size: [72, 26] });
}
b.text('TeamPreview/Window/Hint', '', { size: 24, color: GOLD, ...OUTLINE, anchor: 'top-center', pos: [0, -504], rect_size: [740, 40] });
b.text('TeamPreview/Window/Note', '只能查看，不能在這裡更換或修改', { size: 20, color: '#BCBBBB', ...OUTLINE, anchor: 'bottom-center', pos: [0, 24], rect_size: [740, 30] });

b.write(uiFile, { lint_verbose: true });
