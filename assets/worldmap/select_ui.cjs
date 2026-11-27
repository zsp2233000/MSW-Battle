'use strict';

// The target-selection parts of ui/WorldMapGroup.ui (#124), added to a UIBuilder that already holds the map window (assets/worldmap/build_ui.cjs):
//   - Overlay/Window/Side/Rows/<town>/Pick  a Cardgame button over the row; shown only for a town the server listed as a target
//   - Overlay/Window/Side/Rows/<town>/Dim   a dark veil over the row of a town that cannot be picked in selection mode
//   - Confirm                               the "進攻 <town>？" window (dimmer, frame, title, both strengths, capital note, status, 是 / 否)
//   - Message                               (#127) the message window of an answer that opens no map: dimmer, frame, one text, one 確定 button
//   - Overlay/Window/Side/Notice            (#128) one line in the side panel: a target or the whole list is gone ("<town> 已不能進攻", "這座城已不屬於你的陣營")
//   - Overlay/Window/Map/Content/Towns/<town>/Mark and /Frame   (#129) the halo behind a crest the player can pick, and the brighter frame behind the picked one
// FactionWarMapUI.mlua finds every entity by path under /ui/WorldMapGroup, so keep the paths below in step with it.
// The confirmation window is a root sibling after Overlay, so it is drawn above the map, and the message window after it, above everything
// (Maker takes render order from the order in the file; the message window needs no map to be open).

const TOWNS = ['nanzih', 'zuoying', 'gushan', 'yancheng'];
const CARD_BUTTON = { normal: '9505617fb63c447c8ff9c15c18d88064', highlighted: '398dfdb46d534ea2a2373e4f5d29ae2a', pressed: '1016088c7aca43c78cdd06c01645ab1b' };
const BASE_FRAME = 'ac319875b43f40ea86a069c468a1a26e'; // Base_4 panel frame (hollow, 43 px slices)
const OUTLINE = { outline: true, outline_color: { r: 0, g: 0, b: 0, a: 0.7 }, outline_width: 0.2, face_dilate: 0.2 };
const GOLD = '#EEC78F';
const BROWN_PANEL = { r: 0.12, g: 0.075, b: 0.04, a: 0.95 };
// The size of a row of the town list (#132: the list is narrower since it floats on the right of the map); the pick button and the veil cover the whole row.
const { SIDE_ROW: ROW, geo } = require('./fullscreen_ui.cjs');
const MAP = 'Overlay/Window/Map/Content';
const art = require('./ruids.json');
// Both marks are the crest sprite drawn larger behind the crest, so each shows as a rim around it: gold for a town that can be picked, bright cyan for the picked one.
const MARK = { size: 76, color: { r: 1, g: 0.82, b: 0.25, a: 1 } };
const FRAME = { size: 94, color: { r: 0.4, g: 0.95, b: 1, a: 1 } };

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
  b.button(name, text, { font_size: 30, image_ruid: CARD_BUTTON.normal, bg_color: '#FFFFFF', color: '#FFFFFF', ...opts });
  swap(b, name, CARD_BUTTON);
  b.patchComponent(name, 'MOD.Core.TextGUIRendererComponent', { OutlineColor: OUTLINE.outline_color, OutlineWidth: 0.2, FaceDilate: 0.2, FontStyle: 1 });
}

// The paths the message window adds, so a rebuild of it alone (build_message_ui.cjs) can remove them first.
function messagePaths() {
  return ['Message'];
}

// The paths the side panel line adds, so a rebuild of it alone (build_notice_ui.cjs) can remove them first.
function noticePaths() {
  return ['Overlay/Window/Side/Notice'];
}

// The paths the crest marks add, so a rebuild of them alone (build_mark_ui.cjs) can remove them first.
function markPaths() {
  return TOWNS.flatMap(id => [`${MAP}/Towns/${id}/Mark`, `${MAP}/Towns/${id}/Frame`]);
}

// The paths this adds, so a rebuild can remove them first.
function selectPaths() {
  return ['Confirm', ...messagePaths(), ...noticePaths(), ...markPaths(), ...TOWNS.flatMap(id => [`Overlay/Window/Side/Rows/${id}/Pick`, `Overlay/Window/Side/Rows/${id}/Dim`])];
}

// The message window (#127): shown for ENGAGED, NOT_OWNED, UNAVAILABLE and NO_TARGETS instead of the map. Like the confirmation window its dimmer takes
// every click and has no handler, but it has one button only (確定). It is the last root child, so it is drawn above the map and the confirmation window.
function addMessageUi(b) {
  b.sprite('Message', { anchor: 'stretch', rect_size: [1920, 1080], color: '#000000', alpha: 0.6, raycast: true, enable: false });
  b.sprite('Message/Window', { anchor: 'middle-center', rect_size: [760, 380], color: BROWN_PANEL, sprite_type: 1, raycast: true });
  b.sprite('Message/Window/Frame', { anchor: 'stretch', rect_size: [760, 380], image_ruid: BASE_FRAME, color: '#FFFFFF', sprite_type: 1 });
  b.patchComponent('Message/Window/Frame', 'MOD.Core.SpriteGUIRendererComponent', { FillCenter: false });
  b.text('Message/Window/Text', '', { size: 30, color: '#FFFFFF', ...OUTLINE, anchor: 'top-center', pos: [0, -48], rect_size: [660, 190] });
  cardButton(b, 'Message/Window/Ok', '確定', { anchor: 'bottom-center', pos: [0, 32], rect_size: [240, 88], font_size: 32 });
}

// The side panel line (#128), under the note and above the status line (the side panel is 800 high since #132; the note ends at -656, the status line starts
// 750 from the top). Text only: it takes no click. The builder appends a new entity to the file, and Maker takes render order from the order of the
// entities, so on a file that already has Confirm and Message the line is moved in front of them (same entity, nothing re-imported): the windows stay above it.
function addNoticeUi(b) {
  b.text('Overlay/Window/Side/Notice', '', { size: 22, color: '#FFD173', bold: true, ...OUTLINE, ...geo('Overlay/Window/Side/Notice'), enable: false });
  const at = path => b.entities.findIndex(entity => entity.path === `${b.root_path}/${path}`);
  const notice = at('Overlay/Window/Side/Notice');
  const confirm = at('Confirm');
  if (confirm >= 0 && confirm < notice) b.entities.splice(confirm, 0, b.entities.splice(notice, 1)[0]);
}

// The crest marks (#129): FactionWarMapUI:RenderMarks shows Mark on every town the server listed and Frame on the picked one. They are children of the town node,
// so they are scaled with it, and they must be drawn behind the crest: Frame, Mark, Crest, then the labels (Maker takes render order from the order in the file and from
// displayOrder, so the two new entities are moved in front of the crest and the children of the town are numbered again from 0).
function addMarkUi(b) {
  for (const id of TOWNS) {
    const town = `${MAP}/Towns/${id}`;
    b.sprite(`${town}/Frame`, { rect_size: [FRAME.size, FRAME.size], image_ruid: art.crest, color: FRAME.color, sprite_type: 0, enable: false });
    b.sprite(`${town}/Mark`, { rect_size: [MARK.size, MARK.size], image_ruid: art.crest, color: MARK.color, sprite_type: 0, enable: false });
    const prefix = `${b.root_path}/${town}/`;
    const entityPath = entity => entity.jsonString.path;
    const isChild = entity => entityPath(entity).startsWith(prefix) && !entityPath(entity).slice(prefix.length).includes('/');
    const first = b.entities.findIndex(entity => entityPath(entity) === `${b.root_path}/${town}`) + 1;
    const children = b.entities.filter(isChild);
    const behind = ['Frame', 'Mark'].map(name => children.find(entity => entityPath(entity) === prefix + name));
    const ordered = [...behind, ...children.filter(entity => !behind.includes(entity))];
    const rest = b.entities.filter(entity => !children.includes(entity));
    rest.splice(first, 0, ...ordered);
    b.entities.splice(0, b.entities.length, ...rest);
    ordered.forEach((entity, index) => { entity.jsonString.displayOrder = index; });
  }
}

function addSelectUi(b) {
  addNoticeUi(b);
  for (const id of TOWNS) {
    const row = `Overlay/Window/Side/Rows/${id}`;
    // A faint Cardgame button over the whole row, 88 px high for a touch target (the rows are 92 px apart; stretch entities need their real size as RectSize); the highlighted and pressed
    // sprites give the hover and press feedback. It sits last in the row so it receives the click.
    cardButton(b, `${row}/Pick`, '', { anchor: 'stretch', rect_size: [ROW[0], 88], bg_color: { r: 1, g: 1, b: 1, a: 0.2 }, enable: false });
    b.sprite(`${row}/Dim`, { anchor: 'stretch', rect_size: ROW, color: { r: 0, g: 0, b: 0, a: 0.55 }, sprite_type: 1, enable: false });
  }

  // The window that asks for the confirmation. The dimmer takes every click (nothing outside the window closes it) and has no handler.
  b.sprite('Confirm', { anchor: 'stretch', rect_size: [1920, 1080], color: '#000000', alpha: 0.6, raycast: true, enable: false });
  b.sprite('Confirm/Window', { anchor: 'middle-center', rect_size: [760, 500], color: BROWN_PANEL, sprite_type: 1, raycast: true });
  b.sprite('Confirm/Window/Frame', { anchor: 'stretch', rect_size: [760, 500], image_ruid: BASE_FRAME, color: '#FFFFFF', sprite_type: 1 });
  b.patchComponent('Confirm/Window/Frame', 'MOD.Core.SpriteGUIRendererComponent', { FillCenter: false });
  b.text('Confirm/Window/Title', '進攻？', { size: 40, color: '#FFFFFF', bold: true, ...OUTLINE, anchor: 'top-center', pos: [0, -36], rect_size: [680, 56] });
  b.text('Confirm/Window/Origin', '出發城', { size: 28, color: '#FFFFFF', ...OUTLINE, anchor: 'top-center', pos: [0, -124], rect_size: [680, 40] });
  b.text('Confirm/Window/Target', '目標城', { size: 28, color: '#FFFFFF', ...OUTLINE, anchor: 'top-center', pos: [0, -176], rect_size: [680, 40] });
  b.text('Confirm/Window/Note', '', { size: 26, color: '#FFD173', bold: true, ...OUTLINE, anchor: 'top-center', pos: [0, -240], rect_size: [680, 40] });
  b.text('Confirm/Window/Status', '', { size: 24, color: GOLD, ...OUTLINE, anchor: 'bottom-center', pos: [0, 140], rect_size: [680, 40] });
  cardButton(b, 'Confirm/Window/Yes', '是', { anchor: 'bottom-center', pos: [-150, 32], rect_size: [240, 88], font_size: 32 });
  cardButton(b, 'Confirm/Window/No', '否', { anchor: 'bottom-center', pos: [150, 32], rect_size: [240, 88], font_size: 32 });
  addMarkUi(b);
  addMessageUi(b);
}

module.exports = { addSelectUi, addMessageUi, addNoticeUi, addMarkUi, selectPaths, messagePaths, noticePaths, markPaths };
