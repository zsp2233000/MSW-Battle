-- client. Use the server fixture TOKEN. After EDIT, run either RELOAD/FORCE or the RESTORE phases.
local TOKEN = ''
local MODE = 'EDIT'
assert(Environment:IsMakerPlay() and TOKEN:match('^%x+$') and #TOKEN == 8, 'Maker and a fresh synthetic token required')
local profile, damaged = 'GM85UI' .. TOKEN, 'GM85BAD' .. TOKEN
local gm = _GMPanel
local function await(predicate, message)
    for _ = 1, 150 do
        if predicate() then return end
        wait(0.1)
    end
    error(message .. ': ' .. gm.statusText.Text)
end
local function click(button)
    assert(isvalid(button) and button.Enable, 'button enabled')
    button.Entity:SendEvent(ButtonClickEvent())
end
local function tankInput(name)
    for _, row in ipairs(gm.listLayout.Entity.Children:ToTable()) do
        if row.Enable and row.Name:sub(1, 6) == 'GMRow_'
            and row:GetChildByName('Name').TextGUIRendererComponent.Text:find('monster_tank', 1, true) then
            return row:GetChildByName(name).TextGUIRendererInputComponent
        end
    end
end
local function tankLevel()
    local field = tankInput('LevelInput')
    return field and field.Text
end
local function hasStatus(value) return gm.statusText.Text:find(value, 1, true) ~= nil end
local function loadTarget(target, level)
    gm.targetInput.Text = target
    click(gm.loadButton)
    await(function() return hasStatus(target) and tankLevel() == level end, 'load ' .. target)
end
local function conflict(level)
    tankInput('LevelInput').Text = level
    click(gm.saveButton)
    await(function() return gm.statusText.Text == '存檔在你開啟後已變動' end, 'conflict prompt')
    assert(gm.forceButton.Enable and gm.reloadButton.Enable, 'both conflict choices enabled')
end
local function recordRow(index)
    return gm.historyLayout.Entity:GetChildByName('GMRecord_' .. index)
end
local function openHistory()
    click(gm.historyButton)
    await(function() return hasStatus('最新在前') and isvalid(recordRow(2)) end, 'operation history')
end
local function restoreConflict()
    click(recordRow(1):GetChildByName('Restore').ButtonComponent)
    await(function() return gm.statusText.Text == '存檔在你開啟後已變動' end, 'restore conflict')
    assert(gm.forceButton.Enable and gm.reloadButton.Enable, 'both restore conflict choices enabled')
end
local ok, detail = pcall(function()
    if MODE == 'EDIT' then
        await(function() return isvalid(gm.lobbyButton) and gm.lobbyButton.Enable end, 'GM entry')
        click(gm.lobbyButton)
        await(function() return gm.loadButton.Enable end, 'initial read')
        loadTarget(profile, '6')
        gm.targetInput.Text = damaged
        tankInput('LevelInput').Text = '7'
        tankInput('ExperienceInput').Text = '1'
        click(gm.saveButton)
        await(function() return hasStatus(profile) and hasStatus('已儲存') and tankLevel() == '7' end, 'save stays on loaded target')
        tankInput('LevelInput').Text = '31'
        click(gm.saveButton)
        await(function() return hasStatus('無效') and tankLevel() == '7' end, 'reject invalid level')
        click(gm.resetButton)
        await(function() return hasStatus('已儲存') and tankLevel() == '1' end, 'reset')
        gm.targetInput.Text = damaged
        click(gm.loadButton)
        await(function() return hasStatus('存檔損壞') and gm.rawText.Text == 'broken <b>literal</b>' end, 'literal corrupt save')
        gm.rawInput.Text = '{"schema":1,"monsters":{"monster_tank":{"level":3,"experience":1}},"settled":[]}'
        click(gm.repairButton)
        await(function() return hasStatus(damaged) and hasStatus('已儲存') and tankLevel() == '3' end, 'repair')
        assert(not gm.deleteButton.Enable, 'healthy save cannot be deleted')
        loadTarget(profile, '1')
    elseif MODE == 'RELOAD' then
        conflict('11')
        gm.targetInput.Text = damaged
        click(gm.reloadButton)
        await(function() return hasStatus(profile) and tankLevel() == '10' end, 'reload reads new version of loaded target')
    elseif MODE == 'FORCE' then
        conflict('13')
        click(gm.forceButton)
        await(function() return hasStatus(profile) and hasStatus('已儲存') and tankLevel() == '13' end, 'force preserves draft')
        click(gm.closeButton)
        assert(not gm.panel.Enable, 'panel closed')
    elseif MODE == 'RESTORE_START' then
        gm.targetInput.Text = damaged
        openHistory()
        assert(hasStatus(profile), 'history stays on loaded target')
        local label = recordRow(1):GetChildByName('Details').TextGUIRendererComponent.Text
        assert(label:find('6Y9NGB', 1, true) and label:find(' UTC', 1, true)
            and label:find('GM85UILevels', 1, true) and label:find('成功', 1, true), 'record shows GM, time, key and result')
    elseif MODE == 'RESTORE_RELOAD' then
        restoreConflict()
        click(gm.reloadButton)
        await(function() return hasStatus(profile) and tankLevel() == '10' end, 'restore reload reads new version')
        openHistory()
    elseif MODE == 'RESTORE_FORCE' then
        restoreConflict()
        click(gm.forceButton)
        await(function() return hasStatus(profile) and hasStatus('已還原') and tankLevel() == '7' end, 'force restores the latest record before-content')
        openHistory()
        local label = recordRow(1):GetChildByName('Details').TextGUIRendererComponent.Text
        assert(label:find('還原 · 成功', 1, true), 'restore has a new visible operation record')
        click(gm.closeButton)
        assert(not gm.panel.Enable, 'panel closed')
    else
        error('unknown probe phase')
    end
end)
if not ok then
    gm:Close()
    log_error('[VRF][GMPanelEditUIProbe] FAIL ' .. MODE .. ' ' .. tostring(detail))
elseif MODE == 'FORCE' then
    log('[VRF][GMPanelEditUIProbe] PASS edit; invalid; reset; repair; conflict; reload; force')
elseif MODE == 'RESTORE_FORCE' then
    log('[VRF][GMPanelEditUIProbe] RESTORE_PASS history; restore conflict; reload; force; new record')
else
    log('[VRF][GMPanelEditUIProbe] ' .. MODE .. '_PASS')
end
