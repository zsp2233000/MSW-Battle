#!/usr/bin/env node
'use strict';

// Delta build: node assets/worldmap/build_frontline_ui.cjs. Retains the IDs of the rest of WorldMapGroup.
// build_ui.cjs calls the same helpers for a full build.
const path = require('node:path');
const { UIBuilder } = require('../../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');
const layout = require('./layout.json');
const MAP = 'Overlay/Window/Map/Content';
const SIDE = 'Overlay/Window/Side';
const LEGEND_LABEL = '拔河條';
const NOTE = '傳送門相連｜兩色長度按兵力比例\n同立場為單色・主城兵力固定 100';
const HEIGHT = 8;
const NEUTRAL = '#9E998F';
const LEGEND_WIDTH = 48;
const LEGEND_LABEL_POS = [LEGEND_WIDTH + 8, 0];

function addSegments(b, parent, width) {
  for (const [name, anchor, pivot] of [['First', 'middle-left', 0], ['Second', 'middle-right', 1]]) {
    b.sprite(`${parent}/${name}`, { anchor, pivot: [pivot, 0.5], rect_size: [width / 2, HEIGHT], color: NEUTRAL, sprite_type: 1 });
  }
  // A full build is already in order. On delta import, Maker also reads file order, so display_order alone
  // cannot put the appended segments back under the crests and the legend label.
  const parentIndex = b.entities.indexOf(b.find(parent));
  const segments = ['First', 'Second'].map(name => b.find(`${parent}/${name}`));
  if (segments.every((entity, index) => b.entities[parentIndex + index + 1] === entity)) return;
  for (const entity of segments) b.entities.splice(b.entities.indexOf(entity), 1);
  b.entities.splice(parentIndex + 1, 0, ...segments);
}

function addFrontlines(b) {
  b.empty(`${MAP}/Links`, { anchor: 'stretch' });
  for (let n = 1; n <= 3; n++) {
    const bar = `${MAP}/Links/Link${n}`;
    b.empty(bar, { rect_size: [100, HEIGHT], enable: false });
    addSegments(b, bar, 100);
  }
}

function addFrontlineLegend(b) {
  const example = `${SIDE}/Legend/Link`;
  b.empty(example, { anchor: 'middle-left', pos: [300, 0], rect_size: [LEGEND_WIDTH, HEIGHT] });
  addSegments(b, example, LEGEND_WIDTH);
}

if (require.main === module) {
  const file = path.join(__dirname, '..', '..', 'ui', 'WorldMapGroup.ui');
  const b = UIBuilder.load(file);
  addFrontlines(b);
  addFrontlineLegend(b);
  const text = 'MOD.Core.TextGUIRendererComponent';
  b.patchComponent(`${SIDE}/Legend/Link/Label`, text, { Text: LEGEND_LABEL });
  b.patch(`${SIDE}/Legend/Link/Label`, { pos: LEGEND_LABEL_POS });
  b.patchComponent(`${SIDE}/Note`, text, { Text: NOTE });
  for (const id of Object.keys(layout.towns)) {
    const town = `${MAP}/Towns/${id}`;
    if (b.find(`${town}/Strength`)) b.remove(`${town}/Strength`);
    b.patch(`${town}/Capital`, { display_order: 4 });
    b.patch(`${town}/Arrow`, { display_order: 5 });
  }
  b.write(file, { lint_verbose: true });
}

module.exports = { addFrontlines, addFrontlineLegend, LEGEND_LABEL, LEGEND_LABEL_POS, NOTE };
