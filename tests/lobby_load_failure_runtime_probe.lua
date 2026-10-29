-- Client, after server ConfigureMakerFaults(1, 0, 0). No storage writes.
local function await(predicate)
    for index = 1, 100 do if predicate() then return true end wait(0.1) end
    return false
end
local l = _FormationLobby
local ok, detail = pcall(function()
    local saved = _FormationSchema:EncodeDocument(l.Snapshot.saved)
    local draft = _FormationSchema:CopyUnits(l.Snapshot.draft)
    _FormationService:RequestRetryLoad()
    assert(await(function() return l.Snapshot.loadState == 'ERROR' end), 'injected read failure')
    wait(0.2)
    assert(l:Ui('Retry').EnabledInHierarchy and l:Ui('Retry').ButtonComponent.Enable, 'retry visible and usable')
    assert(not _MatchProbeInput.action.ButtonComponent.Enable and not l:Ui('Lobby/Edit').ButtonComponent.Enable, 'unconfirmed data cannot start an operation')
    assert(string.find(l:Ui('Lobby/Command/Field/Empty').TextGUIRendererComponent.Text, '重試讀取'), 'preview explains read failure')
    assert(_FormationSchema:EncodeDocument(l.Snapshot.saved) == saved and _FormationSchema:SameUnits(l.Snapshot.draft,draft), 'saved data and draft retained')
    l:Ui('Retry'):SendEvent(ButtonClickEvent())
    assert(await(function() return l.Snapshot.loadState == 'READY' end), 'connected retry recovers')
    wait(0.2)
    assert(_MatchProbeInput.action.ButtonComponent.Enable and not l:Ui('Retry').Enable, 'recovered controls')
    log('[VRF][LobbyLoadFailure] PASS failure explanation; disabled actions; retry; retained data')
end)
if not ok then log('[VRF][LobbyLoadFailure] FAIL ' .. tostring(detail)) end
