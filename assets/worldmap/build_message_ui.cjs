#!/usr/bin/env node
'use strict';

// Adds the message window (#127) to the existing WorldMapGroup UI file with the msw-ui-system UIBuilder, and nothing else: the map, the confirmation
// window and the row buttons keep their entities. The window is the last root child, so it is drawn above the map and the confirmation window.
//
//   node assets/worldmap/build_message_ui.cjs
//
// Run it again after a change of addMessageUi in select_ui.cjs: it removes the window and adds it again. Maker imports a new subtree one level per
// refresh (tests/README.md, #117): after the script, refresh, bump a sibling's display order through the builder, refresh again, and so on until
// /ui/WorldMapGroup/Message/Window/Ok exists (look at the tree in Play before running the probe).

const path = require('node:path');
const { UIBuilder } = require('../../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');
const { addMessageUi, messagePaths } = require('./select_ui.cjs');

const uiFile = path.join(__dirname, '..', '..', 'ui', 'WorldMapGroup.ui');
const b = UIBuilder.load(uiFile);
for (const entity of messagePaths()) if (b.find(entity)) b.remove(entity);
addMessageUi(b);
b.write(uiFile, { lint_verbose: true });
