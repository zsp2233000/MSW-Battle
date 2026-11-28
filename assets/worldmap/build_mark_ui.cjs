#!/usr/bin/env node
'use strict';

// Adds the crest marks (#129) to the existing WorldMapGroup UI file with the msw-ui-system UIBuilder, and nothing else: the map, the town nodes, the confirmation
// window, the message window and the row buttons keep their entities. Each town node gets two children behind its crest: Mark (the halo of a town the player
// can pick) and Frame (the picked one), both hidden until FactionWarMapUI:RenderMarks shows them.
//
//   node assets/worldmap/build_mark_ui.cjs
//
// Run it again after a change of addMarkUi in select_ui.cjs: it removes the marks and adds them again. The children of each town node are numbered again from 0
// (Frame, Mark, Crest, Name, ...), so the crest keeps its entity but gets a higher display order. Maker imports a new child of an existing node on one refresh
// (tests/README.md, #117); if the Play shows /ui/WorldMapGroup/Overlay/Window/Map/Content/Towns/zuoying/Mark as missing, bump a sibling's display order through the
// builder and refresh again.

const path = require('node:path');
const { UIBuilder } = require('../../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');
const { addMarkUi, markPaths } = require('./select_ui.cjs');

const uiFile = path.join(__dirname, '..', '..', 'ui', 'WorldMapGroup.ui');
const b = UIBuilder.load(uiFile);
for (const entity of markPaths()) if (b.find(entity)) b.remove(entity);
addMarkUi(b);
b.write(uiFile, { lint_verbose: true });
