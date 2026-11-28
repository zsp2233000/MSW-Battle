const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

// (#132) One colour for a runtime town name on every war screen and notice: ally blue, enemy red, the Cardgame cyan only while the stance is not known.
// The behaviour of each surface is in the rules suites; this test pins the single source and that no surface composes a plain name or its own colour any more.
const source = file => fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n');
const files = dir => fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => (entry.isDirectory() ? files(path.join(dir, entry.name)) : [path.join(dir, entry.name)]));
const mlua = files('RootDesk/MyDesk').filter(file => file.endsWith('.mlua')).map(file => ({ file: file.replace(/\\/g, '/'), text: source(file) }));
const hex = (r, g, b) => `#${[r, g, b].map(value => Math.round(value * 255).toString(16).padStart(2, '0')).join('').toUpperCase()}`;

test('the colour values of a name are the town colours of the map, and the highlight is the one the war screens have always had', () => {
  const doc = source('RootDesk/MyDesk/Formations/FactionWarTownDocument.mlua');
  const ui = source('RootDesk/MyDesk/Formations/FactionWarUI.mlua');
  const colour = name => ui.match(new RegExp(`property Color ${name} = Color\\(([\\d.]+), ([\\d.]+), ([\\d.]+), 1\\)`)).slice(1).map(Number);
  assert.equal(doc.match(/property string AllyNameHex = "(#[0-9A-F]{6})"/)[1], hex(...colour('AllyTownColor')), 'ally name = ally town colour');
  assert.equal(doc.match(/property string EnemyNameHex = "(#[0-9A-F]{6})"/)[1], hex(...colour('EnemyTownColor')), 'enemy name = enemy town colour');
  assert.equal(doc.match(/property string HighlightNameHex = "(#[0-9A-F]{6})"/)[1], ui.match(/property string TownNameHighlightHex = "(#[0-9A-F]{6})"/)[1], 'one highlight');
});

test('every surface that names a town goes through StanceName / StanceTownName, never a plain name or a colour of its own', () => {
  const owner = name => mlua.filter(entry => entry.text.includes(name)).map(entry => path.basename(entry.file));
  // The plain highlight is only the fallback inside FactionWarUI.StanceTownName.
  assert.deepEqual(owner('HighlightedTownName('), ['FactionWarUI.mlua', 'FactionWarUI.mlua'].slice(0, 1), 'HighlightedTownName is called only inside FactionWarUI');
  assert.match(source('RootDesk/MyDesk/Formations/FactionWarUI.mlua'), /method string StanceTownName[^]*return self:HighlightedTownName\(town\)[^]*return doc:StanceName\(/, 'the fallback is the highlight, the stance is StanceName');
  // The names a surface prints are rich text from the document; reading TownNames to compose text is limited to the places that carry data or build that rich text.
  const allowed = new Set(['FactionWarTownDocument.mlua', 'FactionWarAttack.mlua', 'FactionWarMap.mlua', 'FactionWarMapUI.mlua', 'FactionWarUI.mlua', 'MatchFlowInput.mlua']);
  for (const name of owner('TownNames[')) assert.ok(allowed.has(name), `${name} reads a plain town name`);
  const uiMap = source('RootDesk/MyDesk/Formations/FactionWarMapUI.mlua');
  assert.equal([...uiMap.matchAll(/TownNames\[/g)].length, 1, 'the map reads plain names only as data for the neutral board');
  const ui = source('RootDesk/MyDesk/Formations/FactionWarUI.mlua');
  assert.match(ui, /label\.TextGUIRendererComponent\.Text = _FactionWarTownDocument:StanceName\(town, "ally"\)/, 'the HUD names the player\'s own town in blue');
  assert.match(ui, /self:StanceTownName\(town, self\._T\.siegeFaction or "", type\(owner\) == "string" and owner or ""\)/, 'the siege card uses the faction and the board\'s owners');
  const landing = source('RootDesk/MyDesk/Formations/FactionWarLanding.mlua');
  assert.match(landing, /StanceName\(town, "enemy"\) \.\. "已失守，已撤回主城。"/, 'a fallen town is the enemy\'s');
  assert.match(landing, /"已回到" \.\. _FactionWarTownDocument:StanceName\(destination, "ally"\)/, 'the town returned to is the player\'s');
  assert.doesNotMatch(landing, /TownNames\[\w+\] \.\./, 'no notice concatenates a plain name');
  const input = source('RootDesk/MyDesk/Matchmaking/MatchFlowInput.mlua');
  assert.match(input, /StanceName\(origin, \(receipt ~= nil and receipt\.originLost == true\) and "enemy" or "ally"\)/, 'the departure town is blue until the receipt says it fell');
  assert.match(input, /StanceName\(destination, "ally"\)/, 'the destination is the player\'s own');
  assert.match(source('RootDesk/MyDesk/Matchmaking/MatchFlowState.mlua'), /"返回 " \.\. \(context\.originLabel or context\.originName\)/, 'the failed-entry return button uses the coloured label');
  const map = uiMap;
  for (const call of ['self:StanceTownName(town) .. " 已不能進攻"', 'self:StanceTownName(target) .. "，要改變目標', 'self:StanceTownName(target) .. "？"', '"出發城 " .. self:StanceTownName(self._T.origin)', '"目標城 " .. self:StanceTownName(target)']) {
    assert.ok(map.includes(call), `the map says ${call}`);
  }
  for (const file of ['Combat/BattleUIController.mlua', 'Matchmaking/AbsentResult.mlua']) {
    const text = source(`RootDesk/MyDesk/${file}`);
    assert.match(text, /StanceName\(town, stance\)/, `${file}: a strength row takes its stance`);
    assert.match(text, /ColoredConclusion\(/, `${file}: the captured town in the conclusion is coloured by the document`);
    assert.doesNotMatch(text, /string\.gsub\(conclusion/, `${file}: no colouring of its own`);
  }
  assert.match(source('RootDesk/MyDesk/Combat/BattleUIController.mlua'), /unchanged, "ally"\)[^]*unchanged, "enemy"\)/, 'the result page: origin ally, target enemy');
  assert.match(source('RootDesk/MyDesk/Matchmaking/AbsentResult.mlua'), /unchanged, "ally"\), self:StrengthLine\(war\.target[^]*unchanged, "enemy"\)/, 'the absent result: origin ally, target enemy');
});
