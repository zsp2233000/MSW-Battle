#!/usr/bin/env node
'use strict';

// Removes the attack panel (#117) from ui/FactionWarGroup.ui with the msw-ui-system UIBuilder: the world map's target selection (#124,
// assets/worldmap/select_ui.cjs) replaced it. Nothing else in the group is rebuilt (Maker imports a rebuilt subtree one level per refresh).
//
//   node assets/siege/remove_attack_panel_ui.cjs

const path = require('node:path');
const { UIBuilder } = require('../../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');

const uiFile = path.join(__dirname, '..', '..', 'ui', 'FactionWarGroup.ui');
const b = UIBuilder.load(uiFile);
if (b.find('AttackPanel')) b.remove('AttackPanel');
b.write(uiFile, { lint_verbose: true });
