-- client, same fresh Play after gm_panel_runtime_probe.lua PASS and gm_panel_ui_fixture.lua READY.
-- Afterwards always run the fixture with CLEANUP=true in server_main, then stop Play.
local function await(predicate)
    for _ = 1, 150 do if predicate() then return true end wait(0.1) end
    return predicate()
end
local gm = _GMPanel
-- MonsterData is server-only. The server probe checks full catalog coverage; this client fixture has ten monsters.
local EXPECTED_COUNT = 10
local function click(button) button.Entity:SendEvent(ButtonClickEvent()) end
local function rows()
    local result = {}
    for _, child in ipairs(gm.listLayout.Entity.Children:ToTable()) do
        if string.sub(child.Name, 1, 6) == 'GMRow_' and child.Enable then table.insert(result, child) end
    end
    return result
end
local function ready() return #rows() == EXPECTED_COUNT and gm.loadButton.Enable end
local function lobbyState()
    local state = _FormationEditSession.Snapshot
    return table.concat({ tostring(state.editSlot), tostring(state.saved.activeSlot), tostring(_FormationEditSession:View().dirty), _MatchFlowInput.Snapshot.state }, '|')
end
local ok, detail = pcall(function()
    assert(await(function() return isvalid(gm.lobbyButton) and gm.lobbyButton.Enable and _MatchFlowInput:AllowsFormationActions()
        and _FormationEditSession.Snapshot.saved ~= nil end), 'GM lobby entry is ready')
    assert(not gm.panel.EnabledInHierarchy, 'panel starts closed')
    local before = lobbyState()
    -- Synthetic negative identity observation tests the visible non-GM state; the server probe tests real refusal.
    local denied = gm:RequestIdentity()
    gm:Observe(denied, 'IDENTITY', { status = 'FORBIDDEN' })
    assert(await(function() return not gm.lobbyButton.Entity.EnabledInHierarchy end), 'non-GM entry hidden')
    click(gm.lobbyButton)
    assert(not gm.panel.EnabledInHierarchy, 'forced button event cannot open a denied panel')
    gm:RequestIdentity()
    assert(await(function() return gm.lobbyButton.Entity.EnabledInHierarchy and gm.lobbyButton.Enable end), 'real server identity reveals entry')
    click(gm.lobbyButton)
    assert(not gm.loadButton.Enable, 'loading disables repeated requests')
    assert(await(ready) and gm.panel.EnabledInHierarchy, 'connected lobby button loads table')
    local count = #rows()
    local sawTank = false
    for _, row in ipairs(rows()) do
        local tank = string.find(row:GetChildByName('Name').TextGUIRendererComponent.Text, 'monster_tank', 1, true)
        if tank then sawTank = true end
        assert(row:GetChildByName('Level').TextGUIRendererComponent.Text == (tank and 'Lv6' or 'Lv1'), 'visible level')
        assert(row:GetChildByName('Experience').TextGUIRendererComponent.Text == (tank and '2' or '0'), 'visible experience')
    end
    assert(sawTank, 'the stored tank appears in the table')
    assert(gm.statusText.Text:find(_UserService.LocalPlayer.PlayerComponent.ProfileCode, 1, true), 'self profile shown')
    assert(rows()[1].UITransformComponent.RectSize.y * count > gm.listLayout.Entity.UITransformComponent.RectSize.y, 'table needs scrolling')
    gm.listLayout:SetScrollNormalizedPosition(UITransformAxis.Vertical, 1)
    assert(await(function() return gm.listLayout:GetScrollNormalizedPosition().y > 0.9 end), 'table scrolls')
    gm.targetInput.Text = 'GM84CORRUPT'
    click(gm.loadButton)
    assert(await(function() return gm.statusText.Text:find('存檔損壞', 1, true) ~= nil end), 'corrupt save marked')
    assert(gm.rawLayout.Entity.EnabledInHierarchy and gm.rawText.Text == 'broken <b>literal</b>\n{"schema":99}', 'raw text retained literally')
    assert(not gm.rawText.IsRichText and not gm.tableHeader.EnabledInHierarchy and #rows() == 0, 'no markup or stale valid table')
    gm.targetInput.Text = 'GM84ABSENT'
    click(gm.loadButton)
    assert(await(ready) and gm.statusText.Text:find('尚無存檔', 1, true), 'explicit absent target gets defaults')
    for _, row in ipairs(rows()) do
        assert(row:GetChildByName('Level').TextGUIRendererComponent.Text == 'Lv1'
            and row:GetChildByName('Experience').TextGUIRendererComponent.Text == '0', 'all missing-save rows default')
    end
    gm.targetInput.Text = '***'
    click(gm.loadButton)
    assert(await(function() return gm.statusText.Text == '玩家代碼格式無效' end) and #rows() == 0, 'invalid profile visible')
    click(gm.selfButton)
    assert(await(ready) and gm.rawText.Text == '' and not gm.rawLayout.Entity.Enable, 'myself restores valid target and clears raw text')
    local status = gm.statusText.Text
    gm:Observe(2147480000, 'LOAD_LEVELS', { status = 'READY', profile = 'stale', rows = {} })
    assert(gm.statusText.Text == status and #rows() == count, 'unmatched late reply ignored')
    click(gm.loadButton)
    click(gm.closeButton)
    wait(2)
    assert(not gm.panel.EnabledInHierarchy and #rows() == 0, 'close invalidates in-flight reply')
    click(gm.lobbyButton)
    assert(await(ready) and #rows() == count, 'reopen replaces rows without duplicates')
    click(gm.closeButton)
    assert(lobbyState() == before, 'viewer leaves formation and matchmaking unchanged')
end)
gm:Close()
if ok then log('[VRF][GMPanelUIProbe] PASS hidden; authorized; buttons; table; corrupt; defaults; self; stale reply; close')
else log_error('[VRF][GMPanelUIProbe] FAIL '..tostring(detail)) end
