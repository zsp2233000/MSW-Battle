#!/usr/bin/env node
'use strict';

// Adds the side panel line of #128 (Overlay/Window/Side/Notice) to the existing WorldMapGroup UI file with the msw-ui-system UIBuilder, and nothing
// else: the map, the rows, the confirmation window and the message window keep their entities. addNoticeUi puts the line in front of Confirm in the file,
// so the two windows stay drawn above it.
//
//   node assets/worldmap/build_notice_ui.cjs
//
// Run it again after a change of addNoticeUi in select_ui.cjs: it removes the line and adds it again. The line is one new leaf under an entity that
// exists, so one Maker refresh imports it (look for /ui/WorldMapGroup/Overlay/Window/Side/Notice in Play before running the probe).

const path = require('node:path');
const { UIBuilder } = require('../../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');
const { addNoticeUi, noticePaths } = require('./select_ui.cjs');

const uiFile = path.join(__dirname, '..', '..', 'ui', 'WorldMapGroup.ui');
const b = UIBuilder.load(uiFile);
for (const entity of noticePaths()) if (b.find(entity)) b.remove(entity);
addNoticeUi(b);
b.write(uiFile, { lint_verbose: true });
