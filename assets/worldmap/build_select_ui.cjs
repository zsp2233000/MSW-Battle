#!/usr/bin/env node
'use strict';

// Adds the target-selection parts (#124) to the existing ui/WorldMapGroup.ui with the msw-ui-system UIBuilder, without rebuilding
// the map: Maker imports a rebuilt subtree one level per refresh (tests/README.md, #117), so the map, its side list and the town nodes keep their entities.
//
//   node assets/worldmap/build_select_ui.cjs
//
// Run it again after a change of select_ui.cjs: it removes what it added before and adds it again. A new subtree needs one Maker refresh per level
// (Confirm, then Confirm/Window, then its children; Rows/<town> then Pick and Dim), with a content change in between, before every entity exists.

const path = require('node:path');
const { UIBuilder } = require('../../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');
const { addSelectUi, selectPaths } = require('./select_ui.cjs');

const uiFile = path.join(__dirname, '..', '..', 'ui', 'WorldMapGroup.ui');
const b = UIBuilder.load(uiFile);
for (const entity of selectPaths()) if (b.find(entity)) b.remove(entity);
addSelectUi(b);
b.write(uiFile, { lint_verbose: true });
