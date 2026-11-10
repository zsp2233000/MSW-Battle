-- client, after server fixture FAILURE or CORRUPT. CORRUPT remains failed on retry.
local MODE = 'FAILURE'
local function await(predicate)
    for _ = 1, 100 do if predicate() then return true end wait(0.1) end
    return false
end
local l = _FormationLobby
local ok, detail = pcall(function()
    _FormationService:RequestRetryLoad()
    assert(await(function() return _FormationEditSession.Snapshot.levelLoadState == 'ERROR' end), 'explicit failure')
    for _, option in ipairs(_FormationEditSession.Snapshot.options) do
        assert(option.level == nil and option.experience == nil and option.maxHp == nil
            and option.attackDamageMin == nil and option.attackDamageMax == nil, 'no counterfeit Lv1 or stale stats')
    end
    local inEditor = _UserService.LocalPlayer.CurrentMapName == 'formationsim'
    local retry = inEditor and 'EditorControls/Retry' or 'Retry'
    local status = inEditor and 'EditorControls/Status' or 'Status'
    assert(l:Ui(retry).EnabledInHierarchy, 'retry available')
    assert(string.find(l:Ui(status).TextGUIRendererComponent.Text, '怪物等級讀取失敗', 1, true), 'failure visible')
    if inEditor then
        assert(l:Ui('Editor/Intel/Stats/Health/Value').TextGUIRendererComponent.Text == '—', 'no stale health')
        assert(l:Ui('Editor/Intel/Stats/Damage/Value').TextGUIRendererComponent.Text == '—', 'no stale damage')
    end
    if MODE == 'FAILURE' then
        l:Ui(retry):SendEvent(ButtonClickEvent())
        assert(await(function() return _FormationEditSession.Snapshot.levelLoadState == 'READY' end), 'retry recovers')
    end
end)
log(ok and '[VRF][EditorLevels] '..MODE..'_UI PASS' or '[VRF][EditorLevels] '..MODE..'_UI FAIL '..tostring(detail))
