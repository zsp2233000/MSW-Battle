// ADR 0018 / #125: the factions are A and B. The retired colour ids appear in program code only inside the one converter, no property or node is
// named after a colour, and every screen and settlement text says "A 方" / "B 方".
// Run: node --test tests/faction_id_contract.test.cjs
const assert = require('node:assert/strict');
const test = require('node:test');
const { readdirSync, readFileSync, statSync } = require('node:fs');
const { join, relative } = require('node:path');
const { UIBuilder } = require('../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');

const root = join(__dirname, '..');
const read = file => readFileSync(join(root, file), 'utf8').replace(/\r\n/g, '\n');
function walk(dir, accept, found = []) {
  for (const name of readdirSync(join(root, dir))) {
    const path = `${dir}/${name}`;
    if (statSync(join(root, path)).isDirectory()) walk(path, accept, found);
    else if (accept(path)) found.push(path);
  }
  return found;
}
// The project's own scripts. The UI resource packs are third-party and say nothing about factions.
const ownScripts = () => walk('RootDesk/MyDesk', path => path.endsWith('.mlua') && !/\/(UIResource|UIComponent)/.test(path));
const RETIRED_ID = /["'](RED|BLUE)["']/;
const CONVERTER = /    method any NormalizeFaction\(any raw\)\n[\s\S]*?\n    end\n/;

test('the retired colour ids appear in program code only inside the one converter', () => {
  const hits = [];
  for (const file of ownScripts()) {
    let text = read(file);
    if (file.endsWith('/FactionWarTownDocument.mlua')) {
      const converter = text.match(CONVERTER);
      assert.ok(converter, 'FactionWarTownDocument declares NormalizeFaction');
      assert.deepEqual(converter[0].match(/["'](RED|BLUE)["']/g), ['"RED"', '"BLUE"'], 'the converter knows exactly the two retired ids');
      text = text.replace(CONVERTER, '');
    }
    text.split('\n').forEach((line, index) => { if (RETIRED_ID.test(line)) hits.push(`${file}:${index + 1}: ${line.trim()}`); });
  }
  assert.deepEqual(hits, [], 'no retired colour id literal outside the converter');
});

test('tests and probes feed the retired ids only where a legacy value is the point', () => {
  const allowed = new Set([
    'tests/faction_id_contract.test.cjs', // this guard names the retired ids to forbid them
    'tests/faction_id_legacy_rules.lua', // every stored-value read point is fed the retired ids
    'tests/faction_war_integration_journey_e2e_runtime_probe.lua', // LEGACY mode seeds the retired ids into real Maker storage
  ]);
  const hits = walk('tests', path => /\.(lua|cjs)$/.test(path))
    .filter(file => !allowed.has(file) && RETIRED_ID.test(read(file)));
  assert.deepEqual(hits, [], 'seed data is A / B');
});

test('no property or node is named after a faction colour', () => {
  for (const file of ownScripts().filter(path => /\/(Formations|Matchmaking|Combat)\//.test(path))) {
    assert.doesNotMatch(read(file), /\b(Red|Blue)[A-Za-z]*\b/, `${file} names nothing after a colour`);
  }
  const map = read('RootDesk/MyDesk/Formations/FactionWarMapUI.mlua');
  assert.match(map, /property Color FactionAColor = /);
  assert.match(map, /property Color FactionBColor = /);
  const ui = read('RootDesk/MyDesk/Formations/FactionWarUI.mlua');
  assert.match(ui, /Bind\("FactionChoice\/Window\/A", function\(\) self:Request\("A"\) end\)/, 'the A button asks to join A');
  assert.match(ui, /Bind\("FactionChoice\/Window\/B", function\(\) self:Request\("B"\) end\)/, 'the B button asks to join B');
  for (const group of ['FactionWarGroup', 'WorldMapGroup']) {
    const names = UIBuilder.read(`ui/${group}.ui`).listEntities().map(entity => entity.path);
    assert.deepEqual(names.filter(path => /\/(Red|Blue)(\/|$)/.test(path)), [], `${group} has no node named after a colour`);
  }
});

test('the choice buttons and the legend are authored as A and B', () => {
  const war = UIBuilder.read('ui/FactionWarGroup.ui');
  for (const [node, text] of [['A', 'A 方'], ['B', 'B 方']]) {
    assert.ok(war.hasComponent(`FactionChoice/Window/${node}`, 'MOD.Core.ButtonComponent'), `${node} is a button`);
    assert.equal(war.getComponent(`FactionChoice/Window/${node}`, 'MOD.Core.TextGUIRendererComponent').Text, text);
  }
  const map = UIBuilder.read('ui/WorldMapGroup.ui');
  for (const [node, text] of [['A', 'A 方'], ['B', 'B 方']]) {
    assert.equal(map.getComponent(`Overlay/Window/Side/Legend/${node}/Label`, 'MOD.Core.TextGUIRendererComponent').Text, text, `legend ${node}`);
  }
  const build = read('assets/worldmap/build_ui.cjs');
  assert.match(build, /Legend\/A\/Label`, 'A 方'/);
  assert.match(build, /Legend\/B\/Label`, 'B 方'/);
});

test('every screen and settlement text names the factions A 方 / B 方, never by colour', () => {
  for (const file of ownScripts().filter(path => /\/(Formations|Matchmaking|Combat)\//.test(path))) {
    assert.doesNotMatch(read(file), /紅方|藍方|紅城|藍城/, `${file} has no colour-named faction text`);
  }
  for (const file of readdirSync(join(root, 'ui')).filter(name => name.endsWith('.ui'))) {
    const group = UIBuilder.read(`ui/${file}`);
    for (const entity of group.listEntities()) {
      for (const component of group.find(entity.path).jsonString['@components'] || []) {
        if (typeof component.Text === 'string') assert.doesNotMatch(component.Text, /紅方|藍方/, `${file} ${entity.path}`);
      }
    }
  }
  const document = read('RootDesk/MyDesk/Formations/FactionWarTownDocument.mlua');
  assert.match(document, /property table FactionNames = \{ A = "A 方", B = "B 方" \}/);
  assert.match(document, /property table CapitalByFaction = \{ A = "nanzih", B = "yancheng" \}/, 'A holds Nanzih, B holds Yancheng');
});

test('the legacy-value suite is wired to the production scripts', () => {
  const harness = read('tests/faction_id_legacy_local.cjs');
  for (const script of ['FactionWarTownDocument', 'FactionWar', 'AbsentResult']) assert.match(harness, new RegExp(`/${script}\\.mlua`), `${script} runs unmodified`);
  assert.match(read('tests/faction_id_legacy_rules.lua'), /legacy values at every read point PASS/);
  assert.match(relative(root, __filename).replace(/\\/g, '/'), /^tests\//);
});
