const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');
const { UIBuilder } = require('../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');
const read = path => fs.readFileSync(`RootDesk/MyDesk/${path}.mlua`, 'utf8');
const method = (source, name) => source.match(new RegExp(`method \\w+ ${name}\\([^]*?(?=\\n    @|\\nend)`))?.[0] || '';

test('#52 queue starts only in the lobby, including authenticated server requests', () => {
  const queue = method(read('Matchmaking/MatchProbe'), 'QueueForUser');
  assert.match(queue, /player.CurrentMapName ~= "formationlobby" then/);
  assert.doesNotMatch(queue, /CurrentMapName ~= "formationsim"/);
  const ui = UIBuilder.read('ui/MatchGroup.ui');
  assert.equal(ui.find('EditorMatch'), null);
  assert.match(method(read('Matchmaking/MatchProbeInput'), 'Click'), /CurrentMapName/);
});

test('#52 every formation mutation and travel is guarded by the authoritative match lock', () => {
  const source = read('Formations/FormationService');
  for (const name of ['RequestSelectSlot', 'SaveForUser', 'ActivateForUser', 'RequestTravel']) {
    assert.match(method(source, name), /_MatchProbe:IsFormationLocked\(/, name);
  }
  const cancel = method(read('Matchmaking/MatchProbe'), 'CancelForUser');
  assert.ok(cancel.indexOf('if not cancelled then') < cancel.indexOf('_FormationHandoff:Close'),
    'failed native cancellation must not persist a terminal ticket or release editing');
});

test('#52 lobby navigation and edits share the confirmed idle gate', () => {
  const lobby = read('Formations/FormationLobby');
  for (const name of ['Travel', 'SelectLobbySlot', 'Observe']) {
    assert.match(method(lobby, name), /AllowsFormationActions\(/, name);
  }
  assert.match(method(read('Formations/FormationEditSession'), 'Writable'), /AllowsFormationActions\(/);
  const publish = method(read('Matchmaking/MatchProbe'), 'PublishState');
  assert.doesNotMatch(publish, /string.sub\(state, 1, 7\) ~= "RESULT_"/,
    'a return failure must remain visible over repeated result observations');
});
