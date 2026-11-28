#!/usr/bin/env node
'use strict';

// Lays the existing WorldMapGroup UI file out near full screen (#132) with the msw-ui-system UIBuilder, and changes nothing else: the entities keep their ids, so Maker
// reads it as an edit and not as a rebuilt tree (a rebuilt subtree is imported one level per refresh, tests/README.md #117). The one new entity is the closing hint
// at the bottom right corner of the window (Overlay/Window/Hint, a leaf under a node that exists, so one refresh imports it); the old one in the town list and the
// backdrop under the window are removed.
//
//   node assets/worldmap/build_fullscreen_ui.cjs
//
// The rectangles live in assets/worldmap/fullscreen_ui.cjs, which build_ui.cjs uses too. Running this again on a laid-out file changes nothing.

const path = require('node:path');
const { UIBuilder } = require('../../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');
const { applyFullscreenLayout } = require('./fullscreen_ui.cjs');

const uiFile = path.join(__dirname, '..', '..', 'ui', 'WorldMapGroup.ui');
const b = UIBuilder.load(uiFile);
applyFullscreenLayout(b);
b.write(uiFile, { lint_verbose: true });
