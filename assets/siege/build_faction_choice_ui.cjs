#!/usr/bin/env node
'use strict';

// Rebuilds the faction choice screen (#126, ADR 0018) in ui/FactionWarGroup.ui with the msw-ui-system UIBuilder: a Cardgame window with two
// colourless Cardgame buttons, "A 方" and "B 方". They are the same button; only the text tells them apart, because the player has no "own side"
// yet and a red / blue button would suggest one.
// Everything else in the group (siege panel, team preview, town HUD, lobby buttons) is left as it is.
//
//   node assets/siege/build_faction_choice_ui.cjs
//
// FactionWarUI.mlua finds every entity by path under /ui/FactionWarGroup/FactionChoice, so keep the paths below in step with it. The creators
// upsert in place, so the entity ids of the screen do not change.

const path = require('node:path');
const { UIBuilder } = require('../../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');

const ROOT = path.join(__dirname, '..', '..');
const uiFile = path.join(ROOT, 'ui', 'FactionWarGroup.ui');

// Cardgame theme parts (the same ones the world map and the result window use).
const CARD_BUTTON = { normal: '9505617fb63c447c8ff9c15c18d88064', highlighted: '398dfdb46d534ea2a2373e4f5d29ae2a', pressed: '1016088c7aca43c78cdd06c01645ab1b' };
const BASE_FRAME = 'ac319875b43f40ea86a069c468a1a26e'; // Base_4 panel frame (hollow, 43 px slices)
const OUTLINE = { outline: true, outline_color: { r: 0, g: 0, b: 0, a: 0.7 }, outline_width: 0.2, face_dilate: 0.2 };
const GOLD = '#EEC78F';
const BROWN_PANEL = { r: 0.12, g: 0.075, b: 0.04, a: 0.9 };

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

const b = UIBuilder.load(uiFile);
const WINDOW = [616, 364];

// A stretched entity needs its real size as RectSize: the engine insets the rect by (parent - RectSize) / 2 otherwise.
b.sprite('FactionChoice', { anchor: 'stretch', rect_size: [1920, 1080], color: '#000000', alpha: 0.55, raycast: true, enable: false });
b.sprite('FactionChoice/Window', { anchor: 'middle-center', rect_size: WINDOW, color: BROWN_PANEL, sprite_type: 1, raycast: true });
b.text('FactionChoice/Window/Title', '加入國戰', { size: 38, color: '#FFFFFF', bold: true, ...OUTLINE, anchor: 'middle-center', pos: [0, 119], rect_size: [540, 54] });
b.text('FactionChoice/Window/Status', '正在讀取國戰資料…', { size: 25, color: GOLD, ...OUTLINE, anchor: 'middle-center', pos: [0, 61], rect_size: [552, 48] });
// Both buttons start hidden: FactionWarUI shows them only when the server answers CHOOSE.
cardButton(b, 'FactionChoice/Window/A', 'A 方', { anchor: 'middle-center', pos: [-145, -21], rect_size: [264, 88], font_size: 30, enable: false });
cardButton(b, 'FactionChoice/Window/B', 'B 方', { anchor: 'middle-center', pos: [145, -21], rect_size: [264, 88], font_size: 30, enable: false });
cardButton(b, 'FactionChoice/Window/Close', '關閉', { anchor: 'middle-center', pos: [0, -122], rect_size: [184, 88], font_size: 25 });
// The frame only draws its border, so the translucent brown behind it shows through; it never takes a click. It is drawn beneath the content.
b.sprite('FactionChoice/Window/Frame', { anchor: 'stretch', rect_size: WINDOW, image_ruid: BASE_FRAME, color: '#FFFFFF', sprite_type: 1 });
b.patchComponent('FactionChoice/Window/Frame', 'MOD.Core.SpriteGUIRendererComponent', { FillCenter: false });
const ORDER = ['Frame', 'Title', 'Status', 'A', 'B', 'Close'];
ORDER.forEach((name, order) => b.patch(`FactionChoice/Window/${name}`, { display_order: order }));

// Sibling order is render order, and Maker takes it from the order of the entities in the file, not from the displayOrder numbers (see
// build_siege_panel_ui.cjs). The window's children are moved to just after the window, in the order above; no other entity is touched.
const pathOf = entity => entity.jsonString.path;
const windowPath = '/ui/FactionWarGroup/FactionChoice/Window';
const children = ORDER.map(name => b.entities.find(entity => pathOf(entity) === `${windowPath}/${name}`));
const rest = b.entities.filter(entity => !children.includes(entity));
const at = rest.findIndex(entity => pathOf(entity) === windowPath) + 1;
b.entities = rest.slice(0, at).concat(children, rest.slice(at));

b.write(uiFile, { lint_verbose: true });
