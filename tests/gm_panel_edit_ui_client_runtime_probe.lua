-- client, same fresh Play after tests/gm_panel_edit_ui_fixture.lua logs READY.
-- Afterwards always rerun that fixture with CLEANUP=true in server_main, then stop Play.
local function await(predicate)
    for _ = 1, 150 do if predicate() then return true end wait(0.1) end
    return predicate()
end
local function click(button) button.Entity:SendEvent(ButtonClickEvent()) end
local gm = _GMPanel
local function rows()
    local result = {}
    for _, child in ipairs(gm.listLayout.Entity.Children:ToTable()) do
        if string.sub(child.Name, 1, 6) == 'GMRow_' and child.Enable then table.insert(result, child) end
    end
    return result
end
local function input(row, name) return row:GetChildByName(name).TextGUIRendererInputComponent end
local function tank()
    for _, row in ipairs(rows()) do
        if string.find(row:GetChildByName('Name').TextGUIRendererComponent.Text, 'monster_tank', 1, true) then return row end
    end
end
local ok, detail = pcall(function()
    assert(await(function() return isvalid(gm.lobbyButton) and gm.lobbyButton.Enable end), 'GM entry ready')
    click(gm.lobbyButton)
    assert(await(function() return tank() ~= nil and input(tank(), 'LevelInput').Text == '6' end), 'loaded editable level')
    input(tank(), 'LevelInput').Text = '7'
    local loaded = gm.targetInput.Text
    gm.targetInput.Text = 'GM85OTHER'
    input(tank(), 'ExperienceInput').Text = '1'
    click(gm.saveButton)
    assert(await(function() return gm.statusText.Text:find(loaded, 1, true) and input(tank(), 'LevelInput').Text == '7' end), 'save stays on loaded target')
    gm.targetInput.Text = loaded
    input(tank(), 'LevelInput').Text = '99'
    click(gm.saveButton)
    assert(await(function() return gm.statusText.Text:find('無效', 1, true) and input(tank(), 'LevelInput').Text == '7' end), 'invalid edit leaves save')
    click(gm.resetButton)
    assert(await(function() return input(tank(), 'LevelInput').Text == '1' and input(tank(), 'ExperienceInput').Text == '0' end), 'reset defaults')
    gm.targetInput.Text = 'GM85CORRUPT'
    click(gm.loadButton)
    assert(await(function() return gm.statusText.Text:find('存檔損壞', 1, true) and gm.rawText.Text:find('broken', 1, true) end), 'corrupt raw retained')
    gm.rawInput.Text = '{"schema":1,"monsters":{"monster_tank":{"level":3,"experience":1}},"settled":["gm85-repair"]}'
    click(gm.repairButton)
    assert(await(function() return gm.statusText.Text:find('已儲存', 1, true) and input(tank(), 'LevelInput').Text == '3' end), 'repair replaces corrupt save')
    gm.targetInput.Text = 'GM85ABSENT'
    click(gm.loadButton)
    assert(await(function() return gm.statusText.Text:find('尚無存檔', 1, true) end), 'absent target')
    click(gm.deleteButton)
    assert(not gm.deleteButton.Enable, 'healthy save cannot be deleted')
    gm.targetInput.Text = 'GM85CORRUPT'
    click(gm.loadButton)
    click(gm.deleteButton)
    assert(await(function() return gm.statusText.Text:find('存檔可讀', 1, true) end), 'repaired save refuses delete')
    local denied = { status = 'CONFLICT', profile = gm.targetInput.Text, expected = 'newer', rows = gm._T.rows }
    gm._T.pending = true
    gm._T.activeRequest = 8501
    gm._T.draft = { rows = { { monsterId = 'monster_tank', level = 4, experience = 0 } } }
    gm:Observe(8501, 'SAVE_LEVELS', denied)
    assert(gm.statusText.Text == '存檔在你開啟後已變動' and gm.forceButton.Enable and gm.reloadButton.Enable, 'conflict offers both choices')
    click(gm.reloadButton)
    assert(await(function() return gm.statusText.Text:find('已儲存', 1, true) or gm.statusText.Text:find('怪物等級', 1, true) end), 'reload reads current save')
    click(gm.closeButton)
end)
gm:Close()
if ok then log('[VRF][GMPanelEditUIProbe] PASS save; invalid; reset; repair; conflict; reload')
else log_error('[VRF][GMPanelEditUIProbe] FAIL ' .. tostring(detail)) end
