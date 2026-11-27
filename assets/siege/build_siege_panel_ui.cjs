#!/usr/bin/env node
'use strict';

// Adds the siege panel (#123) to ui/FactionWarGroup.ui with the msw-ui-system UIBuilder and removes the queue bar it replaces.
// Nothing else in the group is rebuilt: Maker imports a rebuilt subtree one level per refresh (tests/README.md, #117), so the
// team preview and the rest keep their entities.
//
//   node assets/siege/build_siege_panel_ui.cjs [--strength-bars-only]
//
// FactionWarUI.mlua finds every entity by path under /ui/FactionWarGroup and writes SiegePanel/Origin, Target, Status and the text of
// SiegePanel/Cancel; the versus mark never changes.

const path = require('node:path');
const { UIBuilder } = require('../../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');

const ROOT = path.join(__dirname, '..', '..');
const uiFile = path.join(ROOT, 'ui', 'FactionWarGroup.ui');

// Cardgame theme parts and the "tactical sandtable" colours shared with the attack panel (build_siege_ui.cjs).
const CARD_BUTTON = { normal: '9505617fb63c447c8ff9c15c18d88064', highlighted: '398dfdb46d534ea2a2373e4f5d29ae2a', pressed: '1016088c7aca43c78cdd06c01645ab1b' };
const BASE_FRAME = 'ac319875b43f40ea86a069c468a1a26e'; // Base_4 panel frame (hollow, 43 px slices)
const OUTLINE = { outline: true, outline_color: { r: 0, g: 0, b: 0, a: 0.7 }, outline_width: 0.2, face_dilate: 0.2 };
const GOLD = '#EEC78F';
const BROWN_PANEL = { r: 0.12, g: 0.075, b: 0.04, a: 0.9 };

const CARD = [820, 170];
const GAUGE = 'f0911af597259044aa624a11332c0595'; // same sliced fill as the world map
const NEUTRAL = { r: 0.62, g: 0.6, b: 0.56, a: 1 };

function addStrengthBars(b) {
  for (const [side, x, labelX] of [['Origin', -155, -225], ['Target', 155, 225]]) {
    b.patch(`SiegePanel/${side}`, { pos: [labelX, -10] });
    const bar = `SiegePanel/${side}Bar`;
    b.sprite(bar, { anchor: 'top-center', pos: [x, -56], rect_size: [220, 10], color: '#211A16', sprite_type: 1 });
    b.sprite(`${bar}/Fill`, { anchor: 'middle-left', pivot: [0, 0.5], pos: [0, 0], rect_size: [220, 10],
      image_ruid: GAUGE, color: NEUTRAL, sprite_type: 1, enable: false });
  }
}

const b = UIBuilder.load(uiFile);
if (process.argv.includes('--strength-bars-only')) {
  addStrengthBars(b);
  b.write(uiFile, { lint_verbose: true });
  process.exit(0);
}
for (const gone of ['QueueBar', 'SiegePanel']) if (b.find(gone)) b.remove(gone);

// A card at the top centre, under the town HUD and its notice. The first line is "<departure town> <strength> <versus> <target town> <strength>",
// the second the status words with the one button on the right. The button is touch sized (88 px).
b.sprite('SiegePanel', { anchor: 'top-center', pos: [0, -160], rect_size: CARD, color: BROWN_PANEL, sprite_type: 1, raycast: true, enable: false });
// The frame only draws its border, so the translucent brown behind it shows through; it never takes a click.
b.sprite('SiegePanel/Frame', { anchor: 'stretch', rect_size: CARD, image_ruid: BASE_FRAME, color: '#FFFFFF', sprite_type: 1 });
b.patchComponent('SiegePanel/Frame', 'MOD.Core.SpriteGUIRendererComponent', { FillCenter: false });
b.text('SiegePanel/Origin', '—', { size: 30, color: '#FFFFFF', bold: true, ...OUTLINE, alignment: 5, anchor: 'top-center', pos: [-225, -18], rect_size: [360, 44] });
b.text('SiegePanel/Versus', 'VS', { size: 32, color: GOLD, bold: true, ...OUTLINE, alignment: 4, anchor: 'top-center', pos: [0, -18], rect_size: [80, 44] });
b.text('SiegePanel/Target', '—', { size: 30, color: '#FFFFFF', bold: true, ...OUTLINE, alignment: 3, anchor: 'top-center', pos: [225, -18], rect_size: [360, 44] });
b.text('SiegePanel/Status', '', { size: 26, color: GOLD, ...OUTLINE, alignment: 3, anchor: 'bottom-left', pos: [32, 16], rect_size: [520, 88] });
b.button('SiegePanel/Cancel', '取消配對', { anchor: 'bottom-right', pos: [-24, 16], rect_size: [210, 88], font_size: 26,
  image_ruid: CARD_BUTTON.normal, bg_color: '#FFFFFF', color: '#FFFFFF' });
b.patchComponent('SiegePanel/Cancel', 'MOD.Core.ButtonComponent', {
  Transition: 2,
  ImageRUIDs: {
    HighlightedSprite: { DataId: CARD_BUTTON.highlighted },
    PressedSprite: { DataId: CARD_BUTTON.pressed },
    SelectedSprite: { DataId: CARD_BUTTON.normal },
    DisabledSprite: { DataId: CARD_BUTTON.pressed },
  },
});
b.patchComponent('SiegePanel/Cancel', 'MOD.Core.TextGUIRendererComponent', { OutlineColor: OUTLINE.outline_color, OutlineWidth: 0.2, FaceDilate: 0.2, FontStyle: 1 });
addStrengthBars(b);

// Sibling order is render order, and Maker takes it from the order of the entities in the file (the displayOrder numbers alone did not
// change it: the card stayed on top of the dialogs). The card was appended last, so its subtree moves to just before the first dialog
// (attack panel, team preview) and takes the free displayOrder number right below theirs. No other entity is touched.
const rootPath = '/ui/FactionWarGroup';
const siblings = b.listEntities().filter(entity => entity.depth === 1).map(entity => entity.path.split('/').pop()).filter(name => name !== 'SiegePanel');
const taken = new Set(siblings.map(name => b.find(name).jsonString.displayOrder));
const dialogs = siblings.filter(name => name === 'TeamPreview');
let place = dialogs.length > 0 ? Math.min(...dialogs.map(name => b.find(name).jsonString.displayOrder)) - 1 : Math.max(...taken) + 1;
while (taken.has(place)) place -= 1;
b.patch('SiegePanel', { display_order: place });

const pathOf = entity => entity.jsonString.path;
const inCard = entity => pathOf(entity) === `${rootPath}/SiegePanel` || pathOf(entity).startsWith(`${rootPath}/SiegePanel/`);
const card = b.entities.filter(inCard);
const rest = b.entities.filter(entity => !inCard(entity));
const firstDialog = rest.findIndex(entity => dialogs.some(name => pathOf(entity) === `${rootPath}/${name}`));
b.entities = firstDialog < 0 ? rest.concat(card) : rest.slice(0, firstDialog).concat(card, rest.slice(firstDialog));

b.write(uiFile, { lint_verbose: true });
