const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const { UIBuilder } = require('../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs');

const read = file => fs.readFileSync(path.join(__dirname, '..', file), 'utf8');
const COMMANDS = 'RootDesk/MyDesk/GM/GMCommandService.mlua';
const RPC = 'RootDesk/MyDesk/GM/GMPanelService.mlua';
const PANEL = 'RootDesk/MyDesk/GM/GMPanel.mlua';
function body(source, method) {
  const pattern = 'method \\w+ ' + method + '\\([^)]*\\)([\\s\\S]*?)\\n    end\\b';
  const match = source.match(new RegExp(pattern));
  assert.ok(match, method + ' exists');
  return match[1].split(/\r?\n/).map(s => s.trim()).filter(s => s && !s.startsWith('--')).join('\n');
}

test('every GM command checks the server whitelist before dispatch or storage', () => {
  const source = read(COMMANDS);
  assert.match(source, /@ExecSpace\("ServerOnly"\)\s+method void Execute\(string requesterProfile, table command, any complete\)/);
  assert.ok(body(source, 'Execute').startsWith('if not self:IsGM(requesterProfile) then'));
  assert.match(body(source, 'IsGM'), /requesterProfile == "6Y9NGB"/);
  assert.doesNotMatch(source, /@Sync|@TargetUserSync|property.*(Whitelist|GMProfiles)/);
  assert.doesNotMatch(source, /_DataStorageService|:SetAsync\(|:UpdateAsync\(|:DeleteAndWait\(|:DeleteAsync\(/);
  assert.match(source, /_FormationStorage:Read\(/);
  assert.match(source, /_MonsterLevelStorage:Decode\(raw\)/);
});

test('the RPC derives requester identity from the sender and replies only to that sender', () => {
  const source = read(RPC);
  assert.match(source, /method void Request\(integer requestId, string kind, string profile, string expected, table payload\)/);
  assert.equal((source.match(/@ExecSpace\("Server"\)/g) || []).length, 1);
  const request = body(source, 'Request');
  assert.match(request, /GetUserEntityByUserId\(senderUserId\)/);
  assert.match(request, /local requesterProfile = player\.PlayerComponent\.ProfileCode/);
  assert.match(request, /action = payload\.action/);
  assert.match(request, /expectedExists = payload\.exists/);
  assert.match(request, /_GMCommandService:Execute\(requesterProfile,/);
  assert.match(request, /local replyUserId = senderUserId/);
  assert.match(request, /self:Receive\(requestId, kind, response, replyUserId\)/);
  assert.doesNotMatch(source + read(COMMANDS), /IsMakerPlay|IsMakerEdit|IsPublishedPlay/);
  assert.doesNotMatch(source, /_DataStorageService|_FormationStorage|_MonsterLevelStorage/);
});

test('the GM editor is client only and sends writes only through the RPC', () => {
  const source = read(PANEL);
  assert.doesNotMatch(source, /DataStorage|_FormationStorage|_MonsterLevelStorage|IsMakerPlay|IsMakerEdit|IsPublishedPlay|@Sync/);
  for (const method of source.matchAll(/method \w+ (\w+)\(/g)) {
    assert.match(source, new RegExp('@ExecSpace\\("ClientOnly"\\)\\s+method \\w+ ' + method[1] + '\\('));
  }
  assert.match(source, /_GMPanelService:Request\(/);
  assert.match(source, /requestId == self\._T\.activeRequest/);
  assert.match(source, /LoadTimeoutSeconds/);
  const save = body(source, 'Save');
  assert.match(save, /"SAVE_LEVELS"/);
  assert.match(body(source, 'Submit'), /self\._T\.loaded/);
  assert.match(body(source, 'Submit'), /self\._T\.expected/);
  assert.doesNotMatch(body(source, 'Submit'), /targetInput/);
  assert.match(body(source, 'Force'), /FORCE_SAVE_LEVELS/);
  assert.match(body(source, 'Reset'), /action = "RESET_LEVELS"/);
  assert.match(body(source, 'Delete'), /action = "DELETE_LEVELS"/);
  assert.match(body(source, 'Reload'), /self\._T\.loaded/);
  assert.match(save, /rows = edits/);
  assert.doesNotMatch(save, /raw =/);
  const repair = body(source, 'Repair');
  assert.match(repair, /"SAVE_LEVELS"/);
  assert.match(repair, /raw = self\.rawInput\.Text/);
  assert.doesNotMatch(repair, /rows =/);
  assert.match(body(source, 'Force'), /"FORCE_SAVE_LEVELS"/);
  assert.match(body(source, 'Reset'), /"RESET_LEVELS"/);
  assert.match(body(source, 'Delete'), /"DELETE_LEVELS"/);
  assert.match(source, /存檔在你開啟後已變動/);
  assert.match(source, /AUDIT_FAILED|AUDIT_INCOMPLETE|INVALID_PROGRESS|NOT_CORRUPT|BUSY/);
});

test('GM controls and every bound entity exist, with entry and panel hidden initially', () => {
  const ui = UIBuilder.read('ui/GMPanelGroup.ui');
  const source = read(PANEL);
  const bindings = [...source.matchAll(/property (Entity|ButtonComponent|TextGUIRendererInputComponent|TextGUIRendererComponent|ScrollLayoutGroupComponent) (\w+) = "([^"]*)"/g)];
  assert.ok(bindings.length >= 12, 'all UI references are checked, including empty defaults');
  for (const match of bindings) {
    const entity = ui.listEntities().find(e => ui.getId(e.path) === match[3]);
    assert.ok(entity, match[2] + ' binds an existing entity');
    if (match[1] !== 'Entity') assert.ok(ui.getComponent(entity.path, 'MOD.Core.' + match[1]));
  }
  for (const control of ['Panel/Window/Load', 'Panel/Window/Self', 'Panel/Window/Close',
      'Panel/Window/Save', 'Panel/Window/Reset', 'Panel/Window/Repair', 'Panel/Window/Delete',
      'Panel/Window/Force', 'Panel/Window/Reload']) {
    assert.ok(ui.getComponent(control, 'MOD.Core.ButtonComponent'), control);
  }
  assert.equal(ui.find('LobbyEntry').jsonString.enable, false);
  assert.equal(ui.getComponent('LobbyEntry', 'MOD.Core.TextGUIRendererComponent').Text, 'GM 面板');
  assert.equal(ui.find('Panel').jsonString.enable, false);
  assert.equal(ui.getComponent('Panel/Dimmer', 'MOD.Core.SpriteGUIRendererComponent').RaycastTarget, true);
  assert.equal(ui.getComponent('Panel/Window/Raw/Text', 'MOD.Core.TextGUIRendererComponent').IsRichText, false);
  assert.ok(ui.getComponent('Panel/Window/RepairInput', 'MOD.Core.TextGUIRendererInputComponent'));
  for (const name of ['LevelInput', 'ExperienceInput']) {
    const row = ui.listEntities().find(e => e.path.endsWith('/RowTemplate/' + name));
    assert.equal(row.enable, false, name);
  }
});

test('GM level writes validate through the command boundary and use the shared encoder', () => {
  const source = read(COMMANDS);
  const execute = body(source, 'Execute');
  assert.match(execute, /command\.kind == "SAVE_LEVELS"/);
  assert.match(execute, /command\.kind == "RESET_LEVELS"/);
  assert.match(execute, /command\.kind == "DELETE_LEVELS"/);
  assert.match(source, /_MonsterProgression:IsValidProgress\(/);
  assert.match(source, /_MonsterLevelStorage:Encode\(/);
  assert.match(source, /command\.kind == "FORCE_SAVE_LEVELS"/);
  assert.match(source, /command\.expected/);
  assert.match(source, /_FormationStorage:Write/);
});
