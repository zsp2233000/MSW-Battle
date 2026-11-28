#!/usr/bin/env node
'use strict';

// Restyles the town HUD, its notice and the lobby close button of ui/FactionWarGroup.ui (#132) with the msw-ui-system UIBuilder, so the strip above a town looks
// like the siege panel and the war map: the Cardgame (Maple Duel) parts and the tactical-sandtable gold, instead of the builder's grey default skin.
// Only fields of existing entities change (the entities, their paths and their positions stay), so Maker reads it as an edit.
//
//   node assets/siege/build_town_hud_style.cjs
//
// FactionWarUI.mlua writes TownHUD/Strength and TownHUD/Notice (text only) and FactionWarUI binds LobbyClose by path, so nothing in the script changes.

const path = require('node:path');
const { UIBuilder } = require('../../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');

const uiFile = path.join(__dirname, '..', '..', 'ui', 'FactionWarGroup.ui');

// Cardgame parts (msw-ui-kit cardgame palette): Base_3, a sliced dark plate with a thin bronze frame, the look of the siege panel (dark fill inside a frame). A display strip must not
// look like a button, so the wooden planks of the Cardgame buttons (Base_6, tried first) are not used; Base_7 (flat brown), Base_8 (black with a metal frame), Base_9 (near black),
// Base_10 (teal), Base_11 (red), Base_1 (grey plank) and Base_2 (orange banner) were tried in Maker as well.
const HUD_STRIP = '16b391d441ad46afae46305de48b354c';
const NOTICE_STRIP = HUD_STRIP;
// The CardButton states of the lobby's close button, the same as the other buttons.
const CARD_BUTTON = { normal: '9505617fb63c447c8ff9c15c18d88064', highlighted: '398dfdb46d534ea2a2373e4f5d29ae2a', pressed: '1016088c7aca43c78cdd06c01645ab1b' };
const OUTLINE = { OutlineColor: { r: 0, g: 0, b: 0, a: 0.7 }, OutlineWidth: 0.2, FaceDilate: 0.2 };
const WHITE = { r: 1, g: 1, b: 1, a: 1 };
const GOLD = { r: 0xEE / 255, g: 0xC7 / 255, b: 0x8F / 255, a: 1 };
const SPRITE = 'MOD.Core.SpriteGUIRendererComponent';
const TEXT = 'MOD.Core.TextGUIRendererComponent';

const b = UIBuilder.load(uiFile);

// The strips: an explicit white tint renders the art as authored (the default skin colour would darken it into a ghost).
b.patchComponent('TownHUD', SPRITE, { ImageRUID: { DataId: HUD_STRIP }, Type: 1, Color: WHITE });
b.patchComponent('TownHUD/Notice', SPRITE, { ImageRUID: { DataId: NOTICE_STRIP }, Type: 1, Color: WHITE });
b.patchComponent('TownHUD/Strength', TEXT, { FontColor: WHITE, FontStyle: 1, ...OUTLINE });
b.patchComponent('TownHUD/Notice', TEXT, { FontColor: GOLD, FontStyle: 1, ...OUTLINE });

// The lobby's close button is a Cardgame button like the rest.
b.patchComponent('LobbyClose', SPRITE, { ImageRUID: { DataId: CARD_BUTTON.normal }, Type: 1, Color: WHITE });
b.patchComponent('LobbyClose', 'MOD.Core.ButtonComponent', {
  Transition: 2,
  ImageRUIDs: {
    HighlightedSprite: { DataId: CARD_BUTTON.highlighted },
    PressedSprite: { DataId: CARD_BUTTON.pressed },
    SelectedSprite: { DataId: CARD_BUTTON.normal },
    DisabledSprite: { DataId: CARD_BUTTON.pressed },
  },
});
b.patchComponent('LobbyClose', TEXT, { FontColor: WHITE, FontStyle: 1, ...OUTLINE });

b.write(uiFile, { lint_verbose: true });
