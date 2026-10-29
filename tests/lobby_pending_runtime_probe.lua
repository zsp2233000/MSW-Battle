-- Client after lobby_draft probe and server ConfigureMakerFaults(0, 1, 1).
-- The storage boundary rejects the only attempted write before touching persisted data.
local function await(predicate)
    for index = 1, 100 do if predicate() then return true end wait(0.1) end
    return false
end
local l = _FormationLobby
local ok, detail = pcall(function()
    assert(l.Snapshot.draftValid and l.Snapshot.slots[tostring(l.Snapshot.editSlot)].dirty, 'valid unsaved fixture')
    local saved = _FormationSchema:EncodeDocument(l.Snapshot.saved)
    local draft = _FormationSchema:CopyUnits(l.Snapshot.draft)
    l:Ui('Editor/Save'):SendEvent(ButtonClickEvent())
    assert(await(function() return l.Snapshot.pending end), 'save pending')
    wait(0.2)
    assert(not _MatchProbeInput.action.ButtonComponent.Enable and not l:Ui('Lobby/Edit').ButtonComponent.Enable, 'pending controls disabled')
    assert(not l:Ui('Lobby/Slots/Slot2').ButtonComponent.Enable, 'pending selector disabled')
    local selected = l.Snapshot.editSlot
    l:Ui('Lobby/Slots/Slot2'):SendEvent(ButtonClickEvent())
    wait(0.1)
    l:Ui('Lobby/Slots/Slot2'):SendEvent(ButtonClickEvent())
    assert(l.Snapshot.editSlot == selected and _UserService.LocalPlayer.CurrentMapName == 'formationlobby', 'pending write blocks double-click entry')
    assert(string.find(_MatchProbeInput.status.TextGUIRendererComponent.Text,'確認'), 'pending reason')
    assert(await(function() return l.Snapshot.saveState == 'FAILED' and not l.Snapshot.pending end), 'injected save failure')
    assert(_FormationSchema:EncodeDocument(l.Snapshot.saved) == saved and _FormationSchema:SameUnits(l.Snapshot.draft,draft), 'failure retains confirmed roster and draft')
    log('[VRF][LobbyPending] PASS pending controls; explanation; failed save retains saved roster and draft')
end)
if not ok then log('[VRF][LobbyPending] FAIL ' .. tostring(detail)) end
