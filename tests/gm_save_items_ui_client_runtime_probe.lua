-- client. Use the server fixture TOKEN after READY, then always clean up in server_main.
local TOKEN = ''
assert(Environment:IsMakerPlay() and #TOKEN == 8 and TOKEN:match('^%x+$'), 'Maker and synthetic token required')
local gm, profile = _GMPanel, 'GM87UI' .. TOKEN
local function await(predicate, label)
    for _ = 1, 150 do if predicate() then return end wait(0.1) end
    error(label .. ': ' .. gm.statusText.Text)
end
local function clickable(button) return isvalid(button) and button.Enable and button.Entity.EnabledInHierarchy end
local function click(button)
    assert(clickable(button), 'visible clickable control')
    button.Entity:SendEvent(ButtonClickEvent())
end
local function status(part) return gm.statusText.Text:find(part, 1, true) ~= nil end

await(function() return clickable(gm.lobbyButton) end, 'GM entry')
click(gm.lobbyButton)
await(function() return clickable(gm.loadButton) end, 'initial read')
gm.targetInput.Text = profile
click(gm.loadButton)
await(function() return status(profile) and clickable(gm.formationsTab) end, 'load synthetic target')
click(gm.formationsTab)
await(function() return status('存檔損壞') and clickable(gm.formationSaveButton) end, 'corrupt formation editor')
assert(gm.formationWarning.Entity.EnabledInHierarchy and gm.formationWarning.Text:find('重新登入', 1, true)
    and gm.formationWarning.Text:find('儲存會失敗', 1, true), 'online warning while editing')
assert(gm.rawLayout.Entity.EnabledInHierarchy and gm.rawText.Text == 'broken <b>literal</b>', 'raw corruption')
gm.formationInput.Text = '{"schema":2}'
click(gm.formationSaveButton)
await(function() return status('JSON 無效') and clickable(gm.formationSaveButton) end, 'invalid edit')
assert(gm.formationInput.Text == '{"schema":2}', 'invalid draft can be corrected')

local valid = '{"schema":2,"revision":0,"activeSlot":0,"slots":{"1":{"id":1,"revision":0,"units":[]},'
    .. '"2":{"id":2,"revision":0,"units":[]},"3":{"id":3,"revision":0,"units":[]},'
    .. '"4":{"id":4,"revision":0,"units":[]},"5":{"id":5,"revision":0,"units":[]}}}'
gm.formationInput.Text = valid
click(gm.formationSaveButton)
await(function() return status('已儲存') and clickable(gm.formationSaveButton) end, 'formation saved')
assert(gm.formationInput.Text == valid, 'saved JSON retained')
click(gm.deleteButton)
await(function() return status('已清空預存編隊') and clickable(gm.handoffTab) end, 'formation cleared')
assert(not clickable(gm.deleteButton), 'absent formation has no delete')

click(gm.handoffTab)
await(function() return status('配對交接資料（唯讀）') and clickable(gm.deleteButton) end, 'handoff loaded')
assert(gm.rawLayout.Entity.EnabledInHierarchy and gm.rawText.Text == '{"state":"TRANSFER","probe":true}', 'handoff bytes')
assert(not gm.formationInput.Entity.EnabledInHierarchy and not gm.rawInput.Entity.EnabledInHierarchy
    and not clickable(gm.formationSaveButton) and not clickable(gm.repairButton) and not clickable(gm.saveButton), 'handoff has no editor')
click(gm.deleteButton)
await(function() return status('已刪除') and clickable(gm.historyButton) end, 'handoff deleted')
click(gm.historyButton)
await(function() return status('最新在前') and gm.historyLayout.Entity.EnabledInHierarchy end, 'shared operation record list')
local function record(index) return gm.historyLayout.Entity:GetChildByName('GMRecord_' .. index) end
assert(record(1):GetChildByName('Details').TextGUIRendererComponent.Text:find('配對交接資料', 1, true), 'handoff deletion evident')
assert(not record(1):GetChildByName('Restore').EnabledInHierarchy, 'handoff audit row has no restore action')
assert(record(2):GetChildByName('Details').TextGUIRendererComponent.Text:find('預存編隊', 1, true), 'formation deletion evident')
click(record(2):GetChildByName('Restore').ButtonComponent)
await(function() return status('已還原') and clickable(gm.formationSaveButton) end, 'restore across items')
assert(gm.formationInput.Text == valid, 'exact formation restored')
click(gm.closeButton)
log('[VRF][GMSaveItemsUIProbe] PASS edit; warning; raw; clear; read-only handoff; delete; history; restore')
