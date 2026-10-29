-- Client after server temporarily selects an unused FormationService.StorageKey. No writes.
local function await(predicate)
    for index = 1, 100 do if predicate() then return true end wait(0.1) end
    return false
end
local l = _FormationLobby
local ok, detail = pcall(function()
    _FormationService:RequestRetryLoad()
    assert(await(function() return l.Snapshot.loadState == 'NEW' end), 'missing data is a new player')
    wait(0.2)
    assert(l.Snapshot.saved.activeSlot == 0, 'no active formation')
    assert(_MatchProbeInput.action.TextGUIRendererComponent.Text == '前往整備' and _MatchProbeInput.action.ButtonComponent.Enable, 'new player main action')
    assert(l:Ui('Lobby/Command/Field/Empty').EnabledInHierarchy, 'empty preview explains preparation')
    for index = 1, 6 do assert(not l:Ui('Lobby/Command/Field/Unit'..tostring(index)).Enable, 'no fake roster') end
    _MatchProbeInput.action:SendEvent(ButtonClickEvent())
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationsim' end), 'main action reaches real simulation')
    assert(_MatchProbeInput.State == 'IDLE', 'preparation does not queue')
    l:Ui('Editor/Back'):SendEvent(ButtonClickEvent())
    wait(0.3)
    if l:Ui('ExitConfirm').EnabledInHierarchy then l:Ui('ExitConfirm/Window/ReturnWithoutSave'):SendEvent(ButtonClickEvent()) end
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationlobby' end), 'new player returns')
    log('[VRF][LobbyEmpty] PASS no fake roster; preparation CTA; simulation round trip; no queue')
end)
if not ok then log('[VRF][LobbyEmpty] FAIL ' .. tostring(detail)) end
